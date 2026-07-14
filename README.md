[![FivexL](https://releases.fivexl.io/like-this-repo-banner.png)](https://fivexl.io/#email-subscription)

### Want practical AWS infrastructure insights?

👉 [Subscribe to our newsletter](https://fivexl.io/#email-subscription) to get:

- Real stories from real AWS projects  
- No-nonsense DevOps tactics  
- Cost, security & compliance patterns that actually work  
- Expert guidance from engineers in the field

=========================================================================

# terraform-aws-hermes

Terraform module to deploy [Hermes](https://github.com/nousresearch/hermes-agent) on AWS EC2 using immutable infrastructure principles.

Hermes is an open-source, self-improving AI agent by NousResearch that supports 30+ LLM providers and multiple messaging platforms. This module deploys it as a single-node Docker Compose service backed by Amazon Bedrock for inference and **optional messaging channels that do not require exposing HTTP endpoints or public URLs**—typically **Slack Socket Mode** (WebSocket out) and/or **email** (IMAP/SMTP out). Enable each channel with Terraform flags (`slack_enabled`, `email_enabled`).

## Architecture

- **Single EC2 instance** (arm64, Amazon Linux 2023) managed by an Auto Scaling Group for automatic recovery
- **Docker Compose** runs the Hermes gateway and dashboard as containers with `network_mode: host`; public mode also runs Caddy for TLS
- **Persistent EBS volume** preserves Hermes state across instance replacements
- **No SSH** -- administrative access through AWS Systems Manager Session Manager only
- **Dashboard** defaults to `127.0.0.1:9119` via SSM port forwarding; optional public mode opens only 80/443, terminates TLS in Caddy, and uses either built-in Hermes Basic Auth (default) or OIDC SSO
- **Basic Auth compatibility fix** derives only the Basic-auth dashboard image from the exact official Hermes tag with the unmerged upstream password-provider auto-SSO guard; OIDC mode and the gateway use the unmodified official image
- **Weekly instance refresh** rebuilds the instance on a schedule for immutable infrastructure hygiene
- **CloudWatch Logs** via Docker `awslogs` log driver

## Prerequisites

- AWS account with a default VPC (or provide a `subnet_id`)
- **At least one messaging channel** (`slack_enabled` and/or `email_enabled`; defaults keep Slack on and email off)
- If **`slack_enabled`** (default): Slack App with Socket Mode enabled ([runbook](docs/runbook.md#3-slack-app-when-slack_enabled--true))
- If **`email_enabled`**: dedicated mailbox, IMAP/SMTP reachability, app password stored in SSM ([runbook](docs/runbook.md#4-email-mailbox-when-email_enabled--true), [Hermes email docs](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/email))
- After `terraform apply`, set real values on SSM parameters the module creates (placeholders until you overwrite):
  - Slack (`slack_enabled`): `<prefix>/slack/bot_token`, `<prefix>/slack/app_token`
  - Email (`email_enabled`): `<prefix>/email/password`
  - Always: `<prefix>/soul_md`
  - Optional API: `<prefix>/api_server_key` when `api_server_enabled`
  See [Operator Runbook](docs/runbook.md) for exact steps.
- Bedrock model access enabled in your account for the configured model
- If **`public_dashboard_enabled`**: a Route53 public hosted zone for the domain, plus one auth mode:
  - `basic` (default): after apply, run `scripts/bootstrap-public-dashboard-auth.sh`; it stores the raw generated password in macOS Keychain and only the Hermes scrypt hash/session secret in SSM.
  - `oidc`: register a **public PKCE client** in the IdP with redirect URI `https://<public_dashboard_domain>/auth/callback`, then set the issuer and client ID variables. Restrict access by assigning that IdP application to the intended group/users; this module does not add a separate local user allowlist.

## Usage

```hcl
module "hermes" {
  source  = "fivexl/hermes/aws"

  # Required: pin an existing tag from Docker Hub.
  hermes_version = "v2026.7.7.2"

  # All other variables have sensible defaults.
  # See variables.tf for the full list.
}
```

See [`terraform.tfvars.example`](terraform.tfvars.example) for every non-secret module setting, including the optional OIDC mode. Credentials do not belong in tfvars.

### Access the Dashboard

With the default private dashboard, use SSM port forwarding:

```bash
# Find the instance ID
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$(terraform output -raw asg_name)" \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" \
  --output text)

# Port forward
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9119"],"localPortNumber":["9119"]}'

# Open http://localhost:9119 in your browser
```

With `public_dashboard_enabled = true`, finish the selected auth setup and then open `public_dashboard_url`. In `basic` mode, run the credential bootstrap after apply. In `oidc` mode, the IdP client must use `https://<public_dashboard_domain>/auth/callback` and application/group assignment controls who may sign in. Caddy provides automatic HTTPS and reverse proxying only; login is enforced by Hermes itself.

## Documentation

- [Architecture & Design](docs/design.md) -- why the system is shaped this way (includes Terraform conventions: prefer `for_each` over `count` where applicable)
- [Operator Runbook](docs/runbook.md) -- day-to-day operations, troubleshooting, secret setup

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_cloudinit"></a> [cloudinit](#requirement\_cloudinit) | >= 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |
| <a name="provider_cloudinit"></a> [cloudinit](#provider\_cloudinit) | 2.4.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_instance_role"></a> [instance\_role](#module\_instance\_role) | terraform-aws-modules/iam/aws//modules/iam-role | ~> 6.0 |
| <a name="module_scheduler_role"></a> [scheduler\_role](#module\_scheduler\_role) | terraform-aws-modules/iam/aws//modules/iam-role | ~> 6.0 |
| <a name="module_sg"></a> [sg](#module\_sg) | terraform-aws-modules/security-group/aws | ~> 5.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_autoscaling_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ebs_volume.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume) | resource |
| [aws_eip.public_dashboard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_policy.bedrock](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ebs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.public_dashboard_eip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.scheduler_asg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ssm_parameters](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_launch_template.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_route53_record.public_dashboard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_scheduler_schedule.weekly_refresh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_ssm_parameter.api_server_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.dashboard_hermes_hash](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.dashboard_session_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.dashboard_username](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.email_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.slack_app_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.slack_bot_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.soul_md](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_vpc_security_group_egress_rule.egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.public_dashboard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_password.api_server_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.bedrock](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ebs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.public_dashboard_eip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.scheduler_asg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.scheduler_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ssm_parameters](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_ssm_parameter.al2023_ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnets.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |
| [cloudinit_config.this](https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_server_enabled"></a> [api\_server\_enabled](#input\_api\_server\_enabled) | Enable the OpenAI-compatible API server on port 8642. When enabled, an API\_SERVER\_KEY is auto-generated and stored in SSM. | `bool` | `false` | no |
| <a name="input_bedrock_discovery_enabled"></a> [bedrock\_discovery\_enabled](#input\_bedrock\_discovery\_enabled) | Enable Hermes Bedrock model discovery (auto-detect available models at runtime). Adds ListFoundationModels and ListInferenceProfiles IAM permissions. | `bool` | `true` | no |
| <a name="input_bedrock_model_id"></a> [bedrock\_model\_id](#input\_bedrock\_model\_id) | Default Bedrock model ID for Hermes inference (written to config.yaml).<br/>Use a foundation model ID (e.g. nvidia.nemotron-super-3-120b) or a regional inference profile ID (e.g. us.anthropic.claude-haiku-4-5-20251001-v1:0).<br/>IDs matching /^[a-z]{2}\\./ are treated as inference profiles for IAM: inference-profile ARN and GetInferenceProfile on account profiles in bedrock\_region, plus InvokeModel on arn:aws:bedrock:*::foundation-model/<id-with-xx.-removed> because cross-region profiles invoke the FM in routed regions (not only bedrock\_region). | `string` | `"us.anthropic.claude-haiku-4-5-20251001-v1:0"` | no |
| <a name="input_bedrock_region"></a> [bedrock\_region](#input\_bedrock\_region) | AWS region for Bedrock API calls. | `string` | `"us-east-1"` | no |
| <a name="input_data_path"></a> [data\_path](#input\_data\_path) | Mount path for the persistent data volume on the EC2 instance. | `string` | `"/var/lib/hermes"` | no |
| <a name="input_data_volume_size"></a> [data\_volume\_size](#input\_data\_volume\_size) | Persistent data EBS volume size in GiB. | `number` | `20` | no |
| <a name="input_email_address"></a> [email\_address](#input\_email\_address) | Dedicated mailbox address for the agent (EMAIL\_ADDRESS). | `string` | `""` | no |
| <a name="input_email_allow_all_users"></a> [email\_allow\_all\_users](#input\_email\_allow\_all\_users) | When true, sets EMAIL\_ALLOW\_ALL\_USERS=true so any sender can use the agent.<br/>WARNING: This opens a serious abuse vector — anyone who learns the mailbox address can interact with an agent that often has powerful tools enabled.<br/>Prefer email\_allowed\_users. Only enable with deliberate risk acceptance. | `bool` | `false` | no |
| <a name="input_email_allowed_users"></a> [email\_allowed\_users](#input\_email\_allowed\_users) | Sender addresses allowed to interact with the agent (EMAIL\_ALLOWED\_USERS). Empty list leaves Hermes default behavior (pairing); does not set EMAIL\_ALLOW\_ALL\_USERS. | `list(string)` | `[]` | no |
| <a name="input_email_enabled"></a> [email\_enabled](#input\_email\_enabled) | Enable Hermes email adapter (IMAP/SMTP). When true, requires non-empty email\_address, email\_imap\_host, email\_smtp\_host, and email\_home\_address. | `bool` | `false` | no |
| <a name="input_email_home_address"></a> [email\_home\_address](#input\_email\_home\_address) | Default delivery address for cron-style jobs (EMAIL\_HOME\_ADDRESS). Required when email\_enabled is true. | `string` | `""` | no |
| <a name="input_email_imap_host"></a> [email\_imap\_host](#input\_email\_imap\_host) | IMAP server hostname (EMAIL\_IMAP\_HOST), e.g. imap.gmail.com. | `string` | `""` | no |
| <a name="input_email_imap_port"></a> [email\_imap\_port](#input\_email\_imap\_port) | IMAP port (EMAIL\_IMAP\_PORT). Default 993 (SSL). | `number` | `993` | no |
| <a name="input_email_poll_interval"></a> [email\_poll\_interval](#input\_email\_poll\_interval) | Seconds between inbox polls (EMAIL\_POLL\_INTERVAL). | `number` | `15` | no |
| <a name="input_email_skip_attachments"></a> [email\_skip\_attachments](#input\_email\_skip\_attachments) | When email\_enabled, sets platforms.email.skip\_attachments in config.yaml (skip inbound attachments before decoding). | `bool` | `false` | no |
| <a name="input_email_smtp_host"></a> [email\_smtp\_host](#input\_email\_smtp\_host) | SMTP server hostname (EMAIL\_SMTP\_HOST), e.g. smtp.gmail.com. | `string` | `""` | no |
| <a name="input_email_smtp_port"></a> [email\_smtp\_port](#input\_email\_smtp\_port) | SMTP port (EMAIL\_SMTP\_PORT). Default 587 (STARTTLS). | `number` | `587` | no |
| <a name="input_hermes_version"></a> [hermes\_version](#input\_hermes\_version) | Exact Hermes Docker image tag for nousresearch/hermes-agent (must exist on Docker Hub).<br/>Upstream publishes dated tags such as v2026.4.30 — see:<br/>https://hub.docker.com/r/nousresearch/hermes-agent/tags<br/>Do not use the "latest" tag here. | `string` | n/a | yes |
| <a name="input_instance_refresh_cron"></a> [instance\_refresh\_cron](#input\_instance\_refresh\_cron) | EventBridge Scheduler cron expression for weekly ASG instance refresh (default: Sunday 01:00 UTC). | `string` | `"0 1 ? * SUN *"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type. Must be arm64-compatible. | `string` | `"t4g.medium"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch Logs retention in days. | `number` | `30` | no |
| <a name="input_model_provider"></a> [model\_provider](#input\_model\_provider) | Hermes model provider. Use bedrock for IAM-backed AWS inference or openai-codex for ChatGPT subscription OAuth stored in the persistent Hermes auth store. | `string` | `"bedrock"` | no |
| <a name="input_name"></a> [name](#input\_name) | Deployment name. Used in resource names, tags, and volume discovery. | `string` | `"hermes"` | no |
| <a name="input_openai_codex_model_id"></a> [openai\_codex\_model\_id](#input\_openai\_codex\_model\_id) | Default OpenAI Codex model ID when model\_provider is openai-codex. | `string` | `"gpt-5.5"` | no |
| <a name="input_public_dashboard_auth_mode"></a> [public\_dashboard\_auth\_mode](#input\_public\_dashboard\_auth\_mode) | Authentication mode for a public dashboard. basic uses the built-in Hermes password gate; oidc uses the bundled self-hosted OIDC provider with a public PKCE client. | `string` | `"basic"` | no |
| <a name="input_public_dashboard_basic_auth_username"></a> [public\_dashboard\_basic\_auth\_username](#input\_public\_dashboard\_basic\_auth\_username) | Username for the built-in Hermes dashboard Basic Auth gate. | `string` | `"hermes"` | no |
| <a name="input_public_dashboard_domain"></a> [public\_dashboard\_domain](#input\_public\_dashboard\_domain) | Public DNS name for the dashboard (for example, hm.example.com). Required when public\_dashboard\_enabled is true. | `string` | `""` | no |
| <a name="input_public_dashboard_enabled"></a> [public\_dashboard\_enabled](#input\_public\_dashboard\_enabled) | Expose the dashboard through a stable Elastic IP, Route53, Caddy automatic HTTPS, and the selected Hermes auth gate (Basic Auth by default, optional OIDC). Keeps the upstream no-ingress posture when false. | `bool` | `false` | no |
| <a name="input_public_dashboard_oidc_client_id"></a> [public\_dashboard\_oidc\_client\_id](#input\_public\_dashboard\_oidc\_client\_id) | Public PKCE OIDC client ID registered for the dashboard. Required in oidc mode. | `string` | `""` | no |
| <a name="input_public_dashboard_oidc_issuer"></a> [public\_dashboard\_oidc\_issuer](#input\_public\_dashboard\_oidc\_issuer) | OIDC issuer URL for the public dashboard. Required in oidc mode; must be HTTPS and must not contain a query or fragment. | `string` | `""` | no |
| <a name="input_public_dashboard_oidc_scopes"></a> [public\_dashboard\_oidc\_scopes](#input\_public\_dashboard\_oidc\_scopes) | OIDC scopes requested by the dashboard public PKCE client. Must include openid. | `list(string)` | <pre>[<br/>  "openid",<br/>  "profile",<br/>  "email"<br/>]</pre> | no |
| <a name="input_public_dashboard_route53_zone_id"></a> [public\_dashboard\_route53\_zone\_id](#input\_public\_dashboard\_route53\_zone\_id) | Route53 public hosted zone ID that owns public\_dashboard\_domain. Required when public\_dashboard\_enabled is true. | `string` | `""` | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root EBS volume size in GiB. | `number` | `16` | no |
| <a name="input_slack_allowed_users"></a> [slack\_allowed\_users](#input\_slack\_allowed\_users) | Slack user IDs allowed to use Hermes (SLACK\_ALLOWED\_USERS). Empty list keeps module behavior "open workspace": sets GATEWAY\_ALLOW\_ALL\_USERS=true so the Hermes gateway does not deny everyone by default. | `list(string)` | `[]` | no |
| <a name="input_slack_enabled"></a> [slack\_enabled](#input\_slack\_enabled) | Enable Slack Socket Mode (SSM parameters + gateway env). Set false for email-only deployments. | `bool` | `true` | no |
| <a name="input_slack_home_channel"></a> [slack\_home\_channel](#input\_slack\_home\_channel) | Slack channel ID for cron job delivery (SLACK\_HOME\_CHANNEL). Empty string disables home channel. | `string` | `""` | no |
| <a name="input_ssm_parameter_prefix"></a> [ssm\_parameter\_prefix](#input\_ssm\_parameter\_prefix) | SSM Parameter Store path prefix for all Hermes secrets. | `string` | `"/hermes"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Subnet ID override. If null, auto-discovers default VPC and deterministically selects a default subnet. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_server_key_ssm_parameter_arn"></a> [api\_server\_key\_ssm\_parameter\_arn](#output\_api\_server\_key\_ssm\_parameter\_arn) | SSM parameter ARN for the API server bearer token. Null when api\_server\_enabled is false. |
| <a name="output_api_server_key_ssm_parameter_name"></a> [api\_server\_key\_ssm\_parameter\_name](#output\_api\_server\_key\_ssm\_parameter\_name) | SSM parameter name for the API server bearer token. Null when api\_server\_enabled is false. |
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | Name of the Auto Scaling Group. |
| <a name="output_availability_zone"></a> [availability\_zone](#output\_availability\_zone) | Availability zone of the deployment. |
| <a name="output_data_volume_id"></a> [data\_volume\_id](#output\_data\_volume\_id) | ID of the persistent EBS data volume. |
| <a name="output_deployment_name"></a> [deployment\_name](#output\_deployment\_name) | Hermes deployment name used in resource names and discovery tags. |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the EC2 instance IAM role. |
| <a name="output_iam_role_name"></a> [iam\_role\_name](#output\_iam\_role\_name) | Name of the EC2 instance IAM role. |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the launch template. |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | CloudWatch Logs group ARN. |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | CloudWatch Logs group name. |
| <a name="output_public_dashboard_auth_mode"></a> [public\_dashboard\_auth\_mode](#output\_public\_dashboard\_auth\_mode) | Selected public dashboard authentication mode. Null when public\_dashboard\_enabled is false. |
| <a name="output_public_dashboard_basic_auth_username"></a> [public\_dashboard\_basic\_auth\_username](#output\_public\_dashboard\_basic\_auth\_username) | Username for the built-in Hermes dashboard Basic Auth gate. Null when the public dashboard is disabled or uses OIDC. |
| <a name="output_public_dashboard_domain"></a> [public\_dashboard\_domain](#output\_public\_dashboard\_domain) | Normalized public dashboard domain. Null when public\_dashboard\_enabled is false. |
| <a name="output_public_dashboard_hermes_hash_ssm_parameter_name"></a> [public\_dashboard\_hermes\_hash\_ssm\_parameter\_name](#output\_public\_dashboard\_hermes\_hash\_ssm\_parameter\_name) | SSM parameter name for the Hermes scrypt hash. Null when the public dashboard is disabled or uses OIDC. |
| <a name="output_public_dashboard_ipv4_address"></a> [public\_dashboard\_ipv4\_address](#output\_public\_dashboard\_ipv4\_address) | Stable public dashboard Elastic IP address. Null when public\_dashboard\_enabled is false. |
| <a name="output_public_dashboard_session_secret_ssm_parameter_name"></a> [public\_dashboard\_session\_secret\_ssm\_parameter\_name](#output\_public\_dashboard\_session\_secret\_ssm\_parameter\_name) | SSM parameter name for the Hermes dashboard session secret. Null when the public dashboard is disabled or uses OIDC. |
| <a name="output_public_dashboard_url"></a> [public\_dashboard\_url](#output\_public\_dashboard\_url) | HTTPS URL for the public dashboard. Null when public\_dashboard\_enabled is false. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the instance security group. |
| <a name="output_slack_app_token_ssm_parameter_arn"></a> [slack\_app\_token\_ssm\_parameter\_arn](#output\_slack\_app\_token\_ssm\_parameter\_arn) | SSM parameter ARN for the Slack app token when slack\_enabled is true. Null when Slack is disabled. |
| <a name="output_slack_app_token_ssm_parameter_name"></a> [slack\_app\_token\_ssm\_parameter\_name](#output\_slack\_app\_token\_ssm\_parameter\_name) | SSM parameter name for the Slack app token when slack\_enabled is true. Null when Slack is disabled. |
| <a name="output_slack_bot_token_ssm_parameter_arn"></a> [slack\_bot\_token\_ssm\_parameter\_arn](#output\_slack\_bot\_token\_ssm\_parameter\_arn) | SSM parameter ARN for the Slack bot token when slack\_enabled is true. Null when Slack is disabled. |
| <a name="output_slack_bot_token_ssm_parameter_name"></a> [slack\_bot\_token\_ssm\_parameter\_name](#output\_slack\_bot\_token\_ssm\_parameter\_name) | SSM parameter name for the Slack bot token when slack\_enabled is true. Null when Slack is disabled. |
| <a name="output_soul_md_ssm_parameter_arn"></a> [soul\_md\_ssm\_parameter\_arn](#output\_soul\_md\_ssm\_parameter\_arn) | SSM parameter ARN for the agent personality (SOUL.md). |
| <a name="output_soul_md_ssm_parameter_name"></a> [soul\_md\_ssm\_parameter\_name](#output\_soul\_md\_ssm\_parameter\_name) | SSM parameter name for the agent personality (SOUL.md). Value is set outside Terraform. |
| <a name="output_ssm_port_forward_command"></a> [ssm\_port\_forward\_command](#output\_ssm\_port\_forward\_command) | Ready-to-use SSM port forwarding command for dashboard access. |
| <a name="output_subnet_id"></a> [subnet\_id](#output\_subnet\_id) | Subnet ID where the instance is deployed. |
<!-- END_TF_DOCS -->
