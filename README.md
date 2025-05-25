# Local HTTPS Development Environment Setup Script

This bash script automates the setup of a local HTTPS development environment on Linux systems. It handles Certificate Authority (CA) management, server certificate generation (including wildcard support), `/etc/hosts` file modification, and NGINX configuration for proxying requests to your local applications over HTTPS.

## Features

* **Interactive CA Management:**
    * Create a new self-signed Certificate Authority.
    * Use an existing CA by providing paths to its key and certificate.
    * Reuse the CA that was last used with the script.
* **Automatic CA Trusting:** Newly created CAs are automatically added to the system's trust store (uses `update-ca-trust`).
* **Server Certificate Generation:**
    * Generates server keys and Certificate Signing Requests (CSRs).
    * Signs server certificates using the chosen CA.
    * Supports wildcard certificates (e.g., `*.yourdomain.local`).
    * Creates a fullchain certificate.
* **Automated `/etc/hosts` Updates:** Adds entries for your local development domain(s) to `/etc/hosts`, pointing them to `127.0.0.1`.
* **Dynamic NGINX Configuration:**
    * Generates NGINX server block configurations for HTTPS.
    * Proxies requests to your backend application running on a specified port.
    * Supports configuring multiple server blocks for different domains or applications.
* **NGINX Service Management:** Automatically tests the generated NGINX configuration and reloads NGINX if the configuration is valid.

## Prerequisites

Before running this script, ensure you have the following installed:

* **Bash:** The script interpreter.
* **OpenSSL:** Used for all certificate generation and management tasks.
* **NGINX:** The web server that will be configured to use the HTTPS certificates.
* **`sudo` privileges:** The script requires `sudo` for various operations like writing to system directories, updating CA trusts, and managing NGINX.
* **A Linux distribution compatible with `update-ca-trust`:** This command is used to trust the generated CA system-wide (e.g., Fedora, CentOS, Arch Linux). For Debian/Ubuntu based systems, you might need to adjust the script to use `update-ca-certificates` and ensure the CA certificate is placed in the appropriate directory (e.g., `/usr/local/share/ca-certificates/`).

## Usage

1.  **Save the script:** Save the code to a file, for example, `setup_https_dev.sh`.
2.  **Make it executable:**
    ```bash
    chmod +x setup_https_dev.sh
    ```
3.  **Run the script:**
    ```bash
    ./setup_https_dev.sh
    ```
    The script will prompt you for `sudo` password when necessary for specific commands.

4.  **Follow the interactive prompts:**
    * **CA Selection:** Choose to create a new CA, provide paths to an existing CA, or use the CA from the previous run (if available).
        * If creating a new CA, you'll be asked for the CA organization name.
        * If providing an existing CA, you'll be asked for the paths to the CA key and certificate files.
    * **Server Certificate Details:**
        * Enter the organization name for the server certificate.
        * Decide if you want a wildcard certificate (e.g., `*.app.local`) or a specific domain (e.g., `app.local`).
    * **/etc/hosts Entries:** The script will offer to add your primary server domain to `/etc/hosts`. You can then add more domains if needed.
    * **NGINX Configuration:**
        * For each NGINX server block you want to create:
            * Enter the `server_name`(s) (e.g., `app.local www.app.local`).
            * Enter the port your local application is running on (e.g., `3000`).
        * You can configure multiple server blocks.

The script will then perform all necessary actions, and if successful, your NGINX server will be reloaded with the new HTTPS configuration.

## Script Overview

The script performs the following main steps:

1.  **Directory Setup:** Creates a `/certs` directory if it doesn't exist, where all generated keys and certificates (except the trusted CA in the system store) will be stored.
2.  **CA Handling (`$HOME/.last_used_ca`, `/certs`, `/usr/share/ca-certificates/trust-source/anchors`):**
    * Allows creating a new CA (key, certificate, OpenSSL config), trusting it system-wide using `update-ca-trust`.
    * Allows using an existing CA by providing file paths.
    * Stores the paths of the last used CA key and certificate in `$HOME/.last_used_ca` for quick reuse.
3.  **Server Certificate Creation (`/certs`):**
    * Generates a server private key.
    * Generates a Certificate Signing Request (CSR) based on your input (Common Name, organization).
    * Signs the server CSR using the selected CA, creating the server certificate.
    * Creates a `fullchain.crt.pem` file by concatenating the server certificate and the CA certificate.
