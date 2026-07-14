locals {
  region    = data.aws_region.current.region
  az        = data.aws_subnet.selected.availability_zone
  vpc_id    = data.aws_subnet.selected.vpc_id
  subnet_id = data.aws_subnet.selected.id

  common_tags = merge(var.tags, {
    Name             = var.name
    Project          = "hermes"
    HermesDeployment = var.name
  })

  public_dashboard_domain    = trimsuffix(lower(trimspace(var.public_dashboard_domain)), ".")
  public_dashboard_auth_mode = lower(trimspace(var.public_dashboard_auth_mode))

  # Official Caddy v2.11.4 multi-platform image, pinned to the Docker Hub manifest digest.
  caddy_image = "caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648"

  # Terraform never receives real dashboard credentials. These fixed values
  # keep the public endpoint fail-closed until the post-apply bootstrap runs.
  dashboard_hermes_hash_sentinel    = "UNCONFIGURED_HERMES_SCRYPT_HASH"
  dashboard_session_secret_sentinel = "UNCONFIGURED_HERMES_SESSION_SECRET"

  # All egress is aws_vpc_security_group_egress_rule with stable for_each keys (see security_group.tf).
  sg_email_egress_rules = var.email_enabled ? {
    imap = {
      ip_protocol = "tcp"
      from_port   = var.email_imap_port
      to_port     = var.email_imap_port
      description = "IMAP (Hermes email)"
    }
    smtp = {
      ip_protocol = "tcp"
      from_port   = var.email_smtp_port
      to_port     = var.email_smtp_port
      description = "SMTP (Hermes email)"
    }
  } : {}

  sg_egress_rules = merge(
    {
      https = {
        ip_protocol = "tcp"
        from_port   = 443
        to_port     = 443
        description = "HTTPS outbound"
      }
      dns_udp = {
        ip_protocol = "udp"
        from_port   = 53
        to_port     = 53
        description = "DNS UDP outbound"
      }
      dns_tcp = {
        ip_protocol = "tcp"
        from_port   = 53
        to_port     = 53
        description = "DNS TCP outbound"
      }
    },
    local.sg_email_egress_rules,
  )

  sg_ingress_rules = var.public_dashboard_enabled ? {
    http = {
      from_port   = 80
      to_port     = 80
      description = "HTTP for Caddy ACME and HTTPS redirect"
    }
    https = {
      from_port   = 443
      to_port     = 443
      description = "HTTPS public dashboard"
    }
  } : {}

  # SSM parameter paths
  ssm_slack_bot_token_path          = "${var.ssm_parameter_prefix}/slack/bot_token"
  ssm_slack_app_token_path          = "${var.ssm_parameter_prefix}/slack/app_token"
  ssm_email_password_path           = "${var.ssm_parameter_prefix}/email/password"
  ssm_soul_md_path                  = "${var.ssm_parameter_prefix}/soul_md"
  ssm_api_server_key_path           = "${var.ssm_parameter_prefix}/api_server_key"
  ssm_dashboard_username_path       = "${var.ssm_parameter_prefix}/dashboard/basic_auth/username"
  ssm_dashboard_hermes_hash_path    = "${var.ssm_parameter_prefix}/dashboard/basic_auth/hermes_scrypt_hash"
  ssm_dashboard_session_secret_path = "${var.ssm_parameter_prefix}/dashboard/basic_auth/session_secret"

  ssm_parameter_arns = concat(
    var.slack_enabled ? [
      aws_ssm_parameter.slack_bot_token[0].arn,
      aws_ssm_parameter.slack_app_token[0].arn,
    ] : [],
    [
      aws_ssm_parameter.soul_md.arn,
    ],
    var.api_server_enabled ? [aws_ssm_parameter.api_server_key[0].arn] : [],
    var.email_enabled ? [aws_ssm_parameter.email_password[0].arn] : [],
    var.public_dashboard_enabled && local.public_dashboard_auth_mode == "basic" ? [
      aws_ssm_parameter.dashboard_username[0].arn,
      aws_ssm_parameter.dashboard_hermes_hash[0].arn,
      aws_ssm_parameter.dashboard_session_secret[0].arn,
    ] : [],
  )

  # CloudWatch
  log_group_name = "/hermes/${var.name}"

  # Bedrock model ARN for IAM: foundation models use the account-less ARN; regional inference
  # profile IDs (e.g. us.anthropic.*) require ...:inference-profile/<id> in the caller's account.
  bedrock_model_arn = (
    can(regex("^[a-z]{2}\\.", var.bedrock_model_id))
    ? "arn:aws:bedrock:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_model_id}"
    : "arn:aws:bedrock:${var.bedrock_region}::foundation-model/${var.bedrock_model_id}"
  )

  # Regional inference profile IDs map to a foundation model ID without the xx. prefix (see AWS inference profile IAM docs).
  # Inference profile IDs matching /^[a-z]{2}\\./ always use exactly three leading characters (e.g. us.) before the base ID.
  bedrock_foundation_model_id_for_profile = (
    can(regex("^[a-z]{2}\\.", var.bedrock_model_id))
    ? substr(var.bedrock_model_id, 3, length(var.bedrock_model_id) - 3)
    : ""
  )

  # InvokeModel on inference profiles requires permission on both the profile ARN and the underlying foundation model ARN.
  # System inference profiles (e.g. us.anthropic.*) route compute across multiple regions; FM invoke may hit us-east-2 etc.,
  # so the FM ARN uses a wildcard region. Single-region on-demand models keep bedrock_region only via bedrock_model_arn above.
  bedrock_invoke_resource_arns = distinct(concat(
    [local.bedrock_model_arn],
    local.bedrock_foundation_model_id_for_profile != ""
    ? ["arn:aws:bedrock:*::foundation-model/${local.bedrock_foundation_model_id_for_profile}"]
    : [],
  ))

  # Read inference profile metadata (required for invocation via profiles); scoped to this account and Bedrock region.
  bedrock_inference_profile_read_arns = [
    "arn:aws:bedrock:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
    "arn:aws:bedrock:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:application-inference-profile/*",
  ]

  # Container image reference
  hermes_image           = "nousresearch/hermes-agent:${var.hermes_version}"
  hermes_dashboard_image = "hermes-dashboard:${var.hermes_version}-password-auto-sso-fix"

  # Slack allowed users joined for env var
  slack_allowed_users_csv = join(",", var.slack_allowed_users)

  # Hermes gateway denies all users unless allowlists are set; match module doc when list is empty.
  slack_gateway_allow_all_users = length(var.slack_allowed_users) == 0

  # Host-side path for Docker Compose configuration
  compose_dir = "/opt/hermes"

  # Rendered sub-templates
  hermes_config = templatefile("${path.module}/templates/hermes_config.yaml.tpl", {
    model_provider            = var.model_provider
    model_id                  = var.model_provider == "bedrock" ? var.bedrock_model_id : var.openai_codex_model_id
    bedrock_region            = var.bedrock_region
    bedrock_discovery_enabled = var.bedrock_discovery_enabled
    email_enabled             = var.email_enabled
    email_skip_attachments    = var.email_skip_attachments
  })

  hermes_compose = templatefile("${path.module}/templates/docker-compose.yml.tpl", {
    image                           = local.hermes_image
    dashboard_image                 = local.hermes_dashboard_image
    dashboard_build_context         = "${local.compose_dir}/dashboard-image"
    data_path                       = var.data_path
    log_group_name                  = local.log_group_name
    region                          = local.region
    api_server_enabled              = var.api_server_enabled
    slack_enabled                   = var.slack_enabled
    email_enabled                   = var.email_enabled
    email_address                   = var.email_address
    email_imap_host                 = var.email_imap_host
    email_smtp_host                 = var.email_smtp_host
    email_imap_port                 = var.email_imap_port
    email_smtp_port                 = var.email_smtp_port
    email_poll_interval             = var.email_poll_interval
    email_allowed_users_csv         = join(",", var.email_allowed_users)
    email_allowed_users_set         = length(var.email_allowed_users) > 0
    email_home_address              = var.email_home_address
    email_allow_all_users           = var.email_allow_all_users
    public_dashboard_enabled        = var.public_dashboard_enabled
    public_dashboard_domain         = local.public_dashboard_domain
    public_dashboard_auth_mode      = local.public_dashboard_auth_mode
    public_dashboard_oidc_issuer    = trimspace(var.public_dashboard_oidc_issuer)
    public_dashboard_oidc_client_id = trimspace(var.public_dashboard_oidc_client_id)
    public_dashboard_oidc_scopes    = var.public_dashboard_oidc_scopes
    caddy_image                     = local.caddy_image
    compose_dir                     = local.compose_dir
  })

  hermes_start_script = templatefile("${path.module}/templates/hermes-start.sh.tpl", {
    region                            = local.region
    slack_enabled                     = var.slack_enabled
    email_enabled                     = var.email_enabled
    ssm_slack_bot_token_path          = local.ssm_slack_bot_token_path
    ssm_slack_app_token_path          = local.ssm_slack_app_token_path
    ssm_email_password_path           = local.ssm_email_password_path
    ssm_soul_md_path                  = local.ssm_soul_md_path
    ssm_api_server_key_path           = local.ssm_api_server_key_path
    data_path                         = var.data_path
    compose_dir                       = local.compose_dir
    slack_home_channel                = var.slack_home_channel
    slack_allowed_users               = local.slack_allowed_users_csv
    slack_gateway_allow_all_users     = local.slack_gateway_allow_all_users
    api_server_enabled                = var.api_server_enabled
    public_dashboard_enabled          = var.public_dashboard_enabled
    public_dashboard_auth_mode        = local.public_dashboard_auth_mode
    ssm_dashboard_username_path       = local.ssm_dashboard_username_path
    ssm_dashboard_hermes_hash_path    = local.ssm_dashboard_hermes_hash_path
    ssm_dashboard_session_secret_path = local.ssm_dashboard_session_secret_path
    dashboard_hermes_hash_sentinel    = local.dashboard_hermes_hash_sentinel
    dashboard_session_secret_sentinel = local.dashboard_session_secret_sentinel
  })

  hermes_service = templatefile("${path.module}/templates/hermes.service.tpl", {
    compose_dir = local.compose_dir
    data_path   = var.data_path
  })

  hermes_caddyfile = var.public_dashboard_enabled ? templatefile("${path.module}/templates/Caddyfile.tpl", {
    public_dashboard_domain = local.public_dashboard_domain
  }) : ""

  hermes_dashboard_dockerfile = var.public_dashboard_enabled && local.public_dashboard_auth_mode == "basic" ? templatefile("${path.module}/templates/dashboard.Dockerfile.tpl", {}) : ""

  hermes_diagnose_script = templatefile("${path.module}/templates/hermes-diagnose.sh.tpl", {
    region                   = local.region
    data_path                = var.data_path
    compose_dir              = local.compose_dir
    slack_enabled            = var.slack_enabled
    email_enabled            = var.email_enabled
    ssm_slack_bot_token_path = local.ssm_slack_bot_token_path
    ssm_slack_app_token_path = local.ssm_slack_app_token_path
    ssm_email_password_path  = local.ssm_email_password_path
    ssm_soul_md_path         = local.ssm_soul_md_path
    ssm_api_server_key_path  = local.ssm_api_server_key_path
    api_server_enabled       = var.api_server_enabled
  })
}
