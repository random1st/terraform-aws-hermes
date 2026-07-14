################################################################################
# General
################################################################################

variable "name" {
  description = "Deployment name. Used in resource names, tags, and volume discovery."
  type        = string
  default     = "hermes"
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}

################################################################################
# Compute
################################################################################

variable "instance_type" {
  description = "EC2 instance type. Must be arm64-compatible."
  type        = string
  default     = "t4g.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 16

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "Root volume size must be at least 8 GiB."
  }
}

################################################################################
# Network
################################################################################

variable "subnet_id" {
  description = "Subnet ID override. If null, auto-discovers default VPC and deterministically selects a default subnet."
  type        = string
  default     = null
}

variable "public_dashboard_enabled" {
  description = "Expose the dashboard through a stable Elastic IP, Route53, Caddy automatic HTTPS, and the selected Hermes auth gate (Basic Auth by default, optional OIDC). Keeps the upstream no-ingress posture when false."
  type        = bool
  default     = false
}

variable "public_dashboard_auth_mode" {
  description = "Authentication mode for a public dashboard. basic uses the built-in Hermes password gate; oidc uses the bundled self-hosted OIDC provider with a public PKCE client."
  type        = string
  default     = "basic"

  validation {
    condition     = contains(["basic", "oidc"], lower(trimspace(var.public_dashboard_auth_mode)))
    error_message = "public_dashboard_auth_mode must be either \"basic\" or \"oidc\"."
  }

  validation {
    condition     = lower(trimspace(var.public_dashboard_auth_mode)) != "oidc" || var.public_dashboard_enabled
    error_message = "public_dashboard_auth_mode = \"oidc\" requires public_dashboard_enabled = true."
  }
}

variable "public_dashboard_domain" {
  description = "Public DNS name for the dashboard (for example, hm.example.com). Required when public_dashboard_enabled is true."
  type        = string
  default     = ""

  validation {
    condition = !var.public_dashboard_enabled || can(regex(
      "^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}\\.?$",
      trimspace(var.public_dashboard_domain),
    ))
    error_message = "public_dashboard_domain must be a valid fully-qualified DNS name when public_dashboard_enabled is true."
  }
}

variable "public_dashboard_route53_zone_id" {
  description = "Route53 public hosted zone ID that owns public_dashboard_domain. Required when public_dashboard_enabled is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.public_dashboard_enabled || can(regex("^Z[A-Z0-9]+$", trimspace(var.public_dashboard_route53_zone_id)))
    error_message = "public_dashboard_route53_zone_id must be a Route53 hosted zone ID when public_dashboard_enabled is true."
  }
}

variable "public_dashboard_basic_auth_username" {
  description = "Username for the built-in Hermes dashboard Basic Auth gate."
  type        = string
  default     = "hermes"

  validation {
    condition     = !var.public_dashboard_enabled || lower(trimspace(var.public_dashboard_auth_mode)) != "basic" || can(regex("^[A-Za-z0-9._@-]{1,64}$", var.public_dashboard_basic_auth_username))
    error_message = "public_dashboard_basic_auth_username must be 1-64 characters using only letters, digits, dot, underscore, at, or hyphen."
  }
}

variable "public_dashboard_oidc_issuer" {
  description = "OIDC issuer URL for the public dashboard. Required in oidc mode; must be HTTPS and must not contain a query or fragment."
  type        = string
  default     = ""

  validation {
    condition = lower(trimspace(var.public_dashboard_auth_mode)) != "oidc" || can(regex(
      "^https://[^/?#[:space:]]+(/[^?#[:space:]]*)?$",
      trimspace(var.public_dashboard_oidc_issuer),
    ))
    error_message = "public_dashboard_oidc_issuer must be a valid HTTPS issuer URL without a query or fragment when oidc mode is enabled."
  }
}

variable "public_dashboard_oidc_client_id" {
  description = "Public PKCE OIDC client ID registered for the dashboard. Required in oidc mode."
  type        = string
  default     = ""

  validation {
    condition = lower(trimspace(var.public_dashboard_auth_mode)) != "oidc" || (
      length(trimspace(var.public_dashboard_oidc_client_id)) >= 1 &&
      length(trimspace(var.public_dashboard_oidc_client_id)) <= 512 &&
      !can(regex("[[:space:]]", var.public_dashboard_oidc_client_id))
    )
    error_message = "public_dashboard_oidc_client_id must be 1-512 non-whitespace characters when oidc mode is enabled."
  }
}

