services:
  hermes-gateway:
    image: ${image}
    container_name: hermes-gateway
    network_mode: host
    restart: unless-stopped
    user: "$${HERMES_UID}:$${HERMES_GID}"
    volumes:
      - ${data_path}:/opt/data
    environment:
      HERMES_HOME: /opt/data
      AWS_REGION: ${region}
%{ if slack_enabled ~}
      SLACK_BOT_TOKEN: $${SLACK_BOT_TOKEN}
      SLACK_APP_TOKEN: $${SLACK_APP_TOKEN}
      SLACK_HOME_CHANNEL: $${SLACK_HOME_CHANNEL}
      SLACK_ALLOWED_USERS: $${SLACK_ALLOWED_USERS}
      # Set by hermes-start.sh from Terraform slack_allowed_users (open vs restricted).
      GATEWAY_ALLOW_ALL_USERS: $${GATEWAY_ALLOW_ALL_USERS:-false}
%{ endif ~}
%{ if email_enabled ~}
      EMAIL_ADDRESS: "${email_address}"
      EMAIL_IMAP_HOST: "${email_imap_host}"
      EMAIL_SMTP_HOST: "${email_smtp_host}"
      EMAIL_IMAP_PORT: "${email_imap_port}"
      EMAIL_SMTP_PORT: "${email_smtp_port}"
      EMAIL_POLL_INTERVAL: "${email_poll_interval}"
      EMAIL_PASSWORD: $${EMAIL_PASSWORD}
%{ if email_allowed_users_set ~}
      EMAIL_ALLOWED_USERS: "${email_allowed_users_csv}"
%{ endif ~}
      EMAIL_HOME_ADDRESS: "${email_home_address}"
%{ if email_allow_all_users ~}
      EMAIL_ALLOW_ALL_USERS: "true"
%{ endif ~}
%{ endif ~}
%{ if api_server_enabled ~}
      API_SERVER_ENABLED: "true"
      API_SERVER_KEY: $${API_SERVER_KEY}
%{ endif ~}
    command: ["gateway", "run"]
    # Match upstream: browser tools need > default shm (see Hermes Docker docs).
    shm_size: "1gb"
    logging:
      driver: awslogs
      options:
        awslogs-region: ${region}
        awslogs-group: ${log_group_name}
        awslogs-stream: hermes-gateway

  hermes-dashboard:
    image: %{ if public_dashboard_enabled && public_dashboard_auth_mode == "basic" }${dashboard_image}%{ else }${image}%{ endif }
%{ if public_dashboard_enabled && public_dashboard_auth_mode == "basic" ~}
    build:
      context: ${dashboard_build_context}
      dockerfile: Dockerfile
      args:
        HERMES_BASE_IMAGE: ${image}
%{ endif ~}
    container_name: hermes-dashboard
    network_mode: host
    restart: unless-stopped
    user: "$${HERMES_UID}:$${HERMES_GID}"
    volumes:
      - ${data_path}:/opt/data
    environment:
      HERMES_HOME: /opt/data
      AWS_REGION: ${region}
%{ if public_dashboard_enabled ~}
%{ if public_dashboard_auth_mode == "basic" ~}
      HERMES_DASHBOARD_BASIC_AUTH_USERNAME: "$${PUBLIC_DASHBOARD_USERNAME}"
      HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH: "$${PUBLIC_DASHBOARD_HERMES_PASSWORD_HASH}"
      HERMES_DASHBOARD_BASIC_AUTH_SECRET: "$${PUBLIC_DASHBOARD_SESSION_SECRET}"
%{ else ~}
      HERMES_DASHBOARD_OIDC_ISSUER: ${jsonencode(public_dashboard_oidc_issuer)}
      HERMES_DASHBOARD_OIDC_CLIENT_ID: ${jsonencode(public_dashboard_oidc_client_id)}
      HERMES_DASHBOARD_OIDC_SCOPES: ${jsonencode(join(" ", public_dashboard_oidc_scopes))}
%{ endif ~}
      HERMES_DASHBOARD_PUBLIC_URL: "https://${public_dashboard_domain}"
%{ endif ~}
    command: ["dashboard", "--host", "%{ if public_dashboard_enabled }0.0.0.0%{ else }127.0.0.1%{ endif }", "--no-open"]
    logging:
      driver: awslogs
      options:
        awslogs-region: ${region}
        awslogs-group: ${log_group_name}
        awslogs-stream: hermes-dashboard

%{ if public_dashboard_enabled ~}
  caddy:
    image: ${caddy_image}
    container_name: hermes-caddy
    network_mode: host
    restart: unless-stopped
    user: "1000:1000"
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    depends_on:
      - hermes-dashboard
    volumes:
      - ${compose_dir}/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${data_path}/caddy/data:/data
      - ${data_path}/caddy/config:/config
    logging:
      driver: awslogs
      options:
        awslogs-region: ${region}
        awslogs-group: ${log_group_name}
        awslogs-stream: hermes-caddy
%{ endif ~}
