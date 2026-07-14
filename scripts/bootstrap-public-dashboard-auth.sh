#!/usr/bin/env bash
# Initialize or rotate public dashboard credentials without putting the raw
# password in Terraform state, SSM Parameter Store, a file, or command output.
#
# Usage:
#   AWS_PROFILE=my-profile ./scripts/bootstrap-public-dashboard-auth.sh
#   AWS_PROFILE=my-profile ./scripts/bootstrap-public-dashboard-auth.sh i-0123456789abcdef0
#
# The script reads the applied resource names from Terraform outputs. Set
# TF_ROOT when the calling root module lives outside this repository.

set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermes-ssm-lib.sh
source "$ROOT/scripts/hermes-ssm-lib.sh"

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [i-INSTANCE_ID]" >&2
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this canonical bootstrap stores the password in macOS Keychain and must run on macOS." >&2
  exit 1
fi

for cmd in aws terraform python3 security; do
  hermes_require_cmd "$cmd"
done

TF_ROOT="${TF_ROOT:-$ROOT}"

tf_output() {
  local name="$1"
  local value

  if ! value=$(terraform -chdir="$TF_ROOT" output -raw "$name" 2>/dev/null); then
    echo "error: cannot read Terraform output '$name' from $TF_ROOT" >&2
    echo "Run terraform apply first, or point TF_ROOT at the applied root module." >&2
    exit 1
  fi
  printf '%s' "$value"
}

AUTH_MODE=$(tf_output public_dashboard_auth_mode)
if [[ "$AUTH_MODE" != "basic" ]]; then
  echo "error: this bootstrap only applies to public_dashboard_auth_mode = \"basic\" (current: $AUTH_MODE)." >&2
  exit 1
fi

DOMAIN="${PUBLIC_DASHBOARD_DOMAIN:-$(tf_output public_dashboard_domain)}"
USERNAME="${PUBLIC_DASHBOARD_USERNAME:-$(tf_output public_dashboard_basic_auth_username)}"
HERMES_HASH_PARAMETER="${PUBLIC_DASHBOARD_HERMES_HASH_SSM_PARAMETER_NAME:-$(tf_output public_dashboard_hermes_hash_ssm_parameter_name)}"
SESSION_SECRET_PARAMETER="${PUBLIC_DASHBOARD_SESSION_SECRET_SSM_PARAMETER_NAME:-$(tf_output public_dashboard_session_secret_ssm_parameter_name)}"
HERMES_DEPLOYMENT_NAME="${HERMES_DEPLOYMENT_NAME:-$(tf_output deployment_name)}"
export HERMES_DEPLOYMENT_NAME

if [[ ! "$DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; then
  echo "error: public_dashboard_domain output is not a valid DNS name." >&2
  exit 1
fi
if [[ ! "$USERNAME" =~ ^[A-Za-z0-9._@-]{1,64}$ ]]; then
  echo "error: public dashboard username has an invalid format." >&2
  exit 1
fi
for parameter_name in "$HERMES_HASH_PARAMETER" "$SESSION_SECRET_PARAMETER"; do
  if [[ ! "$parameter_name" =~ ^/[A-Za-z0-9_.\/-]+$ ]]; then
    echo "error: Terraform returned an invalid SSM parameter name." >&2
    exit 1
  fi
done

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ -z "$REGION" ]]; then
  REGION=$(aws configure get region 2>/dev/null || true)
fi
if [[ -z "$REGION" ]]; then
  echo "error: no AWS region configured; set AWS_REGION or configure one for AWS_PROFILE." >&2
  exit 1
fi
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"

aws sts get-caller-identity --query Account --output text >/dev/null

for parameter_name in "$HERMES_HASH_PARAMETER" "$SESSION_SECRET_PARAMETER"; do
  aws ssm get-parameter --name "$parameter_name" --query 'Parameter.Name' --output text >/dev/null
done

PASSWORD=""
HERMES_HASH=""
SESSION_SECRET=""
cleanup() {
  unset PASSWORD HERMES_HASH SESSION_SECRET
}
trap cleanup EXIT HUP INT TERM

# URL-safe random text avoids shell metacharacter ambiguity while retaining
# 384 bits of entropy. It exists only in this process and child stdin streams.
PASSWORD=$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')

# This exactly matches Hermes v2026.7.7.2 plugins/dashboard_auth/basic:
# hashlib.scrypt(n=2**14, r=8, p=1, dklen=32), 16-byte salt, standard base64.
HERMES_HASH=$(printf '%s' "$PASSWORD" | python3 -c '
import base64
import hashlib
import secrets
import sys

password = sys.stdin.buffer.read()
salt = secrets.token_bytes(16)
derived = hashlib.scrypt(password, salt=salt, n=2**14, r=8, p=1, dklen=32, maxmem=0)
print(f"scrypt$16384$8$1${base64.b64encode(salt).decode()}${base64.b64encode(derived).decode()}")
')
if [[ ! "$HERMES_HASH" =~ ^scrypt\$16384\$8\$1\$[A-Za-z0-9+/]+=*\$[A-Za-z0-9+/]+=*$ ]]; then
  echo "error: failed to generate the expected Hermes scrypt hash." >&2
  exit 1
fi

SESSION_SECRET=$(python3 -c 'import base64, secrets; print(base64.b64encode(secrets.token_bytes(48)).decode())')

# Use an explicit -w argument so the generated password is written exactly as
# produced. -U makes rotation update the existing Keychain item.
security add-generic-password \
  -U \
  -a "$USERNAME" \
  -s "$DOMAIN" \
  -D "Hermes dashboard password" \
  -j "Raw password for the built-in Hermes auth gate at https://$DOMAIN" \
  -w "$PASSWORD" \
  >/dev/null

put_secure_parameter() {
  local name="$1"
  local value="$2"

  aws ssm put-parameter \
    --name "$name" \
    --type SecureString \
    --value "$value" \
    --overwrite \
    --output text \
    >/dev/null
}

put_secure_parameter "$HERMES_HASH_PARAMETER" "$HERMES_HASH"
put_secure_parameter "$SESSION_SECRET_PARAMETER" "$SESSION_SECRET"

verify_secure_parameter() {
  local name="$1"
  local expected="$2"
  local actual

  actual=$(aws ssm get-parameter \
    --name "$name" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)
  if [[ "$actual" != "$expected" ]]; then
    unset actual
    echo "error: SSM read-after-write verification failed for $name; Hermes was not restarted." >&2
    exit 1
  fi
  unset actual
}

verify_secure_parameter "$HERMES_HASH_PARAMETER" "$HERMES_HASH"
verify_secure_parameter "$SESSION_SECRET_PARAMETER" "$SESSION_SECRET"

INSTANCE_ID="$(hermes_resolve_target_instance_id "${1:-}")"
if [[ ! "$INSTANCE_ID" =~ ^i-[a-fA-F0-9]+$ ]]; then
  echo "error: resolved instance ID is invalid." >&2
  exit 1
fi

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "Reload initialized Hermes dashboard authentication" \
  --parameters 'commands=["systemctl restart hermes.service","systemctl is-active --quiet hermes.service"]' \
  --query 'Command.CommandId' \
  --output text)

if ! aws ssm wait command-executed --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID"; then
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'Status' \
    --output text 2>/dev/null || true)
  echo "error: remote Hermes restart did not succeed (status=${STATUS:-unknown})." >&2
  exit 1
fi

echo "Public dashboard authentication initialized and Hermes restarted."
echo "The raw password is stored only in macOS Keychain: service=$DOMAIN, account=$USERNAME."
