#!/usr/bin/env bash
# Hermes startup wrapper.
# Fetches secrets from SSM, exports them as env vars, fetches SOUL.md,
# then exec's docker compose. Secrets stay in process memory only.

set -euo pipefail

REGION="${region}"
DATA_PATH="${data_path}"
COMPOSE_DIR="${compose_dir}"

ssm_get() {
  local name="$1"
  aws ssm get-parameter \
    --name "$name" \
    --with-decryption \
    --region "$REGION" \
    --query 'Parameter.Value' \
    --output text
}

IMAGE=$(tr -d '\n\r' <"$COMPOSE_DIR/.image")

%{ if public_dashboard_enabled && public_dashboard_auth_mode == "basic" ~}
# Public mode is fail-closed: placeholders or malformed credentials stop the
# service before Hermes binds the public dashboard port.
PUBLIC_DASHBOARD_USERNAME=$(ssm_get "${ssm_dashboard_username_path}")
PUBLIC_DASHBOARD_HERMES_PASSWORD_HASH=$(ssm_get "${ssm_dashboard_hermes_hash_path}")
PUBLIC_DASHBOARD_SESSION_SECRET=$(ssm_get "${ssm_dashboard_session_secret_path}")

dashboard_auth_fatal() {
  echo "FATAL: public dashboard authentication is not initialized: $1" >&2
  echo "Run scripts/bootstrap-public-dashboard-auth.sh from the Terraform root, then restart hermes.service." >&2
  exit 1
}

[[ -n "$PUBLIC_DASHBOARD_USERNAME" ]] || dashboard_auth_fatal "username is empty"
[[ "$PUBLIC_DASHBOARD_HERMES_PASSWORD_HASH" != "${dashboard_hermes_hash_sentinel}" ]] || dashboard_auth_fatal "Hermes hash is still the Terraform sentinel"
[[ "$PUBLIC_DASHBOARD_SESSION_SECRET" != "${dashboard_session_secret_sentinel}" ]] || dashboard_auth_fatal "session secret is still the Terraform sentinel"

[[ "$PUBLIC_DASHBOARD_HERMES_PASSWORD_HASH" =~ ^scrypt\$16384\$8\$1\$[A-Za-z0-9+/]+=*\$[A-Za-z0-9+/]+=*$ ]] || dashboard_auth_fatal "Hermes hash is not the expected scrypt format"
[[ "$PUBLIC_DASHBOARD_SESSION_SECRET" =~ ^[A-Za-z0-9+/=]{24,}$ ]] || dashboard_auth_fatal "session secret is malformed"

export PUBLIC_DASHBOARD_USERNAME
export PUBLIC_DASHBOARD_HERMES_PASSWORD_HASH
export PUBLIC_DASHBOARD_SESSION_SECRET
%{ endif ~}

# Container UID/GID for volume ownership and Compose interpolation.
# Bypass image ENTRYPOINT (it logs bundled-skills sync) so we only get numeric ids.
HERMES_UID=$(docker run --rm --entrypoint /bin/sh "$IMAGE" -c 'id -u hermes' | tr -d '\r\n')
HERMES_GID=$(docker run --rm --entrypoint /bin/sh "$IMAGE" -c 'id -g hermes' | tr -d '\r\n')
if [[ ! "$HERMES_UID" =~ ^[0-9]+$ || ! "$HERMES_GID" =~ ^[0-9]+$ ]]; then
  echo "warn: id hermes failed (uid='$HERMES_UID' gid='$HERMES_GID'); trying image Config.User" >&2
  ugs=$(docker image inspect "$IMAGE" --format '{{.Config.User}}' 2>/dev/null | tr -d '\r\n')
  if [[ "$ugs" =~ ^[0-9]+:[0-9]+$ ]]; then
    HERMES_UID=$${ugs%%:*}
    HERMES_GID=$${ugs##*:}
  elif [[ "$ugs" =~ ^[0-9]+$ ]]; then
    HERMES_UID=$ugs
    HERMES_GID=$ugs
  else
    echo "warn: Config.User='$ugs' not usable; falling back to 10000:10000" >&2
    HERMES_UID=10000
    HERMES_GID=10000
  fi
fi
if [[ ! "$HERMES_UID" =~ ^[0-9]+$ || ! "$HERMES_GID" =~ ^[0-9]+$ ]]; then
  HERMES_UID=10000
  HERMES_GID=10000
fi
export HERMES_UID HERMES_GID

# Ensure persistent volume is owned by the container user.
chown -R "$HERMES_UID:$HERMES_GID" "$DATA_PATH"

%{ if public_dashboard_enabled ~}
# The recursive Hermes ownership pass above also touches Caddy state. Restore
# the dedicated Caddy UID before Compose starts so ACME storage stays writable.
mkdir -p "$DATA_PATH/caddy/data" "$DATA_PATH/caddy/config"
chown -R 1000:1000 "$DATA_PATH/caddy"
chmod 750 "$DATA_PATH/caddy" "$DATA_PATH/caddy/data" "$DATA_PATH/caddy/config"
%{ endif ~}

# Render SOUL.md from SSM into the data volume on every start.
SOUL_MD=$(ssm_get "${ssm_soul_md_path}")
printf '%s' "$SOUL_MD" > "$DATA_PATH/SOUL.md"
chown "$HERMES_UID:$HERMES_GID" "$DATA_PATH/SOUL.md"
unset SOUL_MD

%{ if slack_enabled ~}
# Fetch Slack secrets and export for docker compose interpolation.
SLACK_BOT_TOKEN=$(ssm_get "${ssm_slack_bot_token_path}")
SLACK_APP_TOKEN=$(ssm_get "${ssm_slack_app_token_path}")
export SLACK_BOT_TOKEN SLACK_APP_TOKEN

export SLACK_HOME_CHANNEL="${slack_home_channel}"
export SLACK_ALLOWED_USERS="${slack_allowed_users}"

%{ if slack_gateway_allow_all_users ~}
export GATEWAY_ALLOW_ALL_USERS=true
%{ else ~}
export GATEWAY_ALLOW_ALL_USERS=false
%{ endif ~}
%{ endif ~}

%{ if email_enabled ~}
EMAIL_PASSWORD=$(ssm_get "${ssm_email_password_path}")
export EMAIL_PASSWORD
%{ endif ~}

%{ if api_server_enabled ~}
API_SERVER_KEY=$(ssm_get "${ssm_api_server_key_path}")
export API_SERVER_KEY
%{ endif ~}

exec docker compose -f "$COMPOSE_DIR/docker-compose.yml" up
