#!/usr/bin/env bash
# ================================================================
#  Postfix + SendGrid Setup Script
#  This script installs and configures Postfix as an SMTP relay
#  for SendGrid, sets a verified sender email, and sends a test email.
# ================================================================

set -euo pipefail

# --- FUNCTIONS ---------------------------------------------------
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "Run as root (sudo)."; }

# --- CHECK ROOT ---------------------------------------------------
need_root

# --- USER INPUT ---------------------------------------------------
read -rp "Enter your verified sender email (e.g., no-reply@yourdomain.com): " SENDER
[ -n "$SENDER" ] || die "Sender email cannot be empty."

read -rp "Enter your server hostname (e.g., gophish.yourdomain.com): " HOSTNAME
[ -n "$HOSTNAME" ] || die "Hostname cannot be empty."

read -srp "Enter your SendGrid API key: " SGKEY
echo
[ -n "$SGKEY" ] || die "API key cannot be empty."

read -rp "Enter a test recipient email (e.g., your Gmail): " TEST_RECIP
[ -n "$TEST_RECIP" ] || die "Test recipient cannot be empty."

DOMAIN="${SENDER#*@}"

echo "[*] Installing Postfix and required packages..."
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y postfix mailutils libsasl2-modules ca-certificates

echo "[*] Configuring server hostname and mailname..."
hostnamectl set-hostname "$HOSTNAME" || true
echo "$DOMAIN" > /etc/mailname

# --- MAIN.CF CONFIG ---------------------------------------------
echo "[*] Creating /etc/postfix/main.cf ..."
cat > /etc/postfix/main.cf <<EOF
# ================================================================
#  Postfix Main Configuration for SendGrid
# ================================================================

myhostname = ${HOSTNAME}
myorigin = /etc/mailname
mydestination = \$myhostname, localhost.\$mydomain, localhost
relayhost = [smtp.sendgrid.net]:2525

# SMTP AUTH with SendGrid
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

# Force verified sender
sender_canonical_maps = hash:/etc/postfix/sender_canonical

# Restrictions to avoid open relay
smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination

# Miscellaneous
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = ipv4
append_dot_mydomain = no
EOF

# --- SASL_PASSWD CONFIG ------------------------------------------
echo "[*] Creating /etc/postfix/sasl_passwd ..."
cat > /etc/postfix/sasl_passwd <<EOF
[smtp.sendgrid.net]:2525 apikey:${SGKEY}
EOF
postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd

# --- SENDER_CANONICAL CONFIG --------------------------------------
echo "[*] Creating /etc/postfix/sender_canonical ..."
cat > /etc/postfix/sender_canonical <<EOF
root@${HOSTNAME} ${SENDER}
root@${HOSTNAME}.localdomain ${SENDER}
root@localhost ${SENDER}
root ${SENDER}
EOF
postmap /etc/postfix/sender_canonical

# --- RESTART POSTFIX ----------------------------------------------
echo "[*] Restarting Postfix..."
systemctl restart postfix

# --- TEST EMAIL ---------------------------------------------------
echo "[*] Sending test email to ${TEST_RECIP} ..."
echo "Postfix SendGrid test email from ${SENDER}" | mail -s "Postfix Test" "${TEST_RECIP}"

echo "================================================================="
echo "DONE!"
echo " - Check logs with: tail -f /var/log/mail.log"
echo " - You should see: relay=smtp.sendgrid.net ... status=sent"
echo
echo " - In GoPhish, set Sending Profile to:"
echo "     Host: 127.0.0.1:25"
echo "     Username/Password: (leave blank)"
echo "     From: ${SENDER}"
echo "================================================================="