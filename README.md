# UltraClaw OS

> Ubuntu 24.04 with a personal AI assistant built in. Boot from USB and start talking to your local AI in minutes.

## What is UltraClaw OS?

UltraClaw OS is a ready-to-use Linux operating system based on Ubuntu 24.04 LTS. It comes with the UltraClaw AI assistant pre-installed and configured to run entirely on your own hardware — no cloud required, no subscriptions, no data leaving your machine.

When you boot from the USB drive, you'll find:

- A clean dark desktop environment ready to use
- The UltraClaw Gateway running automatically at `localhost:18790`
- Firefox opening directly to the UltraClaw interface
- A setup wizard to install Ollama and download your AI model

## Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| RAM | 8 GB | 16 GB |
| Storage | 20 GB free | 50 GB free |
| USB drive | 4 GB | 8 GB |
| Architecture | x86_64 | x86_64 |

## Download

Get the latest ISO from the [Releases page](https://github.com/Dedeg0/ultraclaw-os/releases).

## Flash to USB

**Windows** — use [Balena Etcher](https://etcher.balena.io/):
1. Download and open Balena Etcher
2. Select the `.iso` file
3. Select your USB drive (minimum 4 GB)
4. Click Flash

**Linux / macOS:**
```bash
sudo dd if=ultraclaw-os-vX.X.X-amd64.iso of=/dev/sdX bs=4M status=progress
```
Replace `/dev/sdX` with your USB device.

## Verify the download

```bash
sha256sum -c ultraclaw-os-vX.X.X-amd64.iso.sha256
```

## First boot

1. Boot from the USB drive
2. Log in with username `ultraclaw` and password `ultraclaw`
3. Firefox opens automatically with the UltraClaw interface
4. Firefox opens automatically — click **Install Ollama** to set up your local AI model
5. The download is approximately 4 GB — make sure you have a stable internet connection

## Default credentials

| Field | Value |
|-------|-------|
| Username | `ultraclaw` |
| Password | `ultraclaw` |

> The default password is `ultraclaw` — no change required.

## Accessing the AI interface

Open Firefox and go to `http://localhost:18790` — or use the UltraClaw shortcut in the taskbar.

The gateway starts automatically on every boot. You can check its status anytime by opening a terminal (`Super+T`) and running:

```bash
systemctl status ultraclaw-gateway
```

## License

MIT — based on [OpenCLAW](https://github.com/openclaw/openclaw) by Peter Steinberger and contributors.