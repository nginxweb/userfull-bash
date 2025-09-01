#!/usr/bin/env bash
# CloudPanel post-install bootstrap (no cloudpanel.service)
# - Reads optional /mnt/user-data (password:, fqdn:)
# - Sets MySQL root password (best-effort)
# - (Optional) pulls panel SSL from https://sh.$fqdn/cloud-init/ssl/
# - Restarts nginx + PHP-FPM + DB
# - Prints IP-based panel URL

set -euo pipefail
LOG=/root/cloudpanel-bootstrap.log
exec > >(tee -a "$LOG") 2>&1

echo "=== CloudPanel bootstrap started $(date) ==="

# ----- read /mnt/user-data if attached -----
if ! mountpoint -q /mnt; then mount /dev/sr0 /mnt 2>/dev/null  true; fi
password="$(grep -E '^password:' /mnt/user-data 2>/dev/null | sed 's/password:[[:space:]]*//'  true)"
fqdn="$(grep -E '^fqdn:' /mnt/user-data 2>/dev/null | sed 's/fqdn:[[:space:]]*//'  true)"
umount /dev/sr0 2>/dev/null  true

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ----- set MySQL root password (best-effort) -----
if [ -n "${password:-}" ]; then
  echo "[*] Setting MySQL root password…"
  mysqladmin -u root password "$password" 2>/dev/null  true
  mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${password}'; FLUSH PRIVILEGES;" 2>/dev/null  true
  cat > /root/.my.cnf <<CNF
[client]
user=root
password=${password}
CNF
  chmod 600 /root/.my.cnf
fi

# ----- optional: apply panel SSL pulled from your bootstrap host -----
if [ -n "${fqdn:-}" ]; then
  echo "[*] Attempting to fetch panel SSL from https://sh.${fqdn}/cloud-init/ssl/ …"
  mkdir -p /etc/cloudpanel/ssl
  curl -sk "https://sh.${fqdn}/cloud-init/ssl/${fqdn}.key" -o /etc/cloudpanel/ssl/panel.key  true
  curl -sk "https://sh.${fqdn}/cloud-init/ssl/${fqdn}.crt" -o /etc/cloudpanel/ssl/panel.crt  true
  if [ -s /etc/cloudpanel/ssl/panel.key ] && [ -s /etc/cloudpanel/ssl/panel.crt ]; then
    chmod 600 /etc/cloudpanel/ssl/panel.key
    chmod 644 /etc/cloudpanel/ssl/panel.crt
    # wire nginx vhost certs (best-effort)
    grep -Rl "ssl_certificate" /etc/nginx 2>/dev/null \
      | xargs -r sed -i \
        -e "s#ssl_certificate[[:space:]]\+[^;]\+;#ssl_certificate /etc/cloudpanel/ssl/panel.crt;#g" \
        -e "s#ssl_certificate_key[[:space:]]\+[^;]\+;#ssl_certificate_key /etc/cloudpanel/ssl/panel.key;#g"
  else
    echo "[!] Panel SSL not found on bootstrap host; keeping defaults."
  fi
fi

# ----- restart nginx + all php-fpm versions + DB (there is NO cloudpanel.service) -----
echo "[*] Restarting services…"
systemctl restart nginx  true
for s in $(systemctl list-units --type=service | awk '/php[0-9]+\.[0-9]-fpm\.service/ {print $1}'); do
  systemctl restart "$s"
done
systemctl restart mariadb 2>/dev/null  systemctl restart mysql 2>/dev/null  true
systemctl restart clp-agent 2>/dev/null  true

IP=$(hostname -I | awk '{print $1}')
echo "=== Done. CloudPanel ready at: https://${IP}:8443 ==="