#!/usr/bin/env bash
# Verifies rendering injects only the sensitive fields and fails closed.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export ARIZE_HUB_JWT=jwt ARIZE_CIPHER_KEY=cipher ARIZE_POSTGRES_PASSWORD=pg \
       ARIZE_SMTP_USER=smtpu ARIZE_SMTP_PASSWORD=smtpp ARIZE_GCP_SA_KEY=gcp \
       ARIZE_INTERNAL_TLS_CERT=ic ARIZE_INTERNAL_TLS_KEY=ik \
       ARIZE_FLIGHT_TLS_CERT=fc ARIZE_FLIGHT_TLS_KEY=fk

scripts/render-values.sh "$tmp/values.yaml"

grep -q 'hubJwt: "jwt"' "$tmp/values.yaml" || { echo "FAIL: hubJwt not substituted"; exit 1; }
grep -q 'pushRegistry:' "$tmp/values.yaml" || { echo "FAIL: pushRegistry missing"; exit 1; }
grep -q 'clusterName: "arn:aws:eks:ap-northeast-2:507911341146:cluster/sean-test"' "$tmp/values.yaml" \
  || { echo "FAIL: clusterName changed"; exit 1; }
grep -q 'region: "ap-northeast-2"' "$tmp/values.yaml" || { echo "FAIL: region changed"; exit 1; }
grep -q 'pushRegistry: "507911341146.dkr.ecr.ap-northeast-2.amazonaws.com"' "$tmp/values.yaml" \
  || { echo "FAIL: pushRegistry changed"; exit 1; }
! grep -qE '\$\{ARIZE_[A-Z_]+\}' "$tmp/values.yaml" || { echo "FAIL: placeholders remain"; exit 1; }

# Fails closed when a required secret is absent.
( unset ARIZE_HUB_JWT; scripts/render-values.sh "$tmp/other.yaml" ) 2>/dev/null \
  && { echo "FAIL: missing secret did not fail"; exit 1; }

echo "PASS: render-values.sh"
