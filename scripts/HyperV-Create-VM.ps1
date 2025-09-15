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

if (-not (Test-Path $IsoPath)) { Err "ISO not found: $IsoPath"; exit 1 }

# Convert GB to bytes for Hyper-V cmdlets
$MemoryBytes = [int64]$MemoryGB * 1GB
$DiskBytes   = [int64]$DiskGB * 1GB

# Preflight: validate ISO readability (mount/dismount)
try {
  $mounted = $false
  $img = Mount-DiskImage -ImagePath $IsoPath -PassThru -StorageType ISO -NoDriveLetter -ErrorAction Stop
  if ($img) { $mounted = $true }
} catch {
  Err ("ISO validation failed. The file may be corrupted or locked: {0}. Details: {1}" -f $IsoPath, $_.Exception.Message)
  Write-Host "Re-download the image from https://download.aro.network/images/aro-client-latest.iso and try again." -ForegroundColor Yellow
  exit 1
} finally {
  if ($mounted) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
}

# Validate Hyper-V module
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
  Err "Hyper-V PowerShell module not available. Enable Hyper-V features and try again."
  exit 1
}
Import-Module Hyper-V -ErrorAction Stop

# Ensure VM paths
$VhdPath = Join-Path $VmDir ("{0}.vhdx" -f $VmName)
$VmPath  = Join-Path $VmDir $VmName
New-Item -ItemType Directory -Path $VmPath -Force | Out-Null

# Networking: try Default Switch, fallback to first external switch, else create NAT switch
$SwitchName = $null
$default = Get-VMSwitch -SwitchType Internal,External,Private -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default Switch' }
if ($default) { $SwitchName = $default.Name }
if (-not $SwitchName) {
  $ext = Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($ext) { $SwitchName = $ext.Name }
}
if (-not $SwitchName) {
  $natName = 'ARO-NAT-Switch'
  Info "Creating NAT vSwitch: $natName"
  New-VMSwitch -SwitchName $natName -SwitchType Internal | Out-Null
  New-NetIPAddress -IPAddress 192.168.250.1 -PrefixLength 24 -InterfaceAlias ("vEthernet ($natName)") -ErrorAction SilentlyContinue | Out-Null
  New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix 192.168.250.0/24 -ErrorAction SilentlyContinue | Out-Null
  $SwitchName = $natName
}
Info "Using vSwitch: $SwitchName"

# Remove existing VM if partially present (idempotency safe)
$existing = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($existing) {
  Warn "VM $VmName already exists. It will be updated and started."
  if ($existing.State -ne 'Off') { Stop-VM -Name $VmName -TurnOff -Force }
} else {
  Info "Creating VM $VmName (Gen2)"
  New-VM -Name $VmName -Generation 2 -MemoryStartupBytes $MemoryBytes -NewVHDPath $VhdPath -NewVHDSizeBytes $DiskBytes -Path $VmPath -SwitchName $SwitchName | Out-Null
}

# Configure CPU/RAM
Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false -DynamicMemory -MemoryStartupBytes $MemoryBytes -MemoryMinimumBytes $MemoryBytes -MemoryMaximumBytes $MemoryBytes | Out-Null
Set-VMProcessor -VMName $VmName -Count $Cpu | Out-Null

# Storage and ISO
# Ensure DVD drive exists and points to ISO; set boot order DVD first
$dvd = Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue
if (-not $dvd) { Add-VMDvdDrive -VMName $VmName -Path $IsoPath | Out-Null } else { Set-VMDvdDrive -VMName $VmName -Path $IsoPath | Out-Null }
Set-VMFirmware -VMName $VmName -FirstBootDevice $dvd | Out-Null

# If the virtual disk already contains a filesystem, assume OS installed and detach ISO
function Test-VhdBootable([string]$vhd){
  try {
    $mounted = $false
    $vh = Mount-VHD -Path $vhd -ReadOnly -NoDriveLetter -PassThru -ErrorAction Stop
    $mounted = $true
    $diskNum = ($vh | Get-Disk -ErrorAction Stop).Number
    $parts = Get-Partition -DiskNumber $diskNum -ErrorAction Stop
    if ($parts -and ($parts | Measure-Object).Count -gt 0) {
      $vols = Get-Volume -DiskNumber $diskNum -ErrorAction SilentlyContinue
      if ($vols -and ($vols | Where-Object { $_.FileSystem -ne $null }).Count -gt 0) { return $true }
    }
    return $false
  } catch { return $false }
  finally {
    if ($mounted) { Dismount-VHD -Path $vhd -ErrorAction SilentlyContinue | Out-Null }
  }
}

try {
  $hdd = Get-VMHardDiskDrive -VMName $VmName -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hdd -and (Test-Path $hdd.Path)) {
    if (Test-VhdBootable -vhd $hdd.Path) {
      Warn "Detected filesystem on VHDX. Detaching ISO and setting disk as first boot device."
      # Detach ISO and set boot order to disk
      if ($dvd) { Set-VMDvdDrive -VMName $VmName -Path $null | Out-Null }
      $diskBoot = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
      if ($diskBoot) { Set-VMFirmware -VMName $VmName -FirstBootDevice $diskBoot | Out-Null }
    }
  }
} catch { }

# Secure Boot: sometimes ISO needs MicrosoftUEFICertificateAuthority or disabled
try {
  Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority | Out-Null
} catch {
  Warn "Secure Boot template set failed, disabling Secure Boot."
  Set-VMFirmware -VMName $VmName -EnableSecureBoot Off | Out-Null
}

# Start VM
Info "Starting VM $VmName"
Start-VM -Name $VmName | Out-Null

Info "VM started. Opening console window..."
try {
  Start-Process -FilePath vmconnect.exe -ArgumentList @('localhost', "$VmName") -WindowStyle Normal -ErrorAction Stop | Out-Null
} catch {
  Warn "Could not open vmconnect automatically. You can open it manually: vmconnect.exe localhost \"$VmName\""
}

Info "VM is running. Proceed with installation inside the guest OS."
