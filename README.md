# Arize Auto-Upgrade

Automated upgrade pipeline for a self-hosted Arize AX cluster on EKS, with two human approval gates in Slack or Microsoft Teams.

## How it works

1. **On demand** (the daily schedule is currently disabled — see *Approval gates* below), `check-release.yml` parses <https://arize.com/docs/ax/selfhosting/on-premise-releases.md> and compares the newest release against the deployed version.
2. If a newer release exists it dispatches `upgrade.yml`, which posts the release and every intervening **Upgrade Notes** section to chat with an **Approve image push** button.
3. After approval, images are pulled from `ch.hub.arize.com` and pushed to ECR.
4. Chat gets a second message with an **Approve install** button.
5. After approval, `./arize.sh install` runs, gated on `install-status`.
6. Chat gets the result with an **Open Arize** button, and a GitHub Release tagged `deployed/<version>` records the new state.

> **Approval gates are not enforced right now.** GitHub only enforces
> required reviewers on an environment for public repositories or paid plans.
> This repo is private on a free plan, so the two `environment:` declarations
> are labels that do not block. The daily schedule in `check-release.yml` is
> disabled for that reason: nothing should start an upgrade on its own while
> the gates are inert. **A manual run of `upgrade.yml` will still proceed
> through both stages without pausing for approval.** To restore enforcement,
> make the repo public or upgrade the plan, then re-add required reviewers to
> the `image-push` and `cluster-install` environments.

Approvals use **GitHub Environments**, so every button is a link into the run's approval page. That is why Slack and Teams are interchangeable — and why nothing here needs a public HTTPS endpoint or request-signature verification.

## Read this before running it

This tool upgrades a production cluster. Three properties are worth knowing up front:

- **There is no rollback.** Upgrades run irreversible Postgres, Druid, and gazette init jobs. A failure notifies loudly and stops; recovery is a human decision using `arize.sh backup-db-local` and `restore-from-*`.
- **It jumps straight to latest.** The vendor's `get_latest.sh` only ever serves the newest release, so intermediate versions cannot be pinned. Every intervening Upgrade Notes section is surfaced at approval time so a human sees the breaking changes before saying yes.
- **The approved version is verified after download.** Because "latest" is a moving target, the job re-checks that what it downloaded is what was approved, and aborts if a newer release landed mid-run.

## Setup

The complete deployment configuration is checked in at `values.yaml`. It is the
single source of truth for the cluster, registry, URLs, and Arize credentials used by
the workflow. Keep this repository private and rotate the file's credentials if it is
ever exposed.

### 1. Get your own private copy of this repo

Run the pipeline from **your own private copy**, never from this repository. That copy is what carries your cluster's identity: the EKS cluster ARN, the ECR registry, the hub JWT, and every Variable and Secret in the next two steps are set on it, not here.

Private matters because those Secrets grant push access to your ECR and install rights on a production EKS cluster, and the Actions logs describe your cluster's topology.

**If you can see this repository while it is private,** a fork inherits that visibility and is already private:

```bash
gh repo fork <owner>/arize-upgrade --clone --fork-name arize-upgrade
```

**If you are copying from a public source, a fork will not work.** GitHub forks inherit the parent's visibility, and a fork of a public repository cannot be switched to private afterwards. Duplicate it into a fresh private repo instead:

```bash
gh repo create <your-org>/arize-upgrade --private
git clone --bare https://github.com/<owner>/arize-upgrade.git
cd arize-upgrade.git
git push --mirror https://github.com/<your-org>/arize-upgrade.git
```

Either way, add the source as an `upstream` remote to pull in later pipeline fixes. Your Variables, Secrets and environments live in GitHub settings rather than in the code, so they survive that merge untouched.

> **A private copy on a free plan has no working approval gates.** GitHub enforces
> required reviewers only for public repositories or paid plans — see the callout
> under *How it works*. On a Team or Enterprise plan the gates behave as designed;
> on a free plan, leave the daily schedule disabled and treat every `upgrade.yml`
> run as unattended.

### 2. Repository variables

Only the pipeline's small set of control variables is required.

**Workflow variables**:

| Variable | Example | Purpose |
|---|---|---|
| `NOTIFY_PROVIDER` | `slack_webhook` | `slack`, `teams`, or `slack_webhook`. |
| `DEPLOYED_VERSION` | `11.41.0` | Bootstrap only; ignored once a `deployed/*` Release exists. |

The workflow derives the AWS region, cluster name, ECR registry, and application URL
from `values.yaml`. The install job still verifies the cluster ARN against AWS
before touching `kubectl`.