variable "public_dashboard_oidc_scopes" {
  description = "OIDC scopes requested by the dashboard public PKCE client. Must include openid."
  type        = list(string)
  default     = ["openid", "profile", "email"]

  validation {
    condition = lower(trimspace(var.public_dashboard_auth_mode)) != "oidc" || (
      contains(var.public_dashboard_oidc_scopes, "openid") &&
      length(var.public_dashboard_oidc_scopes) <= 32 &&
      alltrue([
        for scope in var.public_dashboard_oidc_scopes :
        length(trimspace(scope)) >= 1 &&
        length(scope) <= 256 &&
        !can(regex("[[:space:]]", scope))
      ])
    )
    error_message = "public_dashboard_oidc_scopes must contain openid and only non-empty, whitespace-free scope values."
  }
}

################################################################################
# Storage
################################################################################

variable "data_volume_size" {
  description = "Persistent data EBS volume size in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.data_volume_size >= 10
    error_message = "Data volume size must be at least 10 GiB."
  }
}

variable "data_path" {
  description = "Mount path for the persistent data volume on the EC2 instance."
  type        = string
  default     = "/var/lib/hermes"
}

################################################################################
# Hermes
################################################################################

variable "hermes_version" {
  description = <<-EOT
    Exact Hermes Docker image tag for nousresearch/hermes-agent (must exist on Docker Hub).
    Upstream publishes dated tags such as v2026.4.30 — see:
    https://hub.docker.com/r/nousresearch/hermes-agent/tags
    Do not use the "latest" tag here.
  EOT
  type        = string

  validation {
    condition     = length(var.hermes_version) > 0 && var.hermes_version != "latest"
    error_message = "hermes_version must be a non-empty tag and cannot be \"latest\"."
  }
}

################################################################################
# Model Provider
################################################################################

variable "model_provider" {
  description = "Hermes model provider. Use bedrock for IAM-backed AWS inference or openai-codex for ChatGPT subscription OAuth stored in the persistent Hermes auth store."
  type        = string
  default     = "bedrock"

  validation {
    condition     = contains(["bedrock", "openai-codex"], var.model_provider)
    error_message = "model_provider must be either \"bedrock\" or \"openai-codex\"."
  }
}

variable "openai_codex_model_id" {
  description = "Default OpenAI Codex model ID when model_provider is openai-codex."
  type        = string
  default     = "gpt-5.5"

  validation {
    condition     = var.model_provider != "openai-codex" || length(trimspace(var.openai_codex_model_id)) > 0
    error_message = "openai_codex_model_id must be non-empty when model_provider is \"openai-codex\"."
  }
}

################################################################################
# Bedrock
################################################################################

variable "bedrock_region" {
  description = "AWS region for Bedrock API calls."
  type        = string
  default     = "us-east-1"
}

