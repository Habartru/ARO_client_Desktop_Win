# ARO Client: Windows One-Click Launcher

This project provides a one-click way to deploy and run the ARO Client (ISO image) in a virtual machine on Windows 10/11.
The flow is highly automated: resource auto-discovery, hypervisor selection, ISO auto-download/validation, VM auto-start and console auto-open.

## Features
- Resource auto-detection (vCPU / RAM / Disk) based on host capabilities.
- Presets: `auto`, `lite`, `standard`, `perf` (interactive menu in the launcher).
- Preference: Hyper‑V (if available), otherwise VirtualBox.
- ISO auto-download if missing/corrupted (via BITS/Invoke-WebRequest) and readability check (Mount-DiskImage).
- Auto-detach ISO after detecting an installed OS on the VHDX and set disk as first boot device.
- Auto-open Hyper‑V console (`vmconnect.exe`) after VM start.
- Transcript logging: `logs/setup-YYYYMMDD-HHMMSS.log`.

## Project layout
- `Run-Me-AroClient.bat` — launcher (admin elevation + interactive preset menu).
- `scripts/Setup-AroClient.ps1` — orchestrator (auto-config, ISO check, Hyper‑V/VBox selection, logging).
- `scripts/HyperV-Create-VM.ps1` — create/update/start VM on Hyper‑V; auto ISO detachment.
- `scripts/VBox-Create-VM.ps1` — create/update/start VM on VirtualBox.
- `vm/` — VM files (VHDX/VDI).
- `logs/` — setup logs.

## Quick start
1) Run `Run-Me-AroClient.bat` (double-click). Approve UAC.
2) Choose a preset (or press Enter for `auto`).
3) The script will:
   - Download and validate the ISO if required;
   - Pick resources and create/update the `ARO-Client` VM;
   - Start the VM and open Hyper‑V console (if Hyper‑V is used).
4) In the console window, complete ARO Client installation/initialization per docs: https://docs.aro.network/user-guides/software-setup/

On subsequent runs, the script will detect a filesystem on the VHDX, automatically detach the ISO and set disk boot priority.

## Presets and auto-config
- Presets can be selected in the launcher menu or via env var `ARO_PRESET` (auto|lite|standard|perf).
- Auto-config considers:
  - Logical CPU threads;
  - Total RAM;
  - Free space on the system SSD (`C:` by default);
  - Active physical NIC link speed (100 Mb/s, 1 Gb/s, 10 Gb/s, etc.).
- The script leaves headroom for the host (min 2 CPU threads and 8 GB RAM, and ≥20 GB free SSD space beyond the VM disk).

## Networking
- Hyper‑V: uses `Default Switch` (NAT). If absent, creates an internal vSwitch with NAT (`ARO-NAT-Switch`).
- VirtualBox: bridged adapter if available; otherwise NAT.
- ARO requirements (TCP 80/443/9500–9700 and UDP: all) may require an external vSwitch or proper router/NAT configuration.

## VM management (Hyper‑V)
- Start: `Start-VM -Name "ARO-Client"`
- Stop: `Stop-VM -Name "ARO-Client" -TurnOff -Force`
- Console: `vmconnect.exe localhost "ARO-Client"`
- Detach ISO manually: `Set-VMDvdDrive -VMName "ARO-Client" -Path $null`
- Set disk first boot: `Set-VMFirmware -VMName "ARO-Client" -FirstBootDevice (Get-VMHardDiskDrive -VMName "ARO-Client")`

## Logs
- Path: `logs/setup-YYYYMMDD-HHMMSS.log` (PowerShell transcript).
- On errors, also check the console output and warnings.

## Troubleshooting
- Corrupted/unreadable ISO: the script will report and re-download. Verify connection/AV/storage.
- Hyper‑V unavailable: enable Hyper‑V role on Windows Pro/Enterprise and reboot.
- VirtualBox slow with Hyper‑V enabled: a known WHP limitation.
- No internet in VM (Hyper‑V NAT): reconnect to `Default Switch` or use an external vSwitch.

## Notes
- ARO Client is officially shipped as an x86 VM image (ISO). Docker is not a target on Windows.
- Performance depends on host resources and networking. If the host feels sluggish, select a lighter preset (lite/standard).
