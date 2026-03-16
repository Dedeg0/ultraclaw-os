#!/usr/bin/env bash
# scripts/chroot-setup.sh
# Runs inside the chroot during ISO build
set -e
export DEBIAN_FRONTEND=noninteractive
export ULTRACLAW_NONINTERACTIVE=1
export ULTRACLAW_OS=1

echo "==> Running base installer..."
cd /tmp/ultraclaw
bash install.sh --non-interactive || echo "Installer warnings (continuing...)"

echo "==> Installing theme..."
if [ -f /tmp/ultraclaw/theme/install-theme.sh ]; then
  bash /tmp/ultraclaw/theme/install-theme.sh || true
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
After=network-online.target
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

echo "==> Configuring GNOME dark theme..."
mkdir -p /etc/dconf/db/local.d /etc/dconf/profile

cat > /etc/dconf/profile/user << 'EOF'
user-db:user
system-db:local
EOF

cat > /etc/dconf/db/local.d/01-ultraclaw << 'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Yaru-dark'
icon-theme='Yaru'
cursor-theme='Yaru'
font-name='Ubuntu 11'

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/ultraclaw/uc-01-grid.png'
picture-uri-dark='file:///usr/share/backgrounds/ultraclaw/uc-01-grid.png'
picture-options='zoom'
primary-color='#080808'

[org/gnome/desktop/screensaver]
picture-uri='file:///usr/share/backgrounds/ultraclaw/uc-01-grid.png'
primary-color='#080808'

[org/gnome/shell]
favorite-apps=['firefox-ultraclaw.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop']

[org/gnome/settings-daemon/plugins/media-keys]
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0]
name='Terminal'
command='gnome-terminal'
binding='<Super>t'
EOF

dconf update 2>/dev/null || true
echo "GNOME dark theme configured"

echo "==> Configuring GDM..."
mkdir -p /etc/dconf/db/gdm.d
mkdir -p /etc/gdm3

cat > /etc/dconf/db/gdm.d/01-ultraclaw << 'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Yaru-dark'

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/ultraclaw/uc-02-claw.png'
picture-options='zoom'
primary-color='#080808'
EOF

dconf update 2>/dev/null || true

cat > /etc/gdm3/custom.conf << 'EOF'
[daemon]
AutomaticLoginEnable=false
WaylandEnable=false

[security]

[xdmcp]

[chooser]

[debug]
EOF

echo "GDM configured"

echo "==> Creating Firefox shortcut for UltraClaw Gateway..."
cat > /usr/share/applications/firefox-ultraclaw.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=UltraClaw
Comment=UltraClaw Gateway
Exec=firefox --new-window http://localhost:18790
Icon=/usr/share/plymouth/themes/ultraclaw/logo.png
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
EOF

echo "Firefox shortcut created"

echo "==> Removing unnecessary packages..."
apt-get remove -y --purge \
  libreoffice* \
  thunderbird* \
  aisleriot \
  gnome-mahjongg \
  gnome-mines \
  gnome-sudoku \
  gnome-2048 \
  gnome-chess \
  gnome-klotski \
  gnome-nibbles \
  gnome-robots \
  gnome-tetravex \
  gnome-taquin \
  iagno \
  lightsoff \
  quadrapassel \
  swell-foop \
  hitori \
  printer-driver-* \
  foomatic-db* \
  cups-pk-helper \
  simple-scan \
  cheese \
  rhythmbox \
  totem \
  shotwell \
  gnome-calendar \
  gnome-contacts \
  gnome-maps \
  gnome-music \
  gnome-weather \
  gnome-clocks \
  transmission-* \
  brltty \
  espeak* \
  speech-dispatcher* \
  orca \
  ubuntu-advantage-tools \
  apport \
  whoopsie \
  kerneloops \
  popularity-contest \
  ubuntu-report \
  2>/dev/null || true

echo "==> Removing snaps except firefox..."
snap list 2>/dev/null | grep -v "^Name\|firefox\|snapd" | awk '{print $1}' | \
  xargs -I{} snap remove {} 2>/dev/null || true

echo "==> Removing large locale files..."
find /usr/share/locale -mindepth 1 -maxdepth 1 \
  ! -name 'en' ! -name 'en_US' ! -name 'pt_BR' ! -name 'pt' \
  -exec rm -rf {} + 2>/dev/null || true

find /usr/share/man -mindepth 1 -maxdepth 1 \
  ! -name 'man*' \
  -exec rm -rf {} + 2>/dev/null || true

echo "==> Removing node_modules from opt/ultraclaw (reinstalled on first boot)..."
rm -rf /opt/ultraclaw/core/node_modules 2>/dev/null || true

echo "==> Final cleanup..."
apt-get autoremove -y 2>/dev/null || true
apt-get clean
rm -rf \
  /tmp/ultraclaw \
  /var/lib/apt/lists/* \
  /var/cache/apt/archives/* \
  /usr/share/doc \
  /usr/share/gtk-doc \
  /var/log/*.log \
  /etc/resolv.conf \
  2>/dev/null || true

echo "==> Chroot setup complete!"