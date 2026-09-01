#!/usr/bin/env bash
# Make room for `arize.sh pull-images`, which stages 26 images through the
# local Docker daemon before pushing them to ECR.
#
# Two things bit us on 2026-08-30 (run 33302654578):
#
#   1. This script assumed ubuntu-latest keeps a large /mnt and moved Docker's
#      data-root there. On a runner without a separate /mnt, /mnt/docker is a
#      directory on / — so the move bought nothing, but the old check passed
#      because `docker info` did report /mnt/docker. Verify free bytes, not
#      the path string.
#
#   2. The runner image ships ~59 GB of pre-installed content on a 72 GB disk:
#      cached Docker images, .NET, Android, GHC, Swift, and the tool cache.
#      None of it is needed to pull and push images, and clearing it is worth
#      more than any relocation.
#
# Fail closed: a pull that runs out of disk halfway wastes 30 minutes of
# retries and then times out, which is what happened.
set -euo pipefail

# Grounded in the real bundle: ~7 GB on disk, of which 6.1 GB is compressed
# image tarballs. Those expand roughly 2-2.5x once they are layers in the
# Docker store, and the bundle stays on disk alongside them — call it 25 GB.
# 30 keeps headroom for a larger release. The run that actually died mid-pull
# (33302654578) had 13 GB.
REQUIRED_GB="${REQUIRED_GB:-30}"

avail_gb() { df -BG --output=avail "$1" | tail -1 | tr -dc '0-9'; }
report()   { echo "▶ $1:"; df -h / /mnt 2>/dev/null || df -h /; }

report "Disk before"
before="$(avail_gb /)"

# Pre-installed toolchains. Irrelevant to pulling and pushing container images;
# `|| true` because the set varies by runner image and a missing path is fine.
echo "▶ Removing pre-installed toolchains"
sudo rm -rf \
  /usr/share/dotnet \
  /usr/local/lib/android \
  /opt/ghc \
  /usr/local/share/boost \
  /usr/local/share/powershell \
  /usr/share/swift \
  /opt/hostedtoolcache/CodeQL \
  2>/dev/null || true

# Images the runner image ships with (node, buildpack-deps, ...). Ours are not
# pulled yet, so nothing we need can be removed here.
echo "▶ Clearing the pre-seeded Docker cache"
docker system prune -af --volumes 2>/dev/null || true

# Only relocate when /mnt is genuinely a different, roomier filesystem.
mnt_dev="$(df --output=source /mnt 2>/dev/null | tail -1 || true)"
root_dev="$(df --output=source / | tail -1)"
if [ -n "${mnt_dev}" ] && [ "${mnt_dev}" != "${root_dev}" ] && [ "$(avail_gb /mnt)" -gt "$(avail_gb /)" ]; then
  echo "▶ /mnt is a separate volume with more room; moving Docker there"
  sudo systemctl stop docker.socket docker || sudo systemctl stop docker
  sudo mkdir -p /mnt/docker
  printf '{\n  "data-root": "/mnt/docker"\n}\n' | sudo tee /etc/docker/daemon.json
  sudo systemctl start docker
  sudo systemctl is-active --quiet docker
  target=/mnt
else
  echo "▶ No separate /mnt volume; Docker stays on / with the space just freed"
  target=/
fi

echo "▶ Docker root: $(docker info --format '{{.DockerRootDir}}')"
report "Disk after"

free_gb="$(avail_gb "${target}")"
echo "▶ Freed $(( free_gb - before )) GB; ${free_gb} GB available on ${target}"
if [ "${free_gb}" -lt "${REQUIRED_GB}" ]; then
  echo "🛑 only ${free_gb} GB free on ${target}, need ${REQUIRED_GB} GB for the 26 images plus the bundle" >&2
  echo "   Raise REQUIRED_GB only if you know the bundle is smaller." >&2
  exit 1
fi