```bash
gh variable set NOTIFY_PROVIDER --body slack
gh variable set DEPLOYED_VERSION --body 11.41.0
```

The pipeline **never guesses** the deployed version. On the very first run there is no `deployed/*` Release, so `DEPLOYED_VERSION` must be seeded or the check fails with instructions.

### 3. Secrets

Set on **both** the `image-push` and `cluster-install` environments:

| Secret | Notes |
|---|---|
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Default AWS authentication path. |

The workflow injects the sensitive fields from Environment Secrets into a temporary
runner-only `values.yaml`. The base64 `hubJwt` Secret is decoded for the distribution
download. GitHub OIDC is not enabled by default.

`SLACK_WEBHOOK_URL` is a repository-level Secret and is used by the selected
`slack_webhook` provider.

### 4. Environments

Create two environments, each with **required reviewers**:

- `image-push` — gates pulling and pushing images
- `cluster-install` — gates touching the cluster

**Without reviewers configured the jobs run unattended and there are no approvals at all.** This is the single easiest thing to get wrong.

### 5. Chat

**Slack:** create an app with the `chat:write` bot scope, install it, invite it to the channel, then set `SLACK_BOT_TOKEN` (`xoxb-…`) and `SLACK_CHANNEL_ID`. All four messages of an upgrade thread under the first.

**Teams:** in the target channel add a **Workflows** flow from the "post to a channel when a webhook request is received" template, then set `TEAMS_WEBHOOK_URL`. Microsoft retired Office 365 Connectors, so the older `outlook.office.com/webhook/...` URLs are not the path here. Teams webhooks cannot thread, so each stage arrives as its own self-contained card.

**Slack (incoming webhook):** if your Slack app only carries the `incoming-webhook` scope rather than `chat:write`, use `NOTIFY_PROVIDER=slack_webhook` instead of `slack`. Create an incoming webhook (Slack app settings → **Incoming Webhooks** → **Add New Webhook to Workspace**) and set `SLACK_WEBHOOK_URL` (e.g. `https://hooks.slack.com/services/T000/B000/xxxx`) — nothing else. No bot token, no channel invite, and no `SLACK_CHANNEL_ID`, since the channel is fixed at webhook creation. Like Teams, incoming webhooks cannot thread, so the four upgrade messages arrive as separate posts rather than a thread; use the bot-token `slack` provider instead if you want threading.

### 6. values.yaml

Upload or edit the complete vendor configuration at `values.yaml` in the
private repository. The workflow copies it into the downloaded distribution without
substituting GitHub Secrets. It must include the pipeline-specific `pushRegistry` and
`repoName` keys so images are pushed to the intended ECR repository.

```bash
grep -E '^(clusterName|region|hubJwt|pushRegistry|repoName):' values.yaml
```

This file contains credentials and private keys. Never publish the repository or print
the file in workflow logs.

## Prerequisites this repo cannot solve

- The EKS API endpoint must be reachable from GitHub-hosted runners.
- The IAM principal must be mapped in EKS access entries with rights to install.
- A valid Arize hub JWT.

## Operational notes

- **Disk.** `pull-images` stages 26 container images through the local Docker daemon. `ubuntu-latest` has ~14 GB free on `/` but ~65 GB on `/mnt`, so `scripts/prepare-runner-disk.sh`  relocates Docker's `data-root` before the pull. If a future release still overflows, switch to `./arize.sh -y -q --skopeo load-remote-images`, which copies registry-to-registry and uses no local disk.
- **Concurrency.** A run paused at an approval gate reports GitHub status `waiting`. The scheduled check treats `waiting`, `queued` and `in_progress` alike as "an upgrade is active", and treats a failed `gh` call the same way, so neither a long approval wait nor a GitHub outage can trigger a second concurrent upgrade.
- **Approvals expire.** GitHub cancels a run awaiting approval after 30 days; the next scheduled check re-detects and re-dispatches.
- **Parsing, not an API.** The release notes are parsed from the docs site's markdown twin. Zero parsed releases is always a hard failure with an alert — a docs redesign must never look like "no new release".

## Development

```bash
python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/pytest -q
```

Tests never touch the network or a cluster: every external boundary is an injected callable with a real default and a fake in tests. See `CLAUDE.md` for the architecture and the conventions worth knowing before changing anything.

### Enable the credential pre-commit hook

The checked-in `values.yaml` must contain empty or placeholder values for credential
fields. Enable the repository hook once per clone:

```bash
git config core.hooksPath .githooks
```

The hook checks staged content for PEM material and non-empty sensitive fields before
allowing a commit.