variable "bedrock_model_id" {
  description = <<-EOT
    Default Bedrock model ID for Hermes inference (written to config.yaml).
    Use a foundation model ID (e.g. nvidia.nemotron-super-3-120b) or a regional inference profile ID (e.g. us.anthropic.claude-haiku-4-5-20251001-v1:0).
    IDs matching /^[a-z]{2}\\./ are treated as inference profiles for IAM: inference-profile ARN and GetInferenceProfile on account profiles in bedrock_region, plus InvokeModel on arn:aws:bedrock:*::foundation-model/<id-with-xx.-removed> because cross-region profiles invoke the FM in routed regions (not only bedrock_region).
  EOT
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "bedrock_discovery_enabled" {
  description = "Enable Hermes Bedrock model discovery (auto-detect available models at runtime). Adds ListFoundationModels and ListInferenceProfiles IAM permissions."
  type        = bool
  default     = true
}

################################################################################
# Slack
################################################################################

variable "slack_enabled" {
  description = "Enable Slack Socket Mode (SSM parameters + gateway env). Set false for email-only deployments."
  type        = bool
  default     = true

  validation {
    condition     = var.slack_enabled || var.email_enabled || var.public_dashboard_enabled
    error_message = "At least one interaction surface must be enabled: Slack, email, or the public dashboard."
  }
}

variable "slack_home_channel" {
  description = "Slack channel ID for cron job delivery (SLACK_HOME_CHANNEL). Empty string disables home channel."
  type        = string
  default     = ""
}

variable "slack_allowed_users" {
  description = "Slack user IDs allowed to use Hermes (SLACK_ALLOWED_USERS). Empty list keeps module behavior \"open workspace\": sets GATEWAY_ALLOW_ALL_USERS=true so the Hermes gateway does not deny everyone by default."
  type        = list(string)
  default     = []
}

################################################################################
# Email (IMAP/SMTP)
################################################################################

variable "email_enabled" {
  description = "Enable Hermes email adapter (IMAP/SMTP). When true, requires non-empty email_address, email_imap_host, email_smtp_host, and email_home_address."
  type        = bool
  default     = false
}

variable "email_address" {
  description = "Dedicated mailbox address for the agent (EMAIL_ADDRESS)."
  type        = string
  default     = ""

  validation {
    condition     = !var.email_enabled || length(trimspace(var.email_address)) > 0
    error_message = "When email_enabled is true, email_address must be non-empty."
  }
}

variable "email_imap_host" {
  description = "IMAP server hostname (EMAIL_IMAP_HOST), e.g. imap.gmail.com."
  type        = string
  default     = ""

  validation {
    condition     = !var.email_enabled || length(trimspace(var.email_imap_host)) > 0
    error_message = "When email_enabled is true, email_imap_host must be non-empty."
  }
}

variable "email_smtp_host" {
  description = "SMTP server hostname (EMAIL_SMTP_HOST), e.g. smtp.gmail.com."
  type        = string
  default     = ""

  validation {
    condition     = !var.email_enabled || length(trimspace(var.email_smtp_host)) > 0
    error_message = "When email_enabled is true, email_smtp_host must be non-empty."
  }
}

variable "email_imap_port" {
  description = "IMAP port (EMAIL_IMAP_PORT). Default 993 (SSL)."
  type        = number
  default     = 993

  validation {
    condition     = var.email_imap_port >= 1 && var.email_imap_port <= 65535
    error_message = "email_imap_port must be between 1 and 65535."
  }
}

variable "email_smtp_port" {
  description = "SMTP port (EMAIL_SMTP_PORT). Default 587 (STARTTLS)."
  type        = number
  default     = 587

  validation {
    condition     = var.email_smtp_port >= 1 && var.email_smtp_port <= 65535
    error_message = "email_smtp_port must be between 1 and 65535."
  }
}

variable "email_poll_interval" {
  description = "Seconds between inbox polls (EMAIL_POLL_INTERVAL)."
  type        = number
  default     = 15

  validation {
    condition     = !var.email_enabled || var.email_poll_interval >= 1
    error_message = "When email_enabled is true, email_poll_interval must be at least 1."
  }
}

variable "email_allowed_users" {
  description = "Sender addresses allowed to interact with the agent (EMAIL_ALLOWED_USERS). Empty list leaves Hermes default behavior (pairing); does not set EMAIL_ALLOW_ALL_USERS."
  type        = list(string)
  default     = []
}

variable "email_home_address" {
  description = "Default delivery address for cron-style jobs (EMAIL_HOME_ADDRESS). Required when email_enabled is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.email_enabled || length(trimspace(var.email_home_address)) > 0
    error_message = "When email_enabled is true, email_home_address must be non-empty."
  }
}

variable "email_allow_all_users" {
  description = <<-EOT
    When true, sets EMAIL_ALLOW_ALL_USERS=true so any sender can use the agent.
    WARNING: This opens a serious abuse vector — anyone who learns the mailbox address can interact with an agent that often has powerful tools enabled.
    Prefer email_allowed_users. Only enable with deliberate risk acceptance.
  EOT
  type        = bool
  default     = false
}

variable "email_skip_attachments" {
  description = "When email_enabled, sets platforms.email.skip_attachments in config.yaml (skip inbound attachments before decoding)."
  type        = bool
  default     = false
}

################################################################################
# API Server
################################################################################

variable "api_server_enabled" {
  description = "Enable the OpenAI-compatible API server on port 8642. When enabled, an API_SERVER_KEY is auto-generated and stored in SSM."
  type        = bool
  default     = false
}

################################################################################
# SSM / Secrets
################################################################################

variable "ssm_parameter_prefix" {
  description = "SSM Parameter Store path prefix for all Hermes secrets."
  type        = string
  default     = "/hermes"

  validation {
    condition     = length(var.ssm_parameter_prefix) >= 2 && startswith(var.ssm_parameter_prefix, "/")
    error_message = "ssm_parameter_prefix must be a non-empty hierarchical path starting with / (e.g. /hermes)."
  }
}

################################################################################
# Logging
################################################################################

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention value."
  }
}

################################################################################
# Schedule
################################################################################

variable "instance_refresh_cron" {
  description = "EventBridge Scheduler cron expression for weekly ASG instance refresh (default: Sunday 01:00 UTC)."
  type        = string
  default     = "0 1 ? * SUN *"
}
