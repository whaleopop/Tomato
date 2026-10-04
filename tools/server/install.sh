#!/usr/bin/env bash
# On the VPS (Ubuntu), in the folder with royaltim_server.<arch> and royaltim.service:
#   sudo ./install.sh [port]
# Installs a standalone server (no backend: one lobby after another) into /opt/royaltim, opens
# the UDP port in iptables and (re)starts the service.
set -euo pipefail
PORT="${1:-7777}"
DIR=/opt/royaltim

id royaltim >/dev/null 2>&1 || useradd --system --home-dir "$DIR" --shell /usr/sbin/nologin royaltim
mkdir -p "$DIR"
install -m 755 royaltim_server.* "$DIR/royaltim_server"
chown -R royaltim:royaltim "$DIR"
sed "s/--port=7777/--port=$PORT/" royaltim.service > /etc/systemd/system/royaltim.service

# Oracle's Ubuntu images reject everything iptables does not allow (on top of the VCN security list)
if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null; then
	iptables -I INPUT 1 -p udp --dport "$PORT" -j ACCEPT
	if command -v netfilter-persistent >/dev/null; then
		netfilter-persistent save
	fi
fi

systemctl daemon-reload
systemctl enable royaltim
systemctl restart royaltim
sleep 2
systemctl --no-pager status royaltim | head -n 5
echo "Logs: journalctl -u royaltim -f"
