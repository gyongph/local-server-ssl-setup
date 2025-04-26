#!/bin/bash

set -euo pipefail

LAST_CA_FILE="$HOME/.last_used_ca"
CERTS_DIR="/certs"
CA_DIR="/usr/share/ca-certificates/trust-source/anchors"

mkdir -p "$CERTS_DIR"

# Step 1: Select CA option
echo "Select Certificate Authority (CA) option:"
echo "1) Create new CA"
echo "2) Provide existing CA path"
CHOICES="1/2"
if [[ -f "$LAST_CA_FILE" ]]; then
    echo "3) Use previously used CA"
    CHOICES="1/2/3"
fi

read -rp "Enter your choice (${CHOICES}): " CA_CHOICE

# Step 2: Handle CA option
case "$CA_CHOICE" in
    1)
        read -rp "Enter the name of the Certificate Authority organization: " CA_ORG_NAME

        CA_KEY="${CERTS_DIR}/${CA_ORG_NAME}.key.pem"
        CA_CERT="${CERTS_DIR}/${CA_ORG_NAME}.cert.pem"
        CA_CONFIG="${CERTS_DIR}/${CA_ORG_NAME}_ca.cnf"

        cat <<EOF | sudo tee "$CA_CONFIG"
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[ req_distinguished_name ]
CN = ${CA_ORG_NAME}
O = ${CA_ORG_NAME}
C = US

[ v3_ca ]
basicConstraints = critical,CA:TRUE
keyUsage = critical, keyCertSign, cRLSign, digitalSignature
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

        echo "Generating CA key and certificate..."
        sudo openssl genpkey -algorithm RSA -out "$CA_KEY"
        sudo openssl req -x509 -new -key "$CA_KEY" -sha256 -days 3650 -out "$CA_CERT" -config "$CA_CONFIG"

        echo "Trusting the new CA..."
        sudo cp "$CA_CERT" "$CA_DIR/"
        sudo update-ca-trust

        echo -e "${CA_KEY}\n${CA_CERT}" > "$LAST_CA_FILE"

        echo "Certificate Authority created and trusted."
        ;;
    2)
        while true; do
            read -rp "Enter the full path to the CA key file: " CA_KEY
            [[ -f "$CA_KEY" ]] && break
            echo "File not found. Please try again."
        done

        while true; do
            read -rp "Enter the full path to the CA certificate file: " CA_CERT
            [[ -f "$CA_CERT" ]] && break
            echo "File not found. Please try again."
        done

        echo -e "${CA_KEY}\n${CA_CERT}" > "$LAST_CA_FILE"
        echo "Existing CA paths saved for future reuse."
        ;;
    3)
       if [[ -f "$LAST_CA_FILE" ]]; then
    mapfile -t ca_files < "$LAST_CA_FILE"
    CA_KEY="${ca_files[0]}"
    CA_CERT="${ca_files[1]}"

    echo "Using previously saved CA:"
    echo "CA Key: $CA_KEY"
    echo "CA Cert: $CA_CERT"

    if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
        echo "Error: Saved CA files do not exist."
        exit 1
    fi
else
    echo "No previous CA data found."
    exit 1
fi
        ;;
    *)
        echo "Invalid selection. Exiting."
        exit 1
        ;;
esac

# Step 3: Create Server Certificate
read -rp "Enter the name of the organization for the server certificate: " SERVER_ORG_NAME
read -rp "Do you want a wildcard certificate? (yes/no): " WILDCARD_CERT

if [[ "$WILDCARD_CERT" == "yes" ]]; then
    SERVER_CN="*.${SERVER_ORG_NAME}"
else
    SERVER_CN="${SERVER_ORG_NAME}"
fi

SERVER_KEY="${CERTS_DIR}/${SERVER_ORG_NAME}.server.key.pem"
SERVER_CSR="${CERTS_DIR}/${SERVER_ORG_NAME}.server.csr.pem"
SERVER_CERT="${CERTS_DIR}/${SERVER_ORG_NAME}.server.crt.pem"
FULLCHAIN_CERT="${CERTS_DIR}/${SERVER_ORG_NAME}.fullchain.crt.pem"
SERVER_CONFIG="${CERTS_DIR}/${SERVER_ORG_NAME}_server.cnf"