4.  **/etc/hosts Update:**
    * Adds the specified domain(s) to `/etc/hosts`, mapping them to `127.0.0.1` for local resolution.
5.  **NGINX Configuration (`/etc/nginx/conf.d/`):**
    * Prompts for domain(s) and local application port(s).
    * Generates an NGINX configuration file (e.g., `/etc/nginx/conf.d/your_org_name.conf`).
    * The configuration sets up an HTTPS server listening on port 443, using the generated `fullchain.crt.pem` and server key.
    * It proxies requests to your local application (e.g., `http://127.0.0.1:APP_PORT`).
6.  **NGINX Service:**
    * Tests the NGINX configuration (`nginx -t`).
    * If the test is successful, it reloads NGINX (`nginx -s reload`).

## Generated Files and Locations

* **CA Files (if newly created):**
    * Key: `/certs/<CA_ORG_NAME>.key.pem`
    * Certificate: `/certs/<CA_ORG_NAME>.cert.pem`
    * OpenSSL Config: `/certs/<CA_ORG_NAME>_ca.cnf`
    * Trusted CA Certificate: `/usr/share/ca-certificates/trust-source/anchors/<CA_ORG_NAME>.cert.pem` (path may vary based on `update-ca-trust` specifics)
* **Server Files:**
    * Key: `/certs/<SERVER_ORG_NAME>.server.key.pem`
    * CSR: `/certs/<SERVER_ORG_NAME>.server.csr.pem`
    * Certificate: `/certs/<SERVER_ORG_NAME>.server.crt.pem`
    * Fullchain Certificate: `/certs/<SERVER_ORG_NAME}.fullchain.crt.pem`
    * OpenSSL Config: `/certs/<SERVER_ORG_NAME>_server.cnf`
* **NGINX Configuration:** `/etc/nginx/conf.d/<SERVER_ORG_NAME>.conf`
* **Last Used CA Record:** `$HOME/.last_used_ca`

## Important Notes & Caveats

* **Permissions:** This script performs actions that require `sudo` privileges. It will prompt for your password when `sudo` is needed for a command.
* **System Modifications:** The script modifies system files and configurations:
    * Installs CA certificates into the system trust store.
    * Modifies `/etc/hosts`.
    * Creates NGINX configuration files in `/etc/nginx/conf.d/`.
    * Creates files in `/certs`.
* **Backup:** It's always a good practice to back up sensitive files like `/etc/hosts` or your NGINX configurations if you are unsure, though this script aims to create new, distinctly named NGINX config files.
* **Idempotency:** The script is partially idempotent. Re-running it for the same domains might overwrite previous NGINX configs (if named the same) or add duplicate entries to `/etc/hosts` if not already present. The CA creation/selection part allows reuse.
* **CA Trust:** The method for trusting CAs (`update-ca-trust`) is specific to certain Linux distributions. If you're on a system like Debian or Ubuntu, you might need to adjust the script to use `sudo cp "$CA_CERT" /usr/local/share/ca-certificates/` and then `sudo update-ca-certificates`.
* **Development Only:** The certificates generated by this script are self-signed (or signed by a self-signed CA) and are intended strictly for local development and testing purposes. **Do NOT use them in production environments.**
* **Certificate Validity:** By default, the CA certificate is valid for 3650 days (10 years), and server certificates are valid for 365 days (1 year).
* **Error Handling:** The script uses `set -euo pipefail`, which makes it exit immediately if a command fails or an unset variable is used. Check the output carefully for any error messages.

## Troubleshooting

* **NGINX Configuration Test Failed:** If the script reports an "NGINX configuration test failed," check the output for specific error messages from `nginx -t`. You may need to manually edit the generated NGINX configuration file (located in `/etc/nginx/conf.d/`) to fix issues before NGINX can be reloaded. Common issues include port conflicts or syntax errors.
* **File Permissions:** Ensure the script has execute permissions (`chmod +x setup_https_dev.sh`). Problems might also arise if `sudo` doesn't grant sufficient permissions for some operations, though this is unlikely with typical `sudo` setups.
* **CA Not Trusted in Browser:** After creating and trusting a new CA, you might need to restart your web browser for it to pick up the system's updated CA trust store. Some applications might have their own trust stores.

## License

This script is provided as-is. You are free to use, modify, and distribute it. Please consider the implications of running scripts that modify system configurations.
