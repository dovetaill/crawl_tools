#!/bin/bash

# =======================================================================================
# Script Name: install_aio_proxy.sh
# Description: One-click installer for a comprehensive proxy and scraping suite.
#              This script deploys:
#              - FlareSolverr (for solving Cloudflare challenges)
#              - Crawl4AI (for web crawling)
#              - Cloudflare WARP (to route all egress traffic)
#              - Nginx (as a reverse proxy with password protection for each service)
# Author:      Gemini
# Version:     3.0
#
# Usage:
#   Interactive Mode (Recommended for first-time use):
#     ./install_aio_proxy.sh
#
#   Silent Mode (for automated setups):
#     ./install_aio_proxy.sh \
#       <flaresolverr_user> <flaresolverr_pass> <flaresolverr_port> \
#       <crawl4ai_user> <crawl4ai_pass> <crawl4ai_port>
#
# Example:
#   ./install_aio_proxy.sh fs_user FsPass123 8191 c4ai_user C4aiPass456 11235
# =======================================================================================

# --- Script safety settings: exit on error ---
set -e

# --- Configuration ---
INSTALL_DIR="/opt/aio_proxy"
DEFAULT_FLARESOLVERR_PORT="8191"
DEFAULT_CRAWL4AI_PORT="11235"

# --- Helper Functions for Colored Output ---
print_info() {    echo -e "\e[34m[INFO]\e[0m $1"; }
print_success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
print_error() {   echo -e "\e[31m[ERROR]\e[0m $1" >&2; }
print_warn() {    echo -e "\e[33m[WARN]\e[0m $1"; }

# --- Prerequisite Check ---
check_deps() {
    print_info "Checking for dependencies (docker, docker compose)..."
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker and try again."
        exit 1
    fi
    # Prefer `docker compose` (v2) over `docker-compose` (v1)
    if command -v docker compose &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        print_warn "Using 'docker-compose' (v1). It is recommended to upgrade to Docker Compose v2 ('docker compose')."
    else
        print_error "Docker Compose is not installed. Please install it and try again."
        exit 1
    fi
    print_success "All dependencies are satisfied."
}

