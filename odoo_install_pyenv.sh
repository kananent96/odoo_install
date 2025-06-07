#!/bin/bash
################################################################################
# Start Check Script Fail line
export PS4='+ ${BASH_SOURCE}:${LINENO}: '
set -euo pipefail
set -x
# End Check Script Fail line
################################################################################

################################################################################
# Script for installing Odoo on Ubuntu 24.04
# Author: Prashant Prajapati
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo_install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo_install.sh
# Execute the script to install Odoo:
# ./odoo_install
################################################################################
# Common variables
ODOO_USER="odoo18"
ODOO_HOME="/opt/$ODOO_USER"
ODOO_REPO="https://www.github.com/odoo/odoo"
ODOO_BRANCH="18.0"
ODOO_CONFIG="/etc/$ODOO_USER.conf"
ODOO_SERVICE="/etc/systemd/system/$ODOO_USER.service"
ODOO_DB_USER="$ODOO_USER"
ODOO_DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16)  # Secure random password
OE_PORT="8069"
# Set the default Odoo longpolling port
LONGPOLL_PORT="8072"
# Set the website name
WEBSITE_NAME="_"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate
ADMIN_EMAIL="odoo@example.com"
# Set to 'true' to install and configure Nginx
INSTALL_NGINX="true"
# Set Strong admin password
ADMIN_PASSWORD="admin"
# Set to "True" to generate a random password, "False" to use the variable in ADMIN_PASSWORD
GENERATE_RANDOM_PASSWORD="True"
# Set odoo db name as per requirements
ODOO_DB_NAME="odoo18"
#--------------------------------------------------
# Update and Upgrade System
#--------------------------------------------------
echo "=== Updating and Upgrading System ==="
sudo apt-get update && sudo apt-get upgrade -y

echo "=== Secure the Server ==="
sudo apt-get install -y openssh-server fail2ban
sudo systemctl start fail2ban
sudo systemctl enable fail2ban
sudo systemctl status fail2ban --no-pager

echo "=== Install Packages and Libraries ==="
sudo apt-get install -y python3-pip
sudo apt install python3-venv
sudo apt-get install -y python3-dev libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev build-essential libssl-dev libffi-dev libmysqlclient-dev libjpeg-dev libpq-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev

#--------------------------------------------------
# Install Node
#--------------------------------------------------
echo "=== Install Node/ npm ==="
sudo apt-get install -y npm
# Create node symlink
sudo ln -s /usr/bin/nodejs /usr/bin/node || true

# Install less and clean-css
sudo npm install -g less less-plugin-clean-css

#--------------------------------------------------
# Install PostgreSQL
#--------------------------------------------------
echo "=== Set Up the Database Server ==="
sudo apt-get install -y postgresql postgresql-contrib

# Create PostgreSQL user with secure random password
echo "=== Create PostgreSQL User ==="
# Create PostgreSQL user with secure random password
echo "=== Create PostgreSQL User ==="
PGUSER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_DB_USER'")
if [ "$PGUSER_EXISTS" != "1" ]; then
    sudo -u postgres psql -c "CREATE USER $ODOO_DB_USER WITH SUPERUSER CREATEDB PASSWORD '$ODOO_DB_PASS';"
    echo "✅ PostgreSQL user '$ODOO_DB_USER' created."
else
    echo "ℹ️ PostgreSQL user '$ODOO_DB_USER' already exists. Skipping creation."
fi
# sudo -u postgres psql -c "CREATE USER $ODOO_DB_USER WITH SUPERUSER CREATEDB PASSWORD '$ODOO_DB_PASS';"

# Check if PostgreSQL service is running
if ! sudo systemctl is-active --quiet postgresql; then
    echo "PostgreSQL service is not running. Starting and enabling it..."
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
fi

#--------------------------------------------------
# Install Pyenv and Python 3.12.0
#--------------------------------------------------
echo "=== Install Python 3.12.0 with Pyenv ==="
# Install pyenv dependencies
sudo apt-get install -y make build-essential libssl-dev zlib1g-dev \
libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev

