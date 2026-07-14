model:
  default: ${model_id}
  provider: ${model_provider}
%{ if model_provider == "bedrock" ~}
bedrock:
  region: ${bedrock_region}
  discovery:
    enabled: ${bedrock_discovery_enabled}
%{ endif ~}
%{ if email_enabled ~}
platforms:
  email:
    skip_attachments: ${email_skip_attachments}
%{ endif ~}
