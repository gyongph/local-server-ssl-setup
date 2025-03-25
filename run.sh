#!/bin/bash

# Ask if user wants to create a new CA
echo "Do you want to create a new Certificate Authority (CA)? (yes/no)"
read CREATE_CA

if [[ "$CREATE_CA" == "yes" ]]; then
    # Prompt user for CA organization name
    echo "Enter the name of the Certificate Authority organization:"
    read CA_ORG_NAME

    # Define CA file names
    CA_KEY="/certs/${CA_ORG_NAME}.key.pem"
    CA_CERT="/certs/${CA_ORG_NAME}.cert.pem"
    CA_DIR="/usr/share/ca-certificates/trust-source/anchors"
    CERTS_DIR="/certs"
    CA_CONFIG="/certs/${CA_ORG_NAME}_ca.cnf"

    # Ensure /certs directory exists
    sudo mkdir -p "$CERTS_DIR"

    # Create improved CA configuration file
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

    # Generate private key for Certificate Authority without passphrase
    sudo openssl genpkey -algorithm RSA -out "$CA_KEY"

    # Generate self-signed certificate for Certificate Authority with CA extensions
    sudo openssl req -x509 -new -key "$CA_KEY" -sha256 -days 3650 -out "$CA_CERT" -config "$CA_CONFIG"

    # Copy certificate to trusted anchors directory
    sudo cp "$CA_CERT" "$CA_DIR/"

    # Update the system's trusted certificates
    sudo update-ca-trust

    echo "Certificate Authority setup complete. The CA certificate is now trusted and stored in /certs."
else
    # Ask for existing CA key and certificate
    echo "Enter the full path to the CA key file:"
    read CA_KEY
    echo "Enter the full path to the CA certificate file:"
    read CA_CERT
fi

# Prompt user for server organization name
echo "Enter the name of the organization for the server certificate:"
read SERVER_ORG_NAME

# Ask if the user wants a wildcard certificate
echo "Do you want a wildcard certificate? (yes/no)"
read WILDCARD_CERT

if [[ "$WILDCARD_CERT" == "yes" ]]; then
    SERVER_CN="*.${SERVER_ORG_NAME}"
else
    SERVER_CN="${SERVER_ORG_NAME}"
fi

# Define server file names
SERVER_KEY="/certs/${SERVER_ORG_NAME}.server.key.pem"
SERVER_CSR="/certs/${SERVER_ORG_NAME}.server.csr.pem"
SERVER_CERT="/certs/${SERVER_ORG_NAME}.server.crt.pem"
FULLCHAIN_CERT="/certs/${SERVER_ORG_NAME}.fullchain.crt.pem"
SERVER_CONFIG="/certs/${SERVER_ORG_NAME}_server.cnf"

# Create server configuration file with Subject Alternative Name (SAN)
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

# Generate private key for the server
sudo openssl genpkey -algorithm RSA -out "$SERVER_KEY"

# Generate Certificate Signing Request (CSR) for the server
sudo openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$SERVER_CONFIG"

# Sign the server CSR with the CA certificate to produce the server certificate with SAN
sudo openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial -out "$SERVER_CERT" -days 365 -sha256 -extfile "$SERVER_CONFIG" -extensions v3_req

# Create fullchain certificate (server cert + CA cert)
cat "$SERVER_CERT" "$CA_CERT" | sudo tee "$FULLCHAIN_CERT"

echo "Server certificate created and signed by the CA. The files are stored in /certs."
echo "Fullchain certificate available at: $FULLCHAIN_CERT"

