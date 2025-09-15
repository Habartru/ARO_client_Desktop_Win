#requires -version 5.1
[CmdletBinding()]
param(
  [ValidateSet('auto','lite','standard','perf')]
  [string]$Preset = 'auto'
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$IsoPath = Join-Path $RootDir "aro-client-latest.iso"
$VmDir = Join-Path $RootDir "vm"
$LogsDir = Join-Path $RootDir "logs"
$ReferralUrl = if ($env:ARO_REFERRAL_URL) { $env:ARO_REFERRAL_URL } else { 'https://dashboard.aro.network/signup?referral=GKF0Q0' }
$DonationARO = '0xB0D1f32C900745f7b11167e69c3b569F89A67e2C'

New-Item -ItemType Directory -Path $VmDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null

# Start logging transcript
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logFile = Join-Path $LogsDir ("setup-" + $timestamp + ".log")
try { Start-Transcript -Path $logFile -ErrorAction SilentlyContinue | Out-Null } catch { }

function Test-IsoReadable([string]$path){
  if (-not (Test-Path $path)) { return $false }
  try {
    $img = Mount-DiskImage -ImagePath $path -PassThru -StorageType ISO -NoDriveLetter -ErrorAction Stop
    if ($img) { Dismount-DiskImage -ImagePath $path -ErrorAction SilentlyContinue | Out-Null }
    return $true
  } catch { return $false }
}

function Get-IsoFile([string]$url,[string]$dest){
  Write-Info "Downloading ISO..."
  try {
    Start-BitsTransfer -Source $url -Destination $dest -Description "ARO ISO" -ErrorAction Stop
  } catch {
    Write-Warn "BITS transfer failed, trying Invoke-WebRequest..."
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
  }
}

function Confirm-IsoFile([string]$path){
  $url = 'https://download.aro.network/images/aro-client-latest.iso'
  if (-not (Test-IsoReadable -path $path)){
    Write-Warn "ISO missing or not readable: $path"
    Get-IsoFile -url $url -dest $path
    if (-not (Test-IsoReadable -path $path)){
      Write-Err "ISO still not readable after download: $path"
      Write-Host "Please download manually from $url and retry." -ForegroundColor Red
      exit 1
    }
  }
}

Confirm-IsoFile -path $IsoPath

# If param not explicitly passed, allow env var override
if (-not $PSBoundParameters.ContainsKey('Preset')) {
  if ($env:ARO_PRESET) {
    $Preset = $env:ARO_PRESET.ToLowerInvariant()
  }
}
if (@('auto','lite','standard','perf') -notcontains $Preset) { $Preset = 'auto' }

# Auto-detect optimal resources based on host capabilities
function Get-OptimalResources {
  $cpuThreads = 0
  try {
    $cpuThreads = (Get-CimInstance Win32_Processor | Select-Object -ExpandProperty NumberOfLogicalProcessors | Measure-Object -Sum).Sum
  } catch { $cpuThreads = 2 }

  $totalMemGB = 0
  try {
    $totalMemGB = [int][math]::Floor((Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory) / 1GB)
  } catch { $totalMemGB = 8 }

  # Prefer system drive free space as SSD proxy; fallback to C:
  $sysDrive = $env:SystemDrive
  if ([string]::IsNullOrWhiteSpace($sysDrive)) { $sysDrive = 'C:' }
  $freeSysGB = 0
  try {
    $vol = Get-Volume -DriveLetter $sysDrive.TrimEnd(':') -ErrorAction Stop
    $freeSysGB = [int][math]::Floor($vol.SizeRemaining / 1GB)
  } catch { $freeSysGB = 60 }

  # Detect best link speed among physical/bridged-capable adapters
  $linkGbps = 0
  try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    if (-not $adapters) { $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } }
    if ($adapters) {
      foreach ($a in $adapters) {
        # LinkSpeed is like '100 Mbps' or '1 Gbps' or '10 Gbps'
        $ls = [string]$a.LinkSpeed
        if ($ls -match '([0-9]+)\s*(Gbps|Mbps)') {
          $val = [int]$Matches[1]
          $unit = $Matches[2]
          $gbps = 0
          if ($unit -eq 'Gbps') { $gbps = [double]$val } else { $gbps = [double]($val / 1000) }
          if ($gbps -gt $linkGbps) { $linkGbps = $gbps }
        }
      }
    }
  } catch { $linkGbps = 0 }

  # Baseline targets depending on link speed
  $targetCpu = 2; $targetMemGB = 4; $targetDiskGB = 80
  if ($linkGbps -ge 5) {
    $targetCpu = [int][math]::Ceiling($cpuThreads * 0.5)
    $targetMemGB = [int][math]::Min([math]::Floor($totalMemGB * 0.5), 64)
    $targetDiskGB = 240
  } elseif ($linkGbps -ge 1) {
    $targetCpu = [int][math]::Ceiling($cpuThreads * 0.33)
    $targetMemGB = [int][math]::Min([math]::Floor($totalMemGB * 0.5), 32)
    $targetDiskGB = 120
  } else {
    # <= 100/500 Mbps
    $targetCpu = [int][math]::Ceiling([math]::Max(2, $cpuThreads * 0.25))
    $targetMemGB = [int][math]::Max(8, [math]::Floor($totalMemGB * 0.25))
    $targetDiskGB = 80
  }

  # Leave headroom for host
  $cpu = [int][math]::Min([math]::Max(2, $targetCpu), [math]::Max(2, $cpuThreads - 2))
  $mem = [int][math]::Min([math]::Max(4, $targetMemGB), [math]::Max(4, $totalMemGB - 8))

  # Ensure disk fits into free space with safety buffer (20 GB)
  $safety = 20
  $disk = $targetDiskGB
  if ($freeSysGB -gt ($safety + 50)) {
    $maxDisk = $freeSysGB - $safety
    if ($disk -gt $maxDisk) { $disk = $maxDisk }
  } else {
    $disk = 50
  }
  if ($disk -lt 50) { $disk = 50 }

  return @{ Cpu = $cpu; MemoryGB = $mem; DiskGB = [int]$disk; LinkGbps = $linkGbps; Threads = $cpuThreads; TotalMemGB = $totalMemGB; FreeSysGB = $freeSysGB }
}