# --- Main Logic ---
main() {
    check_deps

    # --- Handle Arguments for Silent or Interactive Mode ---
    if [ "$#" -eq 6 ]; then
        # Silent Mode
        FLARESOLVERR_USER="$1"
        FLARESOLVERR_PASS="$2"
        FLARESOLVERR_PORT="$3"
        CRAWL4AI_USER="$4"
        CRAWL4AI_PASS="$5"
        CRAWL4AI_PORT="$6"
        print_info "Running in silent mode."
    elif [ "$#" -eq 0 ]; then
        # Interactive Mode
        print_info "Running in interactive mode. Please provide the following details."

        read -p "Enter username for FlareSolverr: " FLARESOLVERR_USER
        read -s -p "Enter password for FlareSolverr: " FLARESOLVERR_PASS; echo
        read -p "Enter external port for FlareSolverr [default: $DEFAULT_FLARESOLVERR_PORT]: " FLARESOLVERR_PORT
        [ -z "$FLARESOLVERR_PORT" ] && FLARESOLVERR_PORT="$DEFAULT_FLARESOLVERR_PORT"

        echo "---"
        read -p "Enter username for Crawl4AI: " CRAWL4AI_USER
        read -s -p "Enter password for Crawl4AI: " CRAWL4AI_PASS; echo
        read -p "Enter external port for Crawl4AI [default: $DEFAULT_CRAWL4AI_PORT]: " CRAWL4AI_PORT
        [ -z "$CRAWL4AI_PORT" ] && CRAWL4AI_PORT="$DEFAULT_CRAWL4AI_PORT"
    else
        print_error "Invalid number of arguments."
        echo "Usage (Interactive): $0"
        echo "Usage (Silent):      $0 <fs_user> <fs_pass> <fs_port> <c4ai_user> <c4ai_pass> <c4ai_port>"
        exit 1
    fi

    # --- Validate Inputs ---
    if [ -z "$FLARESOLVERR_USER" ] || [ -z "$FLARESOLVERR_PASS" ] || [ -z "$CRAWL4AI_USER" ] || [ -z "$CRAWL4AI_PASS" ]; then
        print_error "Usernames and passwords cannot be empty."
        exit 1
    fi
    if ! [[ $FLARESOLVERR_PORT =~ ^[0-9]+$ ]] || [ "$FLARESOLVERR_PORT" -le 0 ] || [ "$FLARESOLVERR_PORT" -gt 65535 ] || \
       ! [[ $CRAWL4AI_PORT =~ ^[0-9]+$ ]] || [ "$CRAWL4AI_PORT" -le 0 ] || [ "$CRAWL4AI_PORT" -gt 65535 ]; then
        print_error "Invalid port number. Must be between 1 and 65535."
        exit 1
    fi
    if [ "$FLARESOLVERR_PORT" == "$CRAWL4AI_PORT" ]; then
        print_error "FlareSolverr and Crawl4AI ports cannot be the same."
        exit 1
    fi

    # --- Create Directories and Files ---
    print_info "Creating installation directory at $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR/nginx"
    mkdir -p "$INSTALL_DIR/warp-data"

    print_info "Generating .env file with your credentials..."
    # Use printf for safer handling of special characters in passwords
    {
        printf "FLARESOLVERR_USER=%s\n" "$FLARESOLVERR_USER"
        printf "FLARESOLVERR_PASS=%s\n" "$FLARESOLVERR_PASS"
        printf "CRAWL4AI_USER=%s\n" "$CRAWL4AI_USER"
        printf "CRAWL4AI_PASS=%s\n" "$CRAWL4AI_PASS"
        printf "FLARESOLVERR_PORT=%s\n" "$FLARESOLVERR_PORT"
        printf "CRAWL4AI_PORT=%s\n" "$CRAWL4AI_PORT"
    } > "$INSTALL_DIR/.env"

    print_info "Generating docker-compose.yml..."
    cat << EOF > "$INSTALL_DIR/docker-compose.yml"
version: '3.8'

services:
  # The WARP service provides the network exit point for other services.
  warp:
    image: caomingjun/warp
    container_name: aio-warp
    restart: always
    privileged: true # Using privileged simplifies capabilities and sysctls
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv4.conf.all.src_valid_mark=1
    ports:
      # Map host ports to the ports Nginx will listen on internally
      - "\${FLARESOLVERR_PORT}:80"
      - "\${CRAWL4AI_PORT}:81"
    volumes:
      - ./warp-data:/var/lib/cloudflare-warp
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - WARP_SLEEP=10 # Check connection every 10 seconds

  # Nginx acts as the reverse proxy and handles authentication.
  # It shares the network stack of the 'warp' service.
  nginx:
    image: nginx:stable-alpine
    container_name: aio-proxy
    restart: always
    network_mode: "service:warp" # CRITICAL: This makes Nginx use WARP's network stack
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - htpasswd_volume:/etc/nginx/:ro
    depends_on:
      - warp
      - htpasswd-generator

  # FlareSolverr solves Cloudflare challenges.
  # Its traffic is routed through WARP because it shares the same network stack.
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: aio-flaresolverr
    restart: always
    network_mode: "service:warp" # CRITICAL: Route all traffic through WARP
    environment:
      - LOG_LEVEL=info
      - TZ=Asia/Shanghai
    depends_on:
      - warp

  # Crawl4AI is the web scraping service.
  # Its traffic is also routed through WARP.
  crawl4ai:
    image: unclecode/crawl4ai:latest
    container_name: aio-crawl4ai
    restart: always
    network_mode: "service:warp" # CRITICAL: Route all traffic through WARP
    shm_size: '3g' # Required by crawl4ai
    depends_on:
      - warp

  # This init-container runs once to create the password files and then exits.
  htpasswd-generator:
    image: httpd:2.4-alpine
    container_name: aio-htpasswd-gen
    volumes:
      - htpasswd_volume:/etc/nginx/
    command: >
      sh -c "htpasswd -bc /etc/nginx/.flaresolverr_passwd \${FLARESOLVERR_USER} \${FLARESOLVERR_PASS} &&
             htpasswd -bc /etc/nginx/.crawl4ai_passwd \${CRAWL4AI_USER} \${CRAWL4AI_PASS}"
    env_file:
      - .env

volumes:
  htpasswd_volume:

EOF

    print_info "Generating nginx.conf..."
    cat << EOF > "$INSTALL_DIR/nginx/nginx.conf"
# Server block for FlareSolverr
server {
    listen 80;
    server_name _;

    location / {
        auth_basic "FlareSolverr Protected Access";
        auth_basic_user_file /etc/nginx/.flaresolverr_passwd;

        # Because FlareSolverr shares the network stack, we access it via localhost
        proxy_pass http://localhost:8191;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Server block for Crawl4AI
server {
    listen 81;
    server_name _;

    location / {
        auth_basic "Crawl4AI Protected Access";
        auth_basic_user_file /etc/nginx/.crawl4ai_passwd;

        # Crawl4AI also shares the network stack
        proxy_pass http://localhost:11235;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # --- Deploy with Docker Compose ---
    print_info "Navigating to $INSTALL_DIR and starting services..."
    cd "$INSTALL_DIR"

    print_info "Pulling the latest images..."
    $COMPOSE_CMD pull

    print_info "Starting containers... (htpasswd will be generated first)"
    $COMPOSE_CMD up -d

    print_success "Deployment complete!"
    echo "------------------------------------------------------------------"
    echo "Your All-in-One Proxy & Scraping suite is now running."
    echo ""
    echo -e "  \e[1mFlareSolverr Access:\e[0m"
    echo -e "    \e[1mURL:\e[0m      http://<your_server_ip>:${FLARESOLVERR_PORT}"
    echo -e "    \e[1mUsername:\e[0m ${FLARESOLVERR_USER}"
    echo ""
    echo -e "  \e[1mCrawl4AI Access:\e[0m"
    echo -e "    \e[1mURL:\e[0m      http://<your_server_ip>:${CRAWL4AI_PORT}"
    echo -e "    \e[1mUsername:\e[0m ${CRAWL4AI_USER}"
    echo ""
    echo "  \e[1mService Management:\e[0m"
    echo "    - Navigate to the directory: cd ${INSTALL_DIR}"
    echo "    - Check status: ${COMPOSE_CMD} ps"
    echo "    - View logs:    ${COMPOSE_CMD} logs -f"
    echo "    - Stop services:  ${COMPOSE_CMD} down"
    echo ""
    echo "  \e[1mWARP IP Management:\e[0m"
    echo -e "    - \e[1mTo manually refresh WARP IP (get a new one):\e[0m"
    echo "      cd ${INSTALL_DIR} && ${COMPOSE_CMD} restart warp"
    echo "    - \e[1mTo schedule automatic refresh (e.g., every 6 hours):\e[0m"
    echo "      Add this to your crontab ('crontab -e'):"
    echo "      0 */6 * * * cd ${INSTALL_DIR} && ${COMPOSE_CMD} restart warp >/dev/null 2>&1"
    echo "------------------------------------------------------------------"
}

# --- Execute main function with all script arguments ---
main "$@"
