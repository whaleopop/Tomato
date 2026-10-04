#!/usr/bin/env bash
# On the VPS (Ubuntu), in the folder with royaltim_server.<arch>, royaltim_backend.py, catalog.json
# and royaltim-backend.service:   sudo ./install_backend.sh
# Installs the backend (accounts, matchmaking) into /opt/royaltim, keeps the database in
# /opt/royaltim/data, opens TCP 8080 + UDP 7777-7786 and (re)starts the service. A standalone
# game server (royaltim.service) is stopped: the backend starts one per match.
set -euo pipefail
DIR=/opt/royaltim

id royaltim >/dev/null 2>&1 || useradd --system --home-dir "$DIR" --shell /usr/sbin/nologin royaltim
mkdir -p "$DIR/data"
install -m 755 royaltim_server.* "$DIR/royaltim_server"
install -m 644 royaltim_backend.py catalog.json "$DIR/"
chown -R royaltim:royaltim "$DIR"
chmod 700 "$DIR/data"
install -m 644 royaltim-backend.service /etc/systemd/system/royaltim-backend.service

# 2 GB of RAM: a swap file keeps a spike from killing a match
if ! swapon --show | grep -q /swapfile; then
	fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
	grep -q /swapfile /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

# Firewalls that may be on (Oracle-style iptables REJECT, ufw)
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
	ufw allow 8080/tcp && ufw allow 7777:7786/udp
fi
iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 8080 -j ACCEPT
iptables -C INPUT -p udp --dport 7777:7786 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport 7777:7786 -j ACCEPT
if command -v netfilter-persistent >/dev/null; then
	netfilter-persistent save
fi

systemctl disable --now royaltim 2>/dev/null || true
systemctl daemon-reload
systemctl enable royaltim-backend
systemctl restart royaltim-backend
sleep 2
systemctl --no-pager status royaltim-backend | head -n 5
curl -s http://127.0.0.1:8080/status || true
echo
echo "Logs: journalctl -u royaltim-backend -f   (each match: $DIR/data/logs/match_<id>.log)"