# Install pyenv as Odoo user
curl https://pyenv.run | bash
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc
source ~/.bashrc
pyenv install 3.12.0
pyenv global 3.12.0

# Verify installation
source ~/.bashrc && python --version

#--------------------------------------------------
# Create Odoo User
#--------------------------------------------------
echo "=== Create a System User for Odoo ==="
if [ -d "$ODOO_HOME" ]; then
    echo "⚠️  $ODOO_HOME already exists. Removing..."
    sudo rm -rf /opt/odoo18
fi
sudo adduser --system --home=$ODOO_HOME --group --shell /bin/bash $ODOO_USER

#--------------------------------------------------
# Clone Odoo Repository
#--------------------------------------------------
echo "=== Clone Odoo Repository ==="
sudo mkdir -p "$ODOO_HOME"
sudo chown -R "$ODOO_USER":"$ODOO_USER" "$ODOO_HOME"
sudo -u "$ODOO_USER" -H git clone "$ODOO_REPO" --depth 1 --branch "$ODOO_BRANCH" --single-branch "$ODOO_HOME"


#--------------------------------------------------
# Setup Python Virtual Environment and Install Requirements
#--------------------------------------------------
echo "=== Setup Python Virtual Environment and Install Dependencies ==="
echo "=== Create Virtual Environment with Python 3.12.0 ==="
# sudo -u $ODOO_USER -H bash -c "
#     cd $ODOO_HOME
#     python3 -m venv venv
#     source venv/bin/activate
#     pip install wheel
#     pip install -r requirements.txt
#     deactivate
# "
#--------------------------------------------------
# Setup Python Virtual Environment with Python 3.12.0
#--------------------------------------------------
sudo -u $ODOO_USER -H bash -c "
    source ~/.bashrc
    cd $ODOO_HOME
    python -m venv venv
    source venv/bin/activate
    pip install wheel
    pip install -r requirements.txt
    deactivate
"

#--------------------------------------------------
# Create Custom Modules Directory
#--------------------------------------------------
echo -e "\n---- Create custom module directory ----"
sudo -u $ODOO_USER mkdir -p $ODOO_HOME/custom
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

#--------------------------------------------------
# Configure Odoo
#--------------------------------------------------
echo "=== Configure Odoo ==="
sudo bash -c "cat > $ODOO_CONFIG" <<EOF
[options]
db_host = localhost
db_port = 5432
db_user = $ODOO_DB_USER
db_password = $ODOO_DB_PASS
db_name = $ODOO_DB_NAME
addons_path = $ODOO_HOME/addons,$ODOO_HOME/custom
without_demo = all
logfile = /var/log/odoo/$ODOO_USER.log
longpolling_port = $LONGPOLL_PORT
http_port = $OE_PORT
xmlrpc_port = $OE_PORT
list_db = False
EOF

if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
    echo -e "* Generating random admin password"
    ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16)
fi
sudo bash -c "echo 'admin_passwd = $ADMIN_PASSWORD' >> $ODOO_CONFIG"

sudo chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG
sudo chmod 640 $ODOO_CONFIG

# Create log directory
sudo mkdir -p /var/log/odoo
sudo chown $ODOO_USER:root /var/log/odoo

#--------------------------------------------------
# Setup Odoo as a Systemd Service
#--------------------------------------------------
echo "=== Setup Odoo as a Systemd Service ==="
sudo bash -c "cat > $ODOO_SERVICE" <<EOF
[Unit]
Description=$ODOO_USER Odoo Service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=$ODOO_USER
PermissionsStartOnly=true
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo-bin -c $ODOO_CONFIG
StandardOutput=journal+console
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 755 $ODOO_SERVICE
sudo systemctl daemon-reload
sudo systemctl enable $ODOO_USER
sudo systemctl start $ODOO_USER

#--------------------------------------------------
# Install and Configure Nginx (Optional)
#--------------------------------------------------
if [ "$INSTALL_NGINX" = "true" ]; then
    echo -e "\n---- Installing and setting up Nginx ----"
    sudo apt install nginx -y

    echo "=== Configuring Nginx for Odoo ==="
    NGINX_CONF="/etc/nginx/sites-available/$ODOO_USER.conf"
    sudo bash -c "cat > $NGINX_CONF" <<EOF
upstream odoo {
    server 127.0.0.1:$OE_PORT;
}
upstream odoochat {
    server 127.0.0.1:$LONGPOLL_PORT;
}

server {
    listen 80;
    server_name $WEBSITE_NAME www.$WEBSITE_NAME;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    # Add Headers for odoo proxy mode
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    # log
    access_log /var/log/nginx/odoo.access.log;
    error_log /var/log/nginx/odoo.error.log;

    # Redirect requests to odoo backend server
    location / {
        proxy_redirect off;
        proxy_pass http://odoo;
    }
    location /longpolling {
        proxy_pass http://odoochat;
    }

    # common gzip
    gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
    gzip on;

    client_body_in_file_only clean;
    client_body_buffer_size 32K;
    client_max_body_size 500M;
    sendfile on;
    send_timeout 600s;
    keepalive_timeout 300;
}
EOF

    echo "=== Enabling Nginx Configuration ==="
    sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/
    sudo bash -c "echo 'proxy_mode = True' >> $ODOO_CONFIG"
    sudo nginx -t && sudo systemctl restart nginx
    echo "Nginx configured successfully!"
fi

#--------------------------------------------------
# Enable SSL with Certbot
#--------------------------------------------------
if [ "$INSTALL_NGINX" = "true" ] && [ "$ENABLE_SSL" = "True" ] && [ "$ADMIN_EMAIL" != "odoo@example.com" ] && [ "$WEBSITE_NAME" != "_" ]; then
    echo "=== Setting up SSL with Certbot ==="
    sudo apt-get update -y
    sudo apt install snapd -y
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
    sudo apt-get install python3-certbot-nginx -y
    
    if [ -f "/etc/nginx/sites-available/$ODOO_USER.conf" ]; then
        sudo certbot --nginx -d $WEBSITE_NAME -d www.$WEBSITE_NAME \
            --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
        sudo systemctl reload nginx
        echo "SSL/HTTPS is enabled!"
    else
        echo "Nginx configuration missing! SSL setup skipped."
    fi
else
    echo "SSL/HTTPS isn't enabled due to choice or configuration:"
    [ "$ADMIN_EMAIL" = "odoo@example.com" ] && echo " - Invalid email address"
    [ "$WEBSITE_NAME" = "_" ] && echo " - Invalid website name"
fi

#--------------------------------------------------
# Installation Complete
#--------------------------------------------------
echo "=== Installation Complete ==="
echo "-----------------------------------------------------------"
echo "Odoo Server Information:"
echo "URL: http://$WEBSITE_NAME:$OE_PORT"
echo "Port: $OE_PORT"
echo "System User: $ODOO_USER"
echo "Config: $ODOO_CONFIG"
echo "Logs: /var/log/odoo/$ODOO_USER.log"
echo "PostgreSQL User: $ODOO_DB_USER"
echo "PostgreSQL Password: $ODOO_DB_PASS"
echo "Code: $ODOO_HOME"
echo "Custom Addons: $ODOO_HOME/custom/"
echo "Admin Password: $ADMIN_PASSWORD"
echo "Service Management:"
echo "  Start: sudo systemctl start $ODOO_USER"
echo "  Stop: sudo systemctl stop $ODOO_USER"
echo "  Status: sudo systemctl status $ODOO_USER"
echo "  Logs: journalctl -u $ODOO_USER -f"

if [ "$INSTALL_NGINX" = "true" ]; then
    echo "Nginx Config: /etc/nginx/sites-available/$ODOO_USER.conf"
    [ "$ENABLE_SSL" = "True" ] && echo "HTTPS Enabled: https://$WEBSITE_NAME"
fi

echo "-----------------------------------------------------------"
echo "Installation completed successfully!"