cat <<EOF | sudo tee "$SERVER_CONFIG"
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = ${SERVER_CN}
O = ${SERVER_ORG_NAME}
C = US

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${SERVER_CN}
EOF

echo "Generating server key and CSR..."
sudo openssl genpkey -algorithm RSA -out "$SERVER_KEY"
sudo openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$SERVER_CONFIG"

echo "Signing server certificate with CA..."
sudo openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial -out "$SERVER_CERT" -days 365 -sha256 -extfile "$SERVER_CONFIG" -extensions v3_req

cat "$SERVER_CERT" "$CA_CERT" | sudo tee "$FULLCHAIN_CERT" > /dev/null

echo "Server certificate created and fullchain at: $FULLCHAIN_CERT"

# Step 4: Update /etc/hosts
add_host_entry() {
    local domain=$1
    if ! grep -qE "^[^#]*\s+$domain(\s|\$)" /etc/hosts; then
        echo "Adding $domain to /etc/hosts..."
        echo "127.0.0.1    $domain" | sudo tee -a /etc/hosts > /dev/null
    else
        echo "$domain already exists in /etc/hosts."
    fi
}

MAIN_DOMAIN="${SERVER_CN#*.}"
if [[ "$SERVER_CN" != "$MAIN_DOMAIN" ]]; then
    add_host_entry "$MAIN_DOMAIN"
else
    add_host_entry "$SERVER_CN"
fi

while true; do
    read -rp "Do you want to add another domain to /etc/hosts? (yes/no): " ADD_MORE
    if [[ "$ADD_MORE" == "yes" ]]; then
        read -rp "Enter the domain to map to 127.0.0.1: " EXTRA_DOMAIN
        add_host_entry "$EXTRA_DOMAIN"
    else
        break
    fi
done

# Step 5: Add nginx config
echo "Configure NGINX for your domain(s)."

# Define where the nginx conf will be saved
NGINX_CONF_FILE="/etc/nginx/conf.d/${SERVER_ORG_NAME}.conf"
SSL_CERT="$FULLCHAIN_CERT"
SSL_KEY="$SERVER_KEY"

# Make sure conf.d exists
sudo mkdir -p "$(dirname "$NGINX_CONF_FILE")"

# Variable to store all server blocks
ALL_SERVER_BLOCKS=""

# Start asking for server blocks
while true; do
    echo "Enter the server_name(s) (e.g. www.example.com api.example.com):"
    read NGINX_DOMAINS

    echo "Enter the port your app is running on (e.g. 3000):"
    read APP_PORT

    LOCATION_CONFIG="
    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
    "

    SERVER_BLOCK="
server {
    listen 443 ssl;
    server_name ${NGINX_DOMAINS};

    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
${LOCATION_CONFIG}
}
"
    # Append this server block
    ALL_SERVER_BLOCKS+="$SERVER_BLOCK"$'\n'

    echo "Do you want to configure another server block? (yes/no)"
    read ADD_ANOTHER_SERVER
    ADD_ANOTHER_SERVER=$(echo "$ADD_ANOTHER_SERVER" | tr '[:upper:]' '[:lower:]') # normalize input

    if [[ "$ADD_ANOTHER_SERVER" == "no" || "$ADD_ANOTHER_SERVER" == "n" ]]; then
        break
    elif [[ "$ADD_ANOTHER_SERVER" == "yes" || "$ADD_ANOTHER_SERVER" == "y" ]]; then
        continue
    else
        echo "Invalid input. Please type 'yes' or 'no'."
    fi
done

# Write the full nginx conf
echo "$ALL_SERVER_BLOCKS" | sudo tee "$NGINX_CONF_FILE" > /dev/null

echo "NGINX configuration saved to $NGINX_CONF_FILE"

# Test and reload nginx
echo "Testing NGINX configuration..."
if sudo nginx -t; then
    echo "Reloading NGINX..."
    sudo nginx -s reload
    echo "NGINX reloaded successfully."
else
    echo "Error: NGINX configuration test failed. Fix the errors and try again."
fi

echo "✅ Setup complete!"
