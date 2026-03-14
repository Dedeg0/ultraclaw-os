#!/usr/bin/env bash
# scripts/chroot-setup.sh
# Runs inside the chroot during ISO build
export DEBIAN_FRONTEND=noninteractive
export ULTRACLAW_NONINTERACTIVE=1
export ULTRACLAW_OS=1

echo "==> Running base installer..."
cd /tmp/ultraclaw
bash install.sh --non-interactive || echo "Installer warnings (continuing...)"

echo "==> Installing theme..."
if [ -f /tmp/ultraclaw/theme/install-theme.sh ]; then
  bash /tmp/ultraclaw/theme/install-theme.sh
fi

echo "==> Installing Node.js 22..."
apt-get update -qq
apt-get install -y curl
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
node --version && npm --version

echo "==> Installing pnpm and ultraclaw CLI..."
npm install -g pnpm@latest
npm install -g /opt/ultraclaw/core
echo "ultraclaw CLI installed"

echo "==> Installing Firefox..."
apt-get install -y firefox || snap install firefox || true

echo "==> Creating ultraclaw user..."
useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev ultraclaw 2>/dev/null || true
echo 'ultraclaw:ultraclaw' | chpasswd
passwd -e ultraclaw 2>/dev/null || true

echo "==> Setting up UltraClaw Gateway service..."
cat > /etc/systemd/system/ultraclaw-gateway.service << 'EOF'
[Unit]
Description=UltraClaw Gateway
After=network-online.target ollama.service
Wants=network-online.target

[Service]
Type=simple
User=ultraclaw
WorkingDirectory=/home/ultraclaw
ExecStart=/usr/local/bin/ultraclaw gateway --port 18790
Restart=on-failure
RestartSec=5
Environment=ULTRACLAW_OS=1
Environment=HOME=/home/ultraclaw
EnvironmentFile=-/etc/ultraclaw/env

[Install]
WantedBy=multi-user.target
EOF

systemctl enable ultraclaw-gateway.service 2>/dev/null || true
systemctl enable ollama.service            2>/dev/null || true
systemctl enable claw-kernel.service       2>/dev/null || true

echo "==> Configuring Firefox homepage..."
mkdir -p /home/ultraclaw/.mozilla/firefox/ultraclaw.default

cat > /home/ultraclaw/.mozilla/firefox/profiles.ini << 'EOF'
[Install]
DefaultProfile=ultraclaw.default

[Profile0]
Name=UltraClaw
IsRelative=1
Path=ultraclaw.default
Default=1
EOF

cat > /home/ultraclaw/.mozilla/firefox/ultraclaw.default/user.js << 'EOF'
user_pref("browser.startup.homepage", "http://localhost:18790");
user_pref("browser.startup.page", 1);
user_pref("browser.sessionstore.resume_previous_session", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
EOF

chown -R ultraclaw:ultraclaw /home/ultraclaw/.mozilla

echo "==> Writing OS config..."
mkdir -p /etc/ultraclaw /etc/skel/.ultraclaw /home/ultraclaw/.ultraclaw
cp /opt/ultraclaw/core/.env.ultraclaw           /etc/ultraclaw/env                              2>/dev/null || true
cp /opt/ultraclaw/core/config/ultraclaw-os.json /etc/ultraclaw/config.json                      2>/dev/null || true
cp /opt/ultraclaw/core/config/ultraclaw-os.json /home/ultraclaw/.ultraclaw/ultraclaw.json        2>/dev/null || true
chown -R ultraclaw:ultraclaw /home/ultraclaw/.ultraclaw

echo "==> Configuring GDM (normal login, no autologin)..."
mkdir -p /etc/gdm3
cat > /etc/gdm3/custom.conf << 'EOF'
[daemon]
AutomaticLoginEnable=false
WaylandEnable=false

[security]

[xdmcp]

[chooser]

[debug]
EOF

echo "==> Cleanup..."
apt-get clean
rm -rf /tmp/ultraclaw /var/lib/apt/lists/* /etc/resolv.conf
echo "==> Chroot setup complete!"