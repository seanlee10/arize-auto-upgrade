#!/usr/bin/env bash
# Render the checked-in values.yaml with GitHub Environment Secrets.
# Usage: scripts/render-values.sh <output-path>
#
# Never cat or log the output: it contains private keys and passwords.
set -euo pipefail

OUTPUT="${1:?usage: render-values.sh <output-path>}"
TEMPLATE="$(dirname "$0")/../values.yaml"

# Secrets only. Everything else is literal in values.yaml, which is
# checked in so the non-secret config is reviewable in a diff.
# Missing any of these must fail closed and name it.
REQUIRED=(
  ARIZE_HUB_JWT
  ARIZE_CIPHER_KEY
  ARIZE_POSTGRES_PASSWORD
  ARIZE_SMTP_USER
  ARIZE_SMTP_PASSWORD
  ARIZE_GCP_SA_KEY
  ARIZE_INTERNAL_TLS_CERT
  ARIZE_INTERNAL_TLS_KEY
  ARIZE_FLIGHT_TLS_CERT
  ARIZE_FLIGHT_TLS_KEY
)

missing=()
for name in "${REQUIRED[@]}"; do
  if [ -z "${!name:-}" ]; then missing+=("$name"); fi
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "🛑 missing required variables/secrets: ${missing[*]}" >&2
  exit 1
fi

# Every non-secret value is literal in the checked-in file, so the only
# substitutions are the secrets above.
ALL_VARS=("${REQUIRED[@]}")

# Restrict substitution to our own variables so unrelated '$' in the
# template is left alone.
substitutions=""
for name in "${ALL_VARS[@]}"; do substitutions="${substitutions}\${${name}}"; done

envsubst "$substitutions" < "$TEMPLATE" > "$OUTPUT"
chmod 600 "$OUTPUT"

if grep -qE '\$\{ARIZE_[A-Z_]+\}' "$OUTPUT"; then
  echo "🛑 unsubstituted placeholders remain in the rendered values file" >&2
  exit 1
fi

echo "✅ rendered $(wc -l < "$OUTPUT") lines to $OUTPUT"
