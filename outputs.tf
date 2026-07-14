output "asg_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.name
}

output "iam_role_arn" {
  description = "ARN of the EC2 instance IAM role."
  value       = module.instance_role.arn
}

output "iam_role_name" {
  description = "Name of the EC2 instance IAM role."
  value       = module.instance_role.name
}

output "security_group_id" {
  description = "ID of the instance security group."
  value       = module.sg.security_group_id
}

output "log_group_name" {
  description = "CloudWatch Logs group name."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "CloudWatch Logs group ARN."
  value       = aws_cloudwatch_log_group.this.arn
}

output "data_volume_id" {
  description = "ID of the persistent EBS data volume."
  value       = aws_ebs_volume.data.id
}

output "slack_bot_token_ssm_parameter_name" {
  description = "SSM parameter name for the Slack bot token when slack_enabled is true. Null when Slack is disabled."
  value       = var.slack_enabled ? aws_ssm_parameter.slack_bot_token[0].name : null
}

output "slack_bot_token_ssm_parameter_arn" {
  description = "SSM parameter ARN for the Slack bot token when slack_enabled is true. Null when Slack is disabled."
  value       = var.slack_enabled ? aws_ssm_parameter.slack_bot_token[0].arn : null
}

output "slack_app_token_ssm_parameter_name" {
  description = "SSM parameter name for the Slack app token when slack_enabled is true. Null when Slack is disabled."
  value       = var.slack_enabled ? aws_ssm_parameter.slack_app_token[0].name : null
}

output "slack_app_token_ssm_parameter_arn" {
  description = "SSM parameter ARN for the Slack app token when slack_enabled is true. Null when Slack is disabled."
  value       = var.slack_enabled ? aws_ssm_parameter.slack_app_token[0].arn : null
}

output "soul_md_ssm_parameter_name" {
  description = "SSM parameter name for the agent personality (SOUL.md). Value is set outside Terraform."
  value       = aws_ssm_parameter.soul_md.name
}

output "soul_md_ssm_parameter_arn" {
  description = "SSM parameter ARN for the agent personality (SOUL.md)."
  value       = aws_ssm_parameter.soul_md.arn
}

output "api_server_key_ssm_parameter_name" {
  description = "SSM parameter name for the API server bearer token. Null when api_server_enabled is false."
  value       = var.api_server_enabled ? aws_ssm_parameter.api_server_key[0].name : null
}

output "api_server_key_ssm_parameter_arn" {
  description = "SSM parameter ARN for the API server bearer token. Null when api_server_enabled is false."
  value       = var.api_server_enabled ? aws_ssm_parameter.api_server_key[0].arn : null
}

output "ssm_port_forward_command" {
  description = "Ready-to-use SSM port forwarding command for dashboard access."
  value       = "aws ssm start-session --target <INSTANCE_ID> --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"9119\"],\"localPortNumber\":[\"9119\"]}'"
}

output "subnet_id" {
  description = "Subnet ID where the instance is deployed."
  value       = local.subnet_id
}

output "availability_zone" {
  description = "Availability zone of the deployment."
  value       = local.az
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = aws_launch_template.this.id
}

output "deployment_name" {
  description = "Hermes deployment name used in resource names and discovery tags."
  value       = var.name
}

output "public_dashboard_url" {
  description = "HTTPS URL for the public dashboard. Null when public_dashboard_enabled is false."
  value       = var.public_dashboard_enabled ? "https://${local.public_dashboard_domain}" : null
}

output "public_dashboard_auth_mode" {
  description = "Selected public dashboard authentication mode. Null when public_dashboard_enabled is false."
  value       = var.public_dashboard_enabled ? local.public_dashboard_auth_mode : null
}

output "public_dashboard_domain" {
  description = "Normalized public dashboard domain. Null when public_dashboard_enabled is false."
  value       = var.public_dashboard_enabled ? local.public_dashboard_domain : null
}

output "public_dashboard_ipv4_address" {
  description = "Stable public dashboard Elastic IP address. Null when public_dashboard_enabled is false."
  value       = var.public_dashboard_enabled ? aws_eip.public_dashboard[0].public_ip : null
}

output "public_dashboard_basic_auth_username" {
  description = "Username for the built-in Hermes dashboard Basic Auth gate. Null when the public dashboard is disabled or uses OIDC."
  value       = var.public_dashboard_enabled && local.public_dashboard_auth_mode == "basic" ? var.public_dashboard_basic_auth_username : null
}

output "public_dashboard_hermes_hash_ssm_parameter_name" {
  description = "SSM parameter name for the Hermes scrypt hash. Null when the public dashboard is disabled or uses OIDC."
  value       = var.public_dashboard_enabled && local.public_dashboard_auth_mode == "basic" ? aws_ssm_parameter.dashboard_hermes_hash[0].name : null
}

output "public_dashboard_session_secret_ssm_parameter_name" {
  description = "SSM parameter name for the Hermes dashboard session secret. Null when the public dashboard is disabled or uses OIDC."
  value       = var.public_dashboard_enabled && local.public_dashboard_auth_mode == "basic" ? aws_ssm_parameter.dashboard_session_secret[0].name : null
}