$res = Get-OptimalResources
Write-Info ("[Step 1/4] Host analysis complete")
Write-Info ("Auto-selected resources -> CPU: {0} vCPU, RAM: {1} GB, Disk: {2} GB (Link: {3} Gbps, Host: {4} thr/{5} GB RAM, FreeSSD: {6} GB)" -f $res.Cpu, $res.MemoryGB, $res.DiskGB, $res.LinkGbps, $res.Threads, $res.TotalMemGB, $res.FreeSysGB)

# Apply preset overrides
function Set-PresetOverrides($base, $preset) {
  $cpu = $base.Cpu
  $mem = $base.MemoryGB
  $diskDesired = $base.DiskGB

  switch ($preset) {
    'lite' {
      $cpu = [int][math]::Max(2, [math]::Floor($base.Threads * 0.15))
      $mem = [int][math]::Max(4, [math]::Min(8, [math]::Floor($base.TotalMemGB * 0.2)))
      $diskDesired = [int][math]::Max(60, $base.DiskGB)
    }
    'standard' {
      $cpu = [int][math]::Max(4, [math]::Floor($base.Threads * 0.25))
      $mem = [int][math]::Max(8, [math]::Floor($base.TotalMemGB * 0.25))
      $diskDesired = [int][math]::Max(80, $base.DiskGB)
    }
    'perf' {
      $cpu = [int][math]::Max(6, [math]::Ceiling($base.Threads * 0.5))
      $mem = [int][math]::Max(12, [math]::Ceiling($base.TotalMemGB * 0.5))
      $diskDesired = [int][math]::Max(120, $base.DiskGB)
    }
    default { }
  }

  # Re-apply host headroom caps
  $cpu = [int][math]::Min([math]::Max(2, $cpu), [math]::Max(2, $base.Threads - 2))
  $mem = [int][math]::Min([math]::Max(4, $mem), [math]::Max(4, $base.TotalMemGB - 8))

  # Disk safety cap
  $safety = 20
  $maxDisk = 50
  if ($base.FreeSysGB -gt ($safety + 50)) { $maxDisk = $base.FreeSysGB - $safety }
  $disk = [int][math]::Min([math]::Max(50, $diskDesired), $maxDisk)

  return @{ Cpu = $cpu; MemoryGB = $mem; DiskGB = $disk }
}

if ($Preset -ne 'auto') {
  $over = Set-PresetOverrides -base $res -preset $Preset
  $res.Cpu = $over.Cpu
  $res.MemoryGB = $over.MemoryGB
  $res.DiskGB = $over.DiskGB
}

Write-Info ("[Step 2/4] Preset applied: {0}" -f $Preset)
Write-Info ("Using -> CPU: {0} vCPU, RAM: {1} GB, Disk: {2} GB" -f $res.Cpu, $res.MemoryGB, $res.DiskGB)

Write-Info "[Step 3/4] Checking virtualization provider (Hyper-V / VirtualBox)..."
$hvAvailable = $false
try {
  $hvFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
  if ($hvFeature.State -eq 'Enabled') { $hvAvailable = $true }
} catch {
  Write-Warn "Could not query Hyper-V feature state. Assuming not available. Details: $($_.Exception.Message)"
}

if ($hvAvailable) {
  Write-Info "Hyper-V detected. Proceeding with Hyper-V flow."
  $hypervScript = Join-Path $ScriptDir "HyperV-Create-VM.ps1"
  & powershell -NoProfile -ExecutionPolicy Bypass -File $hypervScript -IsoPath $IsoPath -VmDir $VmDir -VmName "ARO-Client" -Cpu $res.Cpu -MemoryGB $res.MemoryGB -DiskGB $res.DiskGB
  $code = $LASTEXITCODE
  Write-Info ("[Step 4/4] Hyper-V flow finished with code {0}" -f $code)
  Write-Info "Summary:"; Write-Info ("  VM Name: ARO-Client"); Write-Info ("  Resources: {0} vCPU / {1} GB RAM / {2} GB Disk" -f $res.Cpu, $res.MemoryGB, $res.DiskGB)
  Write-Info "Next:"; Write-Info "  - A console window should be open (vmconnect). Proceed with installation inside guest OS per docs."
  Write-Info ("Referral: If you are new to ARO, you can sign up using this referral link: {0}" -f $ReferralUrl)
  Write-Info ("Donations (ARO): {0}" -f $DonationARO)
  if ($env:ARO_OPEN_REFERRAL -eq '1') {
    try { Start-Process -FilePath $ReferralUrl -ErrorAction Stop | Out-Null } catch { Write-Warn "Could not open referral URL automatically." }
  }
  if ($code -ne 0) { Write-Err "Hyper-V flow ended with errors. See transcript: $logFile" }
  try { Stop-Transcript | Out-Null } catch { }
  exit $code
}

Write-Warn "Hyper-V not available or disabled. Trying VirtualBox..."

function Test-VirtualBoxInstalled {
  try {
    $vb = (Get-Command VBoxManage.exe -ErrorAction Stop).Source
    if ($vb) { return $true }
  } catch { }
  try {
    $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Oracle\VirtualBox" -ErrorAction Stop
    if ($reg) { return $true }
  } catch { }
  return $false
}

if (Test-VirtualBoxInstalled) {
  Write-Info "VirtualBox detected. Proceeding with VirtualBox flow."
  $vboxScript = Join-Path $ScriptDir "VBox-Create-VM.ps1"
  & powershell -NoProfile -ExecutionPolicy Bypass -File $vboxScript -IsoPath $IsoPath -VmDir $VmDir -VmName "ARO-Client" -Cpu $res.Cpu -MemoryGB $res.MemoryGB -DiskGB $res.DiskGB
  $code = $LASTEXITCODE
  Write-Info ("[Step 4/4] VirtualBox flow finished with code {0}" -f $code)
  Write-Info "Summary:"; Write-Info ("  VM Name: ARO-Client"); Write-Info ("  Resources: {0} vCPU / {1} GB RAM / {2} GB Disk" -f $res.Cpu, $res.MemoryGB, $res.DiskGB)
  Write-Info "Next:"; Write-Info "  - Open VirtualBox Manager and connect to 'ARO-Client'"; Write-Info "  - Install/initialize ARO Client inside guest OS as per docs"
  Write-Info ("Referral: If you are new to ARO, you can sign up using this referral link: {0}" -f $ReferralUrl)
  Write-Info ("Donations (ARO): {0}" -f $DonationARO)
  if ($env:ARO_OPEN_REFERRAL -eq '1') {
    try { Start-Process -FilePath $ReferralUrl -ErrorAction Stop | Out-Null } catch { Write-Warn "Could not open referral URL automatically." }
  }
  exit $code
}

Write-Err "Neither Hyper-V nor VirtualBox are available."
Write-Host "Please enable Hyper-V (Windows 10 Pro/Enterprise) or install VirtualBox, then run again." -ForegroundColor Red
try { Stop-Transcript | Out-Null } catch { }
exit 1

