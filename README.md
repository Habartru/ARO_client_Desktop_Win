<div align="center">

<h1>
  <img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&size=30&duration=3000&pause=1000&color=00D4FF&center=true&vCenter=true&width=600&lines=ARO+CLIENT+DESKTOP+LAUNCHER;Windows+One-Click+Deployment;Auto-Detection+%E2%9A%A1+Hyper-V+%E2%9A%A1+VirtualBox" alt="Typing SVG" />
</h1>

<p>
  <img src="https://img.shields.io/badge/Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Windows"/>
  <img src="https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell"/>
  <img src="https://img.shields.io/badge/Hyper--V-0078D4?style=for-the-badge&logo=microsoft&logoColor=white" alt="Hyper-V"/>
  <img src="https://img.shields.io/badge/VirtualBox-183A61?style=for-the-badge&logo=virtualbox&logoColor=white" alt="VirtualBox"/>
</p>

<p>
  <img src="https://img.shields.io/badge/version-v0.1.0-blue?style=for-the-badge" alt="Version"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License"/>
  <img src="https://img.shields.io/badge/status-active-success?style=for-the-badge" alt="Status"/>
</p>

</div>

# ARO Client: Windows One-Click Launcher

This project provides a one-click way to deploy and run the ARO Client (ISO image) in a virtual machine on Windows 10/11.
The flow is highly automated: resource auto-discovery, hypervisor selection, ISO auto-download/validation, VM auto-start and console auto-open.

## Requirements
- Windows 10/11 64-bit.
- Administrator rights (the launcher will request elevation via UAC).
- The `aro-client-latest.iso` file in the project root: `./aro-client-latest.iso` (downloaded automatically if missing or unreadable).
- For Hyper‑V: Windows Pro/Enterprise with Hyper‑V role enabled and virtualization enabled in BIOS.
- For VirtualBox: Oracle VirtualBox installed and `VBoxManage.exe` available in `PATH`.

## Project layout
- `Run-Me-AroClient.bat` — launcher (admin elevation + interactive preset menu).
- `scripts/Setup-AroClient.ps1` — orchestrator (auto-config, ISO check/download, Hyper‑V/VBox selection, logging).
- `scripts/HyperV-Create-VM.ps1` — create/update/start VM on Hyper‑V; auto ISO detachment after OS detection.
- `scripts/VBox-Create-VM.ps1` — create/update/start VM on VirtualBox.
- `vm/` — VM files (created automatically).
- `logs/` — setup logs (created automatically).

## Quick start
1) Double-click `Run-Me-AroClient.bat` and approve UAC.
2) Choose a preset in the menu (or press Enter for `auto`).
3) The script will:
   - Download and validate the ISO if required;
   - Pick resources and create/update the `ARO-Client` VM;
   - Start the VM and open the Hyper‑V console (if Hyper‑V is used).
4) In the console window, complete ARO Client installation/initialization per docs: https://docs.aro.network/user-guides/software-setup/

## Auto-configuration and presets
- VM name: `ARO-Client`.
- Resources (vCPU, RAM, Disk) are auto-selected by `scripts/Setup-AroClient.ps1` based on:
  - logical CPU threads,
  - total RAM,
  - free space on the system SSD (drive `C:` by default),
  - fastest active physical NIC link speed (100 Mb/s, 1 Gb/s, 10 Gb/s, etc.).
- Presets: `auto`, `lite`, `standard`, `perf` (interactive menu or env var `ARO_PRESET`).
- The script keeps headroom for the host (at least 2 CPU threads and 8 GB RAM; and ≥20 GB free SSD beyond the VM disk).

Boot order: DVD (ISO) first, then disk. VM storage lives under `./vm/`.

## Networking
- Hyper‑V: tries `Default Switch`. If absent — the first external vSwitch. If none — creates an internal vSwitch with NAT (`ARO-NAT-Switch`).
- VirtualBox: bridged adapter if available; otherwise NAT.
Note: ARO requirements (TCP 80/443/9500–9700 and UDP: all) may require an external vSwitch or proper router/NAT configuration.

## Troubleshooting
- Hyper‑V unavailable or DISM/logs access error: run the launcher as Administrator (it will prompt), then enable Hyper‑V:
  `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart` and reboot.
- VT‑x/EPT disabled: enable “Intel Virtualization Technology (VT‑x)” and “Intel VT‑d/EPT” in BIOS.
- VirtualBox not found: install Oracle VirtualBox and ensure `VBoxManage.exe` is in `PATH`.
- No internet in VM (Hyper‑V NAT): ensure `New-NetNat` exists and the `vEthernet (ARO-NAT-Switch)` interface has an IP; or connect the VM to an external vSwitch.

## Security and limitations
- Scripts may create Hyper‑V virtual switches and NAT rules — that changes host networking.
- All commands are designed for PowerShell on Windows 10+.

## Donations
- ARO address: `0xB0D1f32C900745f7b11167e69c3b569F89A67e2C`

## Referral
- If you are new to ARO, feel free to sign up via this referral link:
  - https://dashboard.aro.network/signup?referral=GKF0Q0
- Automation support in scripts:
  - `scripts/Setup-AroClient.ps1` prints the referral link after successful setup.
  - You can override the link with env var `ARO_REFERRAL_URL`.
  - Set `ARO_OPEN_REFERRAL=1` to auto-open the referral URL after setup.

## Support
If you need to tune resources, disks, networking, or run multiple nodes, open an issue or contact the maintainer. We will adapt the scripts and update the docs.
