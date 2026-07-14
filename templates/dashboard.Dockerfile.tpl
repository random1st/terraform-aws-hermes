# Derived only for the public dashboard until the upstream password-provider
# auto-SSO fix lands in a published Hermes tag. The gateway keeps using the
# unmodified official image.
ARG HERMES_BASE_IMAGE
FROM $${HERMES_BASE_IMAGE}

USER root
RUN python - <<'PY'
from pathlib import Path

path = Path("/opt/hermes/hermes_cli/dashboard_auth/middleware.py")
source = path.read_text(encoding="utf-8")
needle = """    provider = providers[0]
    prefix = prefix_from_request(request)
"""
replacement = """    provider = providers[0]
    if getattr(provider, "supports_password", False):
        return None
    prefix = prefix_from_request(request)
"""

if source.count(needle) != 1:
    raise SystemExit(
        "refusing to derive dashboard image: expected the v2026.7.7.2 "
        "_auto_sso_response patch point exactly once"
    )

patched = source.replace(needle, replacement, 1)
if patched.count('if getattr(provider, "supports_password", False):') != 1:
    raise SystemExit("refusing to derive dashboard image: guard verification failed")

path.write_text(patched, encoding="utf-8")
PY
