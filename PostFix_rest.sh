#!/usr/bin/env bash
# ================================================================
#  Reset Postfix to default configuration
# ================================================================
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "Run as root (sudo)."; }
need_root

echo "[*] WARNING: This will reset Postfix to its default configuration."
read -rp "Are you sure you want to continue? (y/N): " confirm
[[ "$confirm" == "y" || "$confirm" == "Y" ]] || die "Aborted by user."

echo "[*] Stopping Postfix..."
systemctl stop postfix || true

echo "[*] Purging current Postfix configuration..."
rm -f /etc/postfix/main.cf
rm -f /etc/postfix/master.cf
rm -f /etc/postfix/sasl_passwd*
rm -f /etc/postfix/sender_canonical*

echo "[*] Reinstalling Postfix with default settings..."
DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y postfix

echo "[*] Restoring default configuration..."
# Generate default main.cf and master.cf
postfix check || true
dpkg-reconfigure postfix

echo "[*] Restarting Postfix..."
systemctl restart postfix
systemctl status postfix --no-pager

echo "================================================================="
echo "Postfix has been reset to default."
echo "Config files:"
echo " - /etc/postfix/main.cf"
echo " - /etc/postfix/master.cf"
echo
echo "You can now re-run setup-postfix-sendgrid.sh to reconfigure."
echo "================================================================="