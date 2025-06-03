#!/bin/bash

# Common variables
ODOO_USER="odoo18"
ODOO_HOME="/opt/$ODOO_USER"
ODOO_REPO="https://www.github.com/odoo/odoo"
ODOO_BRANCH="18.0"
ODOO_CONFIG="/etc/$ODOO_USER.conf"
ODOO_SERVICE="/etc/systemd/system/$ODOO_USER.service"
ODOO_DB_USER="$ODOO_USER"
ODOO_DB_PASS="123456"
OE_PORT="8069"
LONGPOLL_PORT="8072"
# Set the website name
WEBSITE_NAME="_"
# Set the default Odoo longpolling port (you still have to use -c /etc/odoo-server.conf for example to use this.)
LONGPOLLING_PORT="8072"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate
ADMIN_EMAIL="odoo@example.com"
 # Set to 'true' to install and configure Nginx
INSTALL_NGINX=true

echo "=== Step 2: Update the Server ==="
sudo apt-get update && sudo apt-get upgrade -y

echo "=== Step 3: Secure the Server ==="
sudo apt-get install -y openssh-server fail2ban
sudo systemctl start fail2ban
sudo systemctl enable fail2ban
sudo systemctl status fail2ban

echo "=== Step 4: Install Packages and Libraries ==="
sudo apt-get install -y python3-pip python3-dev libxml2-dev libxslt1-dev zlib1g-dev \
libsasl2-dev libldap2-dev build-essential libssl-dev libffi-dev libmysqlclient-dev \
libjpeg-dev libpq-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev \
npm node-less git

# Create node symlink
sudo ln -s /usr/bin/nodejs /usr/bin/node || true

# Install less and clean-css
sudo npm install -g less less-plugin-clean-css

echo "=== Step 5: Set Up the Database Server ==="
sudo apt-get install -y postgresql
# sudo -u postgres createuser --createdb --username postgres --no-createrole --superuser --pwprompt $ODOO_DB_USER
sudo -u postgres psql -c "CREATE ROLE $ODOO_DB_USER WITH LOGIN SUPERUSER CREATEDB PASSWORD '$ODOO_DB_PASS';"

echo "=== Step 6: Create a System User for Odoo ==="
sudo adduser --system --home=$ODOO_HOME --group $ODOO_USER

echo "=== Step 7: Clone Odoo Repository ==="
sudo -u $ODOO_USER -H bash -c "
cd $ODOO_HOME
git clone $ODOO_REPO --depth 1 --branch $ODOO_BRANCH --single-branch .
"

echo "=== Step 8: Setup Python Virtual Environment and Install Dependencies ==="
sudo apt install -y python3-venv xfonts-75dpi
sudo python3 -m venv $ODOO_HOME/venv
sudo -u $ODOO_USER -H bash -c "
source $ODOO_HOME/venv/bin/activate
pip install -r $ODOO_HOME/requirements.txt
deactivate
"

echo -e "\n---- Create custom module directory ----"
sudo su $OE_USER -c "mkdir -p $OE_HOME/custom"

echo "=== Step 9: Configure Odoo ==="
sudo cp $ODOO_HOME/debian/odoo.conf $ODOO_CONFIG
sudo bash -c "cat > $ODOO_CONFIG" <<EOF
[options]
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = $ODOO_DB_USER
db_password = $ODOO_DB_PASS
addons_path = $ODOO_HOME/addons, $OE_HOME/custom
default_productivity_apps = True
without_demo = all
proxy_mode = True
logfile = /var/log/odoo/$ODOO_USER.log
longpolling_port = $LONGPOLL_PORT
http_port = $OE_PORT
EOF

sudo chown $ODOO_USER: $ODOO_CONFIG
sudo chmod 640 $ODOO_CONFIG

# Create log directory
sudo mkdir -p /var/log/odoo
sudo chown $ODOO_USER:root /var/log/odoo

echo "=== Step 10: Setup Odoo as a Systemd Service ==="
sudo bash -c "cat > $ODOO_SERVICE" <<EOF
[Unit]
Description=Odoo18
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo18
PermissionsStartOnly=true
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo-bin -c $ODOO_CONFIG
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 755 $ODOO_SERVICE
sudo chown root: $ODOO_SERVICE

if [ "$INSTALL_NGINX" = true ]; then
    echo -e "\n---- Installing and setting up Nginx ----"
    sudo apt install nginx -y

    echo "=== Configuring Nginx for Odoo ==="
    NGINX_CONF="/etc/nginx/sites-available/$WEBSITE_NAME"
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
    sudo nginx -t && sudo systemctl restart nginx
    sudo service nginx reload
    sudo su root -c "printf 'proxy_mode = True\n' >> /etc/${OE_CONFIG}.conf"
    echo "Done! The Nginx server is up and running."
fi

#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------

if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "odoo@example.com" ]  && [ $WEBSITE_NAME != "_" ];then
  sudo apt-get update -y
  sudo apt install snapd -y
  sudo snap install core; snap refresh core
  sudo snap install --classic certbot
  sudo apt-get install python3-certbot-nginx -y
  sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  sudo service nginx reload
  echo "SSL/HTTPS is enabled!"
else
  echo "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
  if $ADMIN_EMAIL = "odoo@example.com";then 
    echo "Certbot does not support registering odoo@example.com. You should use real e-mail address."
  fi
  if $WEBSITE_NAME = "_";then
    echo "Website name is set as _. Cannot obtain SSL Certificate for _. You should use real website address."
  fi
fi

echo "=== Installation Complete ==="
echo "To start Odoo, run: sudo systemctl start odoo18"
echo "To enable Odoo at boot: sudo systemctl enable odoo18"
