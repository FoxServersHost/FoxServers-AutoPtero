# 🟣 FoxServersHost Auto-Ptero

Fast, automated, professional deployment suite for Pterodactyl + FastDL + Wings.

## 🚀 Features

- ✅ Automatic installation of Pterodactyl Panel
- ✅ Automatic installation of Wings
- ✅ FastDL Agent (CS 1.6, L4D2, MTA, FiveM in future)
- ✅ SSL automatic (Let's Encrypt)
- ✅ Telemetry optional
- ✅ Email report with credentials
- ✅ Auto-updates available
- ✅ Enterprise mode incoming (clusters)

## 📡 Supported Games / Modes
| Game | FastDL | Notes |
|---|---|---|
Counter-Strike 1.6 | ✅ | Classic FastDL
Half-Life Mods | ✅ | AMX/HLDS compatible
Left 4 Dead 2 | ✅ | VPK sync mode
Multi Theft Auto | ✅ | Resource sync
Future: FiveM | 🚧 | Roadmap

## 🛠️ Installation

### Interactive Mode
\`\`\`bash
curl -sSL https://autoinstall.foxsvhost.com/install.sh | bash
\`\`\`

### Silent / WHMCS Mode
\`\`\`bash
PANEL_DOMAIN=panel.example.com \
FASTDL_DOMAIN=fastdl.example.com \
WINGS_DOMAIN=node.example.com \
ADMIN_EMAIL=admin@example.com \
bash <(curl -sSL https://autoinstall.foxsvhost.com/install.sh) --silent
\`\`\`

## 💜 FoxServersHost
Premium hosting automation built with love 🟣
