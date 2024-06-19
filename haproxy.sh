#!/bin/bash

echo -e "${Purple}"
____________________________________________________________________________________
        ____                             _     _                                     
    ,   /    )                           /|   /                                  /   
-------/____/---_--_----__---)__--_/_---/-| -/-----__--_/_-----------__---)__---/-__-
  /   /        / /  ) /   ) /   ) /    /  | /    /___) /   | /| /  /   ) /   ) /(    
_/___/________/_/__/_(___(_/_____(_ __/___|/____(___ _(_ __|/_|/__(___/_/_____/___\__
____________________________________________________________________________________                                                                                     
"
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
NC='\033[0m'              # NC
White='\033[0;96m'        # White

echo "
____________________________________________________________________________________

SERVER IP=$(hostname -I | awk '{print $1}')

SERVER COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')

SERVER ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

____________________________________________________________________________________                                                                                     
"
config_file="/etc/haproxy/haproxy.cfg"
backup_file="/etc/haproxy/haproxy.cfg.bak"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

install_haproxy() {
    echo "Installing HAProxy..."
    sudo apt-get update
    sudo apt-get install -y haproxy
    echo "HAProxy installed."
    default_config
}

default_config() {
    cat <<EOL > $config_file
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # Default ciphers to use on SSL-enabled listening sockets.
    # For more information, see ciphers(1SSL). This list is from:
    #  https://hynek.me/articles/hardening-your-web-servers-ssl-ciphers/
    ssl-default-bind-ciphers ECDH+AESGCM:ECDH+CHACHA20:ECDH+AES256:ECDH+AES128:ECDH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS
    ssl-default-bind-options no-sslv3

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http
EOL
}

generate_haproxy_config() {
    local ports=($1)
    local target_ips=($2)
    local config_file="/etc/haproxy/haproxy.cfg"

    echo "Generating HAProxy configuration..."

    for port in "${ports[@]}"; do
        cat <<EOL >> $config_file

frontend frontend_$port
    bind *:$port
    default_backend backend_$port

backend backend_$port
EOL
        for i in "${!target_ips[@]}"; do
            if [ $i -eq 0 ]; then
                cat <<EOL >> $config_file
    server server$(($i+1)) ${target_ips[$i]}:$port check
EOL
            else
                cat <<EOL >> $config_file
    server server$(($i+1)) ${target_ips[$i]}:$port check backup
EOL
            fi
        done
    done

    echo "HAProxy configuration generated at $config_file"
}

add_ip_ports() {
    read -p "Enter the IPs to forward to (use comma , to separate multiple IPs): " user_ips
    IFS=',' read -r -a ips_array <<< "$user_ips"
    read -p "Enter the ports (use comma , to separate): " user_ports
    IFS=',' read -r -a ports_array <<< "$user_ports"
    generate_haproxy_config "${ports_array[*]}" "${ips_array[*]}"

    if haproxy -c -f /etc/haproxy/haproxy.cfg; then
        echo "Restarting HAProxy service..."
        service haproxy restart
        echo "HAProxy configuration updated and service restarted."
    else
        echo "HAProxy configuration is invalid. Please check the configuration file."
    fi
}

clear_configs() {
    echo "Creating a backup of the HAProxy configuration..."
    cp $config_file $backup_file

    if [ $? -ne 0 ]; then
        echo "Failed to create a backup. Aborting."
        return
    fi

    echo "Clearing IP and port configurations from HAProxy configuration..."

    awk '
    /^frontend frontend_/ {skip = 1}
    /^backend backend_/ {skip = 1}
    skip {if (/^$/) {skip = 0}; next}
    {print}
    ' $backup_file > $config_file

    echo "Clearing IP and port configurations from $config_file."
    
    echo "Stopping HAProxy service..."
    sudo service haproxy stop
    
    if [ $? -eq 0 ]; then
        echo "HAProxy service stopped."
    else
        echo "Failed to stop HAProxy service."
    fi

    echo "Done!"
}

remove_haproxy() {
    echo "Removing HAProxy..."
    sudo apt-get remove --purge -y haproxy
    sudo apt-get autoremove -y
    echo "HAProxy removed."
}

check_root

while true; do
    sleep 1.5
    echo -e "${Purple}Select an option:${NC}"
    echo -e "1. Install HAProxy"
    echo -e "2. Add IPs and Ports to Forward"
    echo -e "3. Clear Configurations"
    echo -e "4. Remove HAProxy Completely"
    echo "9. Exit"
    echo -e -p "Select a Number : " choice

    case $choice in
        1)
            install_haproxy
            ;;
        2)
            add_ip_ports
            ;;
        3)
            clear_configs
            ;;
        4)
            remove_haproxy
            ;;
        9)
            echo "Exiting..."
            break
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done
