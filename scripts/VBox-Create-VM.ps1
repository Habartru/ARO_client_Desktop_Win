#requires -version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$IsoPath,
  [Parameter(Mandatory=$true)][string]$VmDir,
  [string]$VmName = "ARO-Client",
  [int]$Cpu = 4,
  [int]$MemoryGB = 8,
  [int]$DiskGB = 80
)

$ErrorActionPreference = 'Stop'
function Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "[ERROR] $m" -ForegroundColor Red }

# Validate VBoxManage
try {
  $VBoxManage = (Get-Command VBoxManage.exe -ErrorAction Stop).Source
} catch {
  Err "VBoxManage.exe not found. Please install Oracle VirtualBox and add it to PATH."
  exit 1
}

if (-not (Test-Path $IsoPath)) { Err "ISO not found: $IsoPath"; exit 1 }

# Paths
$VmPath  = Join-Path $VmDir $VmName
$VdiPath = Join-Path $VmDir ("{0}.vdi" -f $VmName)
New-Item -ItemType Directory -Path $VmPath -Force | Out-Null

# Check existing VM
$exists = & $VBoxManage list vms | Select-String -SimpleMatch '"' + $VmName + '"'
if ($exists) {
  Warn "VM $VmName already exists. It will be updated and started."
} else {
  Info "Creating VM $VmName"
  & $VBoxManage createvm --name $VmName --register --basefolder $VmDir | Out-Null
}

# OS type: use generic 64-bit
& $VBoxManage modifyvm $VmName --ostype "Other_64" | Out-Null
& $VBoxManage modifyvm $VmName --memory ($MemoryGB * 1024) --cpus $Cpu --ioapic on --pae on | Out-Null
& $VBoxManage modifyvm $VmName --firmware efi | Out-Null

# Networking: prefer bridged adapter if available, else NAT
$bridged = (& $VBoxManage list bridgedifs) -join "\n"
if ($bridged -match "Name: ") {
  $ifname = ($bridged | Select-String -Pattern "^Name:\s+(.+)$" -AllMatches).Matches | Select-Object -First 1
  if ($ifname) {
    $nic = $ifname.Groups[1].Value.Trim()
    Info "Using bridged adapter: $nic"
    & $VBoxManage modifyvm $VmName --nic1 bridged --bridgeadapter1 "$nic" | Out-Null
  } else {
    Warn "No bridged adapter parsed. Falling back to NAT."
    & $VBoxManage modifyvm $VmName --nic1 nat | Out-Null
  }
} else {
  Warn "No bridged adapters found. Using NAT."
  & $VBoxManage modifyvm $VmName --nic1 nat | Out-Null
}

# Storage controllers
# Remove existing controllers if any (ignore errors)
& $VBoxManage storagectl $VmName --name "SATA" --remove 2>$null
& $VBoxManage storagectl $VmName --name "IDE"  --remove 2>$null

& $VBoxManage storagectl $VmName --name "SATA" --add sata --controller IntelAhci --portcount 2 --bootable on | Out-Null

# Create disk if missing
if (-not (Test-Path $VdiPath)) {
  Info "Creating virtual disk: $DiskGB GB"
  & $VBoxManage createmedium disk --filename $VdiPath --size ($DiskGB * 1024 * 1024) --format VDI | Out-Null
}

# Attach disk and ISO
& $VBoxManage storageattach $VmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $VdiPath | Out-Null
& $VBoxManage storageattach $VmName --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium $IsoPath | Out-Null

# Boot order: DVD first, then disk
& $VBoxManage modifyvm $VmName --boot1 dvd --boot2 disk --boot3 none --boot4 none | Out-Null

# Start headless
Info "Starting VM (headless)"
& $VBoxManage startvm $VmName --type headless | Out-Null

Info "VM started. Use VirtualBox Manager or 'VBoxManage showvminfo \"$VmName\"' to check status."
