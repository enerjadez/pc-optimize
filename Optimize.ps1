#Requires -Version 5.1
<#
.SYNOPSIS
  Windows performance pack. Safe on Windows 10/11. Detects this machine.

.DESCRIPTION
  Parks OEM/launcher/telemetry sludge on Manual, clears heavy startup,
  disables idle scheduled tasks, and applies latency/power settings.
  Never disables Defender, Firewall, Windows Update, audio, or core OS.

  APPLY     write changes (default)
  PREVIEW   show the plan, change nothing
  AUDIT     inventory only
  RESTORE   roll back the latest backup on this PC

.PARAMETER KeepLaunchers
  Leave Steam / Epic / Riot / Battle.net / EA / Ubisoft in startup.
.PARAMETER KeepPrinter
  Leave Print Spooler as-is.
.PARAMETER KeepWSL
  Leave the WSL service as-is.
.PARAMETER KeepSearch
  Leave Windows Search indexing running.
.PARAMETER KeepXbox
  Leave Xbox Live services as-is.
.PARAMETER KeepPhone
  Leave Phone Link / phone services as-is.
.PARAMETER NoHags
  Do not enable hardware-accelerated GPU scheduling.
.PARAMETER Yes
  Skip the Y/N confirm.
.PARAMETER NoRestorePoint
  Skip the Windows restore-point attempt.
#>
[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Preview', 'Audit', 'Restore')]
    [string]$Action = 'Apply',

    [switch]$KeepLaunchers,
    [switch]$KeepPrinter,
    [switch]$KeepWSL,
    [switch]$KeepSearch,
    [switch]$KeepXbox,
    [switch]$KeepPhone,
    [switch]$NoHags,
    [switch]$Yes,
    [switch]$NoRestorePoint,

    [string]$BackupRoot = $(Join-Path $env:ProgramData 'WinOptimize')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$script:Results = New-Object System.Collections.Generic.List[object]
$script:IsLaptop = $false
$script:RamGB = 0

# ---------------------------------------------------------------------------
# Catalogs. Wildcards allowed on service names. Manual, never Disabled,
# except Killer/SmartByte (those inject into the NIC and hurt FPS).
# ---------------------------------------------------------------------------
$script:ServiceExact = @(
    # Board / RGB / OEM suites
    'MSI_Center_Service', 'MSI_Case_Service', 'MSIREGISTER_MR'
    'Mystic_Light_Service', 'LightKeeperService'
    'ArmouryCrateService', 'ArmouryCrateControlInterface', 'LightingService'
    'ASUSOptimization', 'ROG Live Service', 'LightingService'
    'AacKingston', 'A-Volute', 'NahimicService', 'Nahimic*', 'SonicStudio3'
    'Razer Game Manager Service', 'RzActionSvc', 'NZXT CAM'
    'logi_lamparray_service', 'LGHUBUpdaterService', 'CorsairService'
    'iCUEDevicePluginHost', 'iCUEUpdateService'
    # Phone / OEM extras
    'ss_conn_service', 'ss_conn_service2'
    'DellClientManagementService', 'SupportAssistAgent', 'Dell SupportAssist'
    'HotKeyServiceUWP', 'HPAppHelperCap', 'HpTouchpointAnalyticsService'
    'ImControllerService', 'LenovoVantageService'
    # Launchers / updaters / bloat
    'GooglePlayGamesServices*', 'Overwolf', 'AdobeARMservice', 'AdobeUpdateService'
    'gupdate', 'gupdatem', 'MozillaMaintenance'
    'Steam Client Service', 'EpicGamesUpdater', 'EpicOnlineServices'
    'CoworkVMService'
    # Windows sludge (safe on Manual - starts if something asks)
    'DiagTrack', 'dmwappushservice', 'DPS', 'PcaSvc'
    'WSearch', 'SysMain', 'Spooler', 'DoSvc'
    'MapsBroker', 'Fax', 'RemoteRegistry', 'RetailDemo', 'WMPNetworkSvc'
    'SharedAccess', 'PhoneSvc', 'TapiSrv', 'TabletInputService', 'WbioSrvc'
    'lfsvc', 'DusmSvc', 'TrkWks', 'WpcMonSvc', 'WalletService'
    'SEMgrSvc', 'icssvc', 'wisvc', 'AJRouter', 'AssignedAccessManagerSvc'
    'shpamsvc', 'SmsRouter', 'WMPNetworkSvc', 'diagnosticshub.standardcollector.service'
    'WerSvc', 'wercplsupport', 'axinstsv', 'NetTcpPortSharing'
    'RemoteAccess', 'SCardSvr', 'ScDeviceEnum', 'SCPolicySvc'
    'SensorDataService', 'SensrSvc', 'SensorService'
    'StiSvc', 'FrameServer', 'WiaRpc'
    'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc'
    'WSLService', 'WSAIFabricSvc'
    'NvTelemetryContainer', 'NvTelemetry'
    'DSAService', 'DSAUpdateService'
    # NIC sludge - Disabled, not Manual
    'Killer Analytics Service', 'Killer Network Service'
    'KNDBWM', 'SmartByte', 'SmartByteNetworkService'
)

$script:ServiceDisable = @(
    'Killer Analytics Service', 'Killer Network Service'
    'KNDBWM', 'SmartByte', 'SmartByteNetworkService'
)

$script:NeverTouch = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
@(
    'RpcSs', 'DcomLaunch', 'RpcEptMapper', 'PlugPlay', 'CryptSvc', 'KeyIso'
    'WinDefend', 'WdNisSvc', 'MDCoreSvc', 'mpssvc', 'BFE', 'SecurityHealthService'
    'wscsvc', 'Winmgmt', 'EventLog', 'Schedule', 'ProfSvc', 'UserManager', 'LSM'
    'SamSs', 'Power', 'Audiosrv', 'AudioEndpointBuilder', 'Dhcp', 'Dnscache'
    'nsi', 'NlaSvc', 'netprofm', 'WlanSvc', 'LanmanWorkstation', 'LanmanServer'
    'BrokerInfrastructure', 'CoreMessagingRegistrar', 'SystemEventsBroker'
    'SENS', 'EventSystem', 'StateRepository', 'AppXSvc', 'camsvc', 'FontCache'
    'Themes', 'TextInputManagementService', 'gpsvc', 'TrustedInstaller', 'msiserver'
    'WinHttpAutoProxySvc', 'wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'BITS'
    'VaultSvc', 'TokenBroker', 'LicenseManager', 'ClipSVC', 'sppsvc'
    'hidserv', 'HidIr', 'GameInputRedistService', 'GameInputSvc', 'GamingServices'
    'GamingServicesNet', 'ClickToRunSvc'
    'AMD Crash Defender Service', 'AMD External Events Utility', 'amd3dvcacheSvc'
    'RtkAudioUniversalService'
    'NVDisplay.ContainerLocalSystem', 'NvContainerLocalSystem'
    'EasyAntiCheat', 'EasyAntiCheatSys', 'BEService', 'vgc', 'vgk'
    'FACEIT', 'FaceItService', 'mhyprot2'
) | ForEach-Object { [void]$script:NeverTouch.Add($_) }

$script:StartupExact = @(
    'Steam', 'EpicGamesLauncher', 'RiotClient', 'Riot Vanguard'
    'WallpaperEngine', 'LGHUB', 'Docker Desktop'
    'AMDNoiseSuppression', 'SteelSeriesGG', 'Corsair iCUE5 Software'
    'MSIRegister', 'iCUE', 'Steam Client Bootstrapper'
    'Ubisoft Connect', 'EADM', 'Battle.net'
    'CCleaner Smart Cleaning', 'SunJavaUpdateSched', 'uTorrent'
    'Discord', 'Spotify', 'OneDrive', 'Microsoft Teams', 'Teams'
    'Skype', 'com.squirrel.Teams.Teams', 'Adobe GC Invoker Utility'
    'GoogleDriveFS', 'Dropbox', 'iTunesHelper', 'QuickTime Task'
    'CcProxy', 'ccleaner', 'Overwolf', 'GalaxyClient'
    'IAStorIcon', 'Razer Central', 'logioptionsplus', 'LGHUB'
    'com.squirrel.Discord.Discord', 'Spotify Web Helper'
    'OneDriveSetup', 'Microsoft.Todos', 'YourPhone'
)

$script:StartupPatterns = @(
    'Steam', 'EpicGames', 'Riot Client', 'RiotClient', 'vgtray'
    'wallpaper64', 'wallpaper32', 'lghub', 'iCUE', 'SteelSeries'
    'Docker Desktop', 'AMDNoiseSuppression', 'MSIRegister', 'Mystic'
    'ArmouryCrate', 'Armoury Crate', 'NZXT', 'Razer', 'Overwolf'
    'AdobeGCInvoker', 'ccleaner', 'utorrent'
    'MicrosoftEdgeAutoLaunch_', 'GoogleChromeAutoLaunch_'
    'GalaxyClient', 'UbisoftConnect', 'upc\.exe', 'EADesktop'
    'Battle\.net', 'Battle.net', 'spotify', 'Discord', 'Teams'
    'OneDrive', 'Skype', 'Dropbox', 'GoogleDrive', 'YourPhone'
    'CrossDevice', 'PhoneExperience', 'iTunesHelper', 'AppleMusic'
    'GeForce Experience', 'NVIDIA Share', 'nvsphelper', 'ShadowPlay'
    'AMDSoftware', 'AMDRSServ', 'AMDLink'
)

$script:StartupKeep = @(
    'SecurityHealth', 'RtkAudUService', 'WindowsDefender', 'Realtek HD Audio'
    'Avast', 'AVG', 'Norton', 'Bitdefender', 'Kaspersky', 'ESET', 'Malwarebytes'
    'CrowdStrike', 'Sentinel', 'Sophos', 'Webroot', 'Trend Micro'
)

# Scheduled tasks to disable if present (path + name).
$script:TaskExact = @(
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'PcaPatchDbTask' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'StartupAppTask' }
    @{ Path = '\Microsoft\Windows\Autochk\'; Name = 'Proxy' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'KernelCeipTask' }
    @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
    @{ Path = '\Microsoft\Windows\Feedback\Siuf\'; Name = 'DmClient' }
    @{ Path = '\Microsoft\Windows\Feedback\Siuf\'; Name = 'DmClientOnScenarioDownload' }
    @{ Path = '\Microsoft\Windows\Maps\'; Name = 'MapsToastTask' }
    @{ Path = '\Microsoft\Windows\Maps\'; Name = 'MapsUpdateTask' }
    @{ Path = '\Microsoft\Windows\Shell\'; Name = 'FamilySafetyMonitor' }
    @{ Path = '\Microsoft\Windows\Shell\'; Name = 'FamilySafetyRefreshTask' }
    @{ Path = '\Microsoft\Windows\Windows Error Reporting\'; Name = 'QueueReporting' }
    @{ Path = '\Microsoft\XblGameSave\'; Name = 'XblGameSaveTask' }
    @{ Path = '\Microsoft\Windows\CloudExperienceHost\'; Name = 'CreateObjectTask' }
    @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\'; Name = 'BootstrapUsageDataReporting' }
    @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\'; Name = 'UsageDataFlushing' }
    @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\'; Name = 'UsageDataReporting' }
    @{ Path = '\Microsoft\Windows\Power Efficiency Diagnostics\'; Name = 'AnalyzeSystem' }
    @{ Path = '\Microsoft\Windows\PI\'; Name = 'Sqm-Tasks' }
    @{ Path = '\Microsoft\Windows\NetTrace\'; Name = 'GatherNetworkInfo' }
    @{ Path = '\Microsoft\Office\'; Name = 'OfficeTelemetryAgentFallBack' }
    @{ Path = '\Microsoft\Office\'; Name = 'OfficeTelemetryAgentLogOn' }
    @{ Path = '\Microsoft\Office\'; Name = 'OfficeTelemetryAgentFallBack2016' }
    @{ Path = '\Microsoft\Office\'; Name = 'OfficeTelemetryAgentLogOn2016' }
)

$script:TaskNamePatterns = @(
    'GoogleUpdateTaskMachine', 'GoogleUpdateTaskUser'
    'Adobe Acrobat Update Task', 'Adobe Flash Player Updater'
    'CCleaner*', 'Overwolf*', 'User_Feed_Synchronization'
    'NvTmRep', 'NvTmMon', 'NvProfileUpdater'
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Head([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 68) -ForegroundColor DarkCyan
}
function Write-Ok([string]$Text) { Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-Skip([string]$Text) { Write-Host "  [SKIP] $Text" -ForegroundColor DarkGray }
function Write-WarnLine([string]$Text) { Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host "  [FAIL] $Text" -ForegroundColor Red }
function Write-Info([string]$Text) { Write-Host "  [..]   $Text" -ForegroundColor Gray }

function Add-Result {
    param([string]$Area, [string]$Item, [string]$Status, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ Area = $Area; Item = $Item; Status = $Status; Detail = $Detail })
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal $id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Admin {
    if (Test-Admin) { return }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) {
            if ($v) { $argList += "-$k" }
        }
        else {
            $argList += "-$k"
            $argList += "`"$v`""
        }
    }
    Write-Host 'Requesting Administrator...' -ForegroundColor Yellow
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit 0
}

function Test-IsLaptop {
    try {
        $types = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes)
        $laptop = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
        return [bool]($types | Where-Object { $laptop -contains [int]$_ })
    }
    catch { return $false }
}

function Get-ActivePowerGuid {
    $raw = powercfg /getactivescheme 2>&1 | Out-String
    if ($raw -match 'GUID:\s*([a-fA-F0-9-]+)') { return $Matches[1] }
    return $null
}

function Get-MachineInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -and $_.Name -notmatch 'Basic Render' })
    $gpuName = if ($gpus.Count -gt 0) { ($gpus | ForEach-Object { $_.Name }) -join ' + ' } else { 'unknown' }
    $script:RamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    [pscustomobject]@{
        Computer  = $env:COMPUTERNAME
        OS        = $os.Caption
        Version   = $os.Version
        RAM_GB    = $script:RamGB
        CPU       = $cpu.Name.Trim()
        GPU       = $gpuName
        Laptop    = $script:IsLaptop
        Running   = @(Get-Service | Where-Object Status -eq 'Running').Count
        Automatic = @(Get-Service | Where-Object { $_.StartType -eq 'Automatic' -or $_.StartType -eq 'AutomaticDelayedStart' }).Count
        TotalSvcs = @(Get-Service).Count
        PowerGuid = Get-ActivePowerGuid
    }
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    }
    catch { return $null }
}

function Convert-RegValueToJson($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [byte[]]) { return [Convert]::ToBase64String($Value) }
    return $Value
}

function Convert-JsonToRegValue($Stored, [string]$Type) {
    if ($Type -eq 'Binary') {
        if ($null -eq $Stored -or $Stored -eq '') { return $null }
        return [Convert]::FromBase64String([string]$Stored)
    }
    if ($Type -eq 'DWord') { return [int64]$Stored }
    return [string]$Stored
}

function Get-RunKeyMap([string]$Path) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { return $map }
    foreach ($p in $item.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        $map[$p.Name] = [string]$p.Value
    }
    return $map
}

# ---------------------------------------------------------------------------
# Registry plan
# ---------------------------------------------------------------------------
function Get-RegistryPlan {
    $items = @(
        @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AllowAutoGameMode'; Type = 'DWord'; Value = 1; Note = 'Game Mode on' }
        @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Type = 'DWord'; Value = 1; Note = 'Game Mode on' }
        @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'UseNexusForGameBarEnabled'; Type = 'DWord'; Value = 0; Note = 'Game Bar overlay off' }
        @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Type = 'DWord'; Value = 0; Note = 'Game DVR off' }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Type = 'DWord'; Value = 0; Note = 'Game Bar capture off' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name = 'AllowGameDVR'; Type = 'DWord'; Value = 0; Note = 'Game DVR policy off' }
        @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed'; Type = 'String'; Value = '0'; Note = 'Pointer precision off' }
        @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold1'; Type = 'String'; Value = '0'; Note = 'Pointer precision off' }
        @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold2'; Type = 'String'; Value = '0'; Note = 'Pointer precision off' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'MenuShowDelay'; Type = 'String'; Value = '0'; Note = 'Menu delay 0' }
        @{ Path = 'HKCU:\Control Panel\Desktop\WindowMetrics'; Name = 'MinAnimate'; Type = 'String'; Value = '0'; Note = 'Window animations off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Type = 'DWord'; Value = 3; Note = 'Visual effects custom' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'DragFullWindows'; Type = 'String'; Value = '1'; Note = 'Show window contents while dragging' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'FontSmoothing'; Type = 'String'; Value = '2'; Note = 'Keep font smoothing' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'UserPreferencesMask'; Type = 'Binary'; Value = [byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00); Note = 'Trim animations, keep fonts' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'HiberbootEnabled'; Type = 'DWord'; Value = 0; Note = 'Fast Startup off' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Type = 'DWord'; Value = 0; Note = 'Multimedia: games first' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Type = 'DWord'; Value = 0xffffffff; Note = 'Network throttling off' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority'; Type = 'DWord'; Value = 8; Note = 'Games GPU priority' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Type = 'DWord'; Value = 6; Note = 'Games CPU priority' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Type = 'String'; Value = 'High'; Note = 'Games scheduling' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Type = 'String'; Value = 'High'; Note = 'Games disk priority' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Type = 'DWord'; Value = 38; Note = 'Foreground boost (0x26)' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'LargeSystemCache'; Type = 'DWord'; Value = 0; Note = 'LargeSystemCache off (desktop)' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'ClearPageFileAtShutdown'; Type = 'DWord'; Value = 0; Note = 'Do not wipe pagefile on shutdown' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name = 'EnablePrefetcher'; Type = 'DWord'; Value = 0; Note = 'Prefetcher off (SSD)' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name = 'EnableSuperfetch'; Type = 'DWord'; Value = 0; Note = 'Superfetch off' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisableLastAccessUpdate'; Type = 'DWord'; Value = 1; Note = 'NTFS last-access stamps off' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control'; Name = 'WaitToKillServiceTimeout'; Type = 'String'; Value = '2000'; Note = 'Faster service stop on shutdown' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'WaitToKillAppTimeout'; Type = 'String'; Value = '2000'; Note = 'Faster app stop on shutdown' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'HungAppTimeout'; Type = 'String'; Value = '2000'; Note = 'Hung-app timeout 2s' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'StartupDelayInMSec'; Type = 'DWord'; Value = 0; Note = 'No startup delay' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Type = 'DWord'; Value = 1; Note = 'UWP background apps off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BackgroundAppGlobalToggle'; Type = 'DWord'; Value = 0; Note = 'Background search apps off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Type = 'DWord'; Value = 0; Note = 'Bing in Start off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'CortanaConsent'; Type = 'DWord'; Value = 0; Note = 'Cortana off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Type = 'DWord'; Value = 0; Note = 'Explorer ads off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Type = 'DWord'; Value = 0; Note = 'Widgets button off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Type = 'DWord'; Value = 0; Note = 'Copilot button off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Type = 'DWord'; Value = 0; Note = 'Suggested content off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Type = 'DWord'; Value = 0; Note = 'Suggested apps off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Type = 'DWord'; Value = 0; Note = 'Tips off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Type = 'DWord'; Value = 0; Note = 'Settings suggestions off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Type = 'DWord'; Value = 0; Note = 'Silent Store installs off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Type = 'DWord'; Value = 0; Note = 'Advertising ID off' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Type = 'DWord'; Value = 0; Note = 'Tailored experiences off' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Type = 'DWord'; Value = 1; Note = 'Consumer features off' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Type = 'DWord'; Value = 1; Note = 'Telemetry = basic (not 0)' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Type = 'DWord'; Value = 0; Note = 'Cortana policy off' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Copilot'; Name = 'TurnOffWindowsCopilot'; Type = 'DWord'; Value = 1; Note = 'Copilot policy off' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Type = 'DWord'; Value = 0; Note = 'News and interests off' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'; Name = 'EnableFeeds'; Type = 'DWord'; Value = 0; Note = 'Feeds off' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Type = 'DWord'; Value = 1; Note = 'Recall / AI analysis off' }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Type = 'DWord'; Value = 0; Note = 'Delivery Optimization HTTP only' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'; Name = 'ToastEnabled'; Type = 'DWord'; Value = 0; Note = 'Toast spam off' }
        @{ Path = 'HKCU:\Control Panel\Accessibility\StickyKeys'; Name = 'Flags'; Type = 'String'; Value = '506'; Note = 'Sticky Keys popup off' }
        @{ Path = 'HKCU:\Control Panel\Accessibility\Keyboard Response'; Name = 'Flags'; Type = 'String'; Value = '122'; Note = 'Filter Keys popup off' }
        @{ Path = 'HKCU:\Control Panel\Accessibility\ToggleKeys'; Name = 'Flags'; Type = 'String'; Value = '58'; Note = 'Toggle Keys popup off' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance'; Name = 'MaintenanceDisabled'; Type = 'DWord'; Value = 1; Note = 'Idle maintenance off' }
    )
    if (-not $NoHags) {
        $items += @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Type = 'DWord'; Value = 2; Note = 'HAGS on' }
    }
    if ($script:RamGB -ge 16) {
        $items += @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'DisablePagingExecutive'; Type = 'DWord'; Value = 1; Note = 'Keep kernel in RAM (16GB+)' }
    }
    return $items
}

# ---------------------------------------------------------------------------
# Plan: services / startup / tasks
# ---------------------------------------------------------------------------
function Get-TargetServiceNames {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($n in $script:ServiceExact) {
        if ($n -eq 'WSearch' -and $KeepSearch) { continue }
        if ($n -in @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc') -and $KeepXbox) { continue }
        if ($n -eq 'Spooler' -and $KeepPrinter) { continue }
        if ($n -eq 'WSLService' -and $KeepWSL) { continue }
        if ($n -in @('PhoneSvc', 'TapiSrv') -and $KeepPhone) { continue }
        if ($n -eq 'WbioSrvc' -and $script:IsLaptop) { continue }
        if ($n -eq 'TabletInputService' -and $script:IsLaptop) { continue }
        $names.Add($n)
    }
    return , $names
}

function Resolve-ServiceMatches {
    $wanted = Get-TargetServiceNames
    $all = @(Get-Service -ErrorAction SilentlyContinue)
    $hits = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pat in $wanted) {
        foreach ($s in @($all | Where-Object { $_.Name -like $pat })) {
            if ($script:NeverTouch.Contains($s.Name)) { continue }
            if ($seen.Add($s.Name)) { $hits.Add($s) }
        }
    }
    return , $hits
}

function Test-StartupKeep([string]$Name, [string]$Command) {
    foreach ($k in $script:StartupKeep) {
        if ($Name -like "*$k*" -or $Command -like "*$k*") { return $true }
    }
    if ($KeepLaunchers) {
        foreach ($k in @('Steam', 'Epic', 'Riot', 'Battle.net', 'Ubisoft', 'EADesktop', 'Xbox')) {
            if ($Name -like "*$k*" -or $Command -like "*$k*") { return $true }
        }
    }
    if ($KeepPhone) {
        foreach ($k in @('YourPhone', 'CrossDevice', 'PhoneExperience')) {
            if ($Name -like "*$k*" -or $Command -like "*$k*") { return $true }
        }
    }
    return $false
}

function Test-StartupMatch([string]$Name, [string]$Command) {
    if ($script:StartupExact -contains $Name) { return $true }
    foreach ($rx in $script:StartupPatterns) {
        if ($Name -match $rx) { return $true }
        if ($Command -and $Command -match $rx) { return $true }
    }
    return $false
}

function Get-StartupPlan {
    $roots = @(
        @{ Hive = 'HKCU'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
        @{ Hive = 'HKLM'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' }
        @{ Hive = 'HKLMWow'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
    )
    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($r in $roots) {
        $map = Get-RunKeyMap $r.Path
        foreach ($name in $map.Keys) {
            $cmd = $map[$name]
            if (Test-StartupKeep $name $cmd) { continue }
            if (Test-StartupMatch $name $cmd) {
                $plan.Add([pscustomobject]@{
                        Hive    = $r.Hive
                        Path    = $r.Path
                        Name    = $name
                        Command = $cmd
                    })
            }
        }
    }
    return , $plan
}

function Get-StartupFolderHits {
    $dirs = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup')
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup')
    )
    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -eq 'desktop.ini') { return }
            $hits.Add($_)
        }
    }
    return , $hits
}

function Get-TaskHits {
    $hits = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $script:TaskExact) {
        $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($task) {
            $key = $t.Path + $t.Name
            if ($seen.Add($key)) { $hits.Add($task) }
        }
    }
    $all = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    foreach ($pat in $script:TaskNamePatterns) {
        foreach ($task in @($all | Where-Object { $_.TaskName -like $pat })) {
            $key = $task.TaskPath + $task.TaskName
            if ($seen.Add($key)) { $hits.Add($task) }
        }
    }
    return , $hits
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------
function Save-Backup {
    param($Info, $Services, $RunKeys, $RegistryBefore, $Tasks, $Nagle, $StartupFiles)
    Ensure-Dir $BackupRoot
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $file = Join-Path $BackupRoot ("backup-{0}-{1}.json" -f $stamp, $env:COMPUTERNAME)
    $payload = [ordered]@{
        schema       = 2
        created      = (Get-Date).ToString('o')
        computer     = $env:COMPUTERNAME
        info         = $Info
        services     = @($Services)
        runKeys      = $RunKeys
        registry     = @($RegistryBefore)
        tasks        = @($Tasks)
        nagle        = @($Nagle)
        startupFiles = @($StartupFiles)
    }
    ($payload | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $file -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $BackupRoot 'latest.txt') -Value $file -Encoding UTF8
    return $file
}

function Get-LatestBackupPath {
    $ptr = Join-Path $BackupRoot 'latest.txt'
    if (Test-Path -LiteralPath $ptr) {
        $p = (Get-Content -LiteralPath $ptr -Raw).Trim()
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $latest = Get-ChildItem -LiteralPath $BackupRoot -Filter 'backup-*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

function Get-ServiceSnapshot {
    Get-Service | ForEach-Object {
        [pscustomobject]@{
            Name      = $_.Name
            Display   = $_.DisplayName
            Status    = [string]$_.Status
            StartType = [string]$_.StartType
        }
    }
}

function Get-NagleSnapshot {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path $base)) { return , $rows }
    Get-ChildItem $base | ForEach-Object {
        $p = $_.PSPath
        $ip = Get-RegValue $p 'DhcpIPAddress'
        if (-not $ip) { $ip = Get-RegValue $p 'IPAddress' }
        if (-not $ip) { return }
        $rows.Add([pscustomobject]@{
                Path            = $p
                Id              = $_.PSChildName
                Ip              = [string]$ip
                TcpAckFrequency = (Get-RegValue $p 'TcpAckFrequency')
                TCPNoDelay      = (Get-RegValue $p 'TCPNoDelay')
                HadAck          = ($null -ne (Get-RegValue $p 'TcpAckFrequency'))
                HadDelay        = ($null -ne (Get-RegValue $p 'TCPNoDelay'))
            })
    }
    return , $rows
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
function Set-ServiceParked {
    param($Service)
    $name = $Service.Name
    $kill = $false
    foreach ($d in $script:ServiceDisable) {
        if ($name -like $d) { $kill = $true; break }
    }
    $want = if ($kill) { 'Disabled' } else { 'Manual' }
    $alreadyOk = ($want -eq 'Manual' -and ($Service.StartType -eq 'Manual' -or $Service.StartType -eq 'Disabled')) -or
    ($want -eq 'Disabled' -and $Service.StartType -eq 'Disabled')
    try {
        if ($alreadyOk) {
            Add-Result 'Service' $name 'Already parked' ("{0} ({1})" -f $Service.StartType, $Service.DisplayName)
            Write-Skip ("{0}  already {1}" -f $name, $Service.StartType)
            return
        }
        Set-Service -Name $name -StartupType $want -ErrorAction Stop
        if ($Service.Status -eq 'Running') {
            Stop-Service -Name $name -Force -ErrorAction Stop
        }
        Add-Result 'Service' $name $want $Service.DisplayName
        Write-Ok ("{0}  -> {1}  ({2})" -f $name, $want, $Service.DisplayName)
    }
    catch {
        $scWant = if ($kill) { 'disabled' } else { 'demand' }
        $null = & sc.exe config $name start= $scWant 2>&1
        Start-Sleep -Milliseconds 250
        try { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue } catch {}
        $now = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($now -and [string]$now.StartType -eq $want) {
            Add-Result 'Service' $name "$want (sc)" $Service.DisplayName
            Write-Ok ("{0}  -> {1} via sc.exe" -f $name, $want)
        }
        else {
            Add-Result 'Service' $name 'FAIL' $_.Exception.Message
            Write-Fail ("{0}  {1}" -f $name, $_.Exception.Message)
        }
    }
}

function Disable-StartupApproved {
    param([string]$ApprovedRoot, [string]$Name)
    if (-not (Test-Path -LiteralPath $ApprovedRoot)) { return }
    $disabled = [byte[]](0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
    try {
        $props = Get-ItemProperty -LiteralPath $ApprovedRoot -ErrorAction SilentlyContinue
        if ($props -and $props.PSObject.Properties.Name -contains $Name) {
            Set-ItemProperty -LiteralPath $ApprovedRoot -Name $Name -Value $disabled -Type Binary -Force
        }
    }
    catch { }
}

function Remove-StartupEntry {
    param($Entry)
    try {
        Remove-ItemProperty -LiteralPath $Entry.Path -Name $Entry.Name -Force -ErrorAction Stop
        $approved = if ($Entry.Hive -eq 'HKCU') {
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        }
        else {
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        }
        Disable-StartupApproved $approved $Entry.Name
        Add-Result 'Startup' $Entry.Name 'Removed' $Entry.Hive
        Write-Ok ("startup  {0}\{1}" -f $Entry.Hive, $Entry.Name)
    }
    catch {
        Add-Result 'Startup' $Entry.Name 'FAIL' $_.Exception.Message
        Write-Fail ("startup  {0}: {1}" -f $Entry.Name, $_.Exception.Message)
    }
}

function Disable-StartupFolderItem {
    param($File)
    try {
        $bak = $File.FullName + '.bak'
        if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force }
        Rename-Item -LiteralPath $File.FullName -NewName ($File.Name + '.bak') -Force
        Add-Result 'StartupFolder' $File.Name 'Renamed .bak' $File.DirectoryName
        Write-Ok ("startup folder  {0}" -f $File.Name)
    }
    catch {
        Add-Result 'StartupFolder' $File.Name 'FAIL' $_.Exception.Message
        Write-Fail ("startup folder  {0}: {1}" -f $File.Name, $_.Exception.Message)
    }
}

function Disable-TaskHit {
    param($Task)
    if ($Task.State -eq 'Disabled') {
        Write-Skip ("task  {0}{1}" -f $Task.TaskPath, $Task.TaskName)
        Add-Result 'Task' $Task.TaskName 'Already disabled' $Task.TaskPath
        return
    }
    try {
        Disable-ScheduledTask -InputObject $Task -ErrorAction Stop | Out-Null
        Add-Result 'Task' $Task.TaskName 'Disabled' $Task.TaskPath
        Write-Ok ("task  {0}{1}" -f $Task.TaskPath, $Task.TaskName)
    }
    catch {
        Add-Result 'Task' $Task.TaskName 'FAIL' $_.Exception.Message
        Write-Fail ("task  {0}: {1}" -f $Task.TaskName, $_.Exception.Message)
    }
}

function Set-RegDesired {
    param($Item)
    try {
        if (-not (Test-Path -LiteralPath $Item.Path)) {
            New-Item -Path $Item.Path -Force | Out-Null
        }
        $current = Get-RegValue $Item.Path $Item.Name
        $same = $false
        if ($Item.Type -eq 'Binary' -and $current -is [byte[]] -and $Item.Value -is [byte[]]) {
            $same = [Convert]::ToBase64String($current) -eq [Convert]::ToBase64String($Item.Value)
        }
        elseif ($null -ne $current) {
            $same = [string]$current -eq [string]$Item.Value
        }
        if ($same) {
            Add-Result 'Registry' $Item.Note 'Already set' $Item.Name
            Write-Skip $Item.Note
            return
        }
        if ($Item.Type -eq 'Binary') {
            Set-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -Value $Item.Value -Type Binary -Force
        }
        elseif ($Item.Type -eq 'DWord') {
            New-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -Value $Item.Value -PropertyType DWord -Force | Out-Null
        }
        else {
            New-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -Value $Item.Value -PropertyType String -Force | Out-Null
        }
        Add-Result 'Registry' $Item.Note 'Set' $Item.Name
        Write-Ok $Item.Note
    }
    catch {
        Add-Result 'Registry' $Item.Note 'FAIL' $_.Exception.Message
        Write-Fail ("{0}: {1}" -f $Item.Note, $_.Exception.Message)
    }
}

function Enable-GamePowerPlan {
    $ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $highPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    try {
        $list = powercfg -list 2>&1 | Out-String
        if ($script:IsLaptop) {
            powercfg -setactive $highPerf 2>&1 | Out-Null
            Add-Result 'Power' 'High performance' 'Set' 'laptop'
            Write-Ok 'Power plan: High performance (laptop)'
        }
        else {
            if ($list -notmatch $ultimate) {
                powercfg -duplicatescheme $ultimate 2>&1 | Out-Null
            }
            $list2 = powercfg -list 2>&1 | Out-String
            $guid = $null
            foreach ($line in ($list2 -split "`r?`n")) {
                if ($line -match 'Power Scheme GUID:\s*([a-fA-F0-9-]+)\s+\(Ultimate Performance\)') {
                    $guid = $Matches[1]
                }
            }
            if (-not $guid) { $guid = $ultimate }
            powercfg -setactive $guid 2>&1 | Out-Null
            Add-Result 'Power' 'Ultimate Performance' 'Set' $guid
            Write-Ok 'Power plan: Ultimate Performance'
        }

        powercfg -setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 0 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
        # Core parking off (AC)
        powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMAXCORES 100 2>$null | Out-Null
        powercfg -setactive SCHEME_CURRENT 2>$null | Out-Null
        Add-Result 'Power' 'AC: CPU 100%, no parking, USB/PCIe/disk idle off' 'Set' ''
        Write-Ok 'AC power: CPU 100%, core parking off, USB/PCIe/disk idle off'

        if (-not $script:IsLaptop) {
            powercfg -h off 2>$null | Out-Null
            Add-Result 'Power' 'Hibernate off' 'Set' 'desktop'
            Write-Ok 'Hibernate off (desktop)'
        }
    }
    catch {
        Add-Result 'Power' 'Power plan' 'FAIL' $_.Exception.Message
        Write-Fail $_.Exception.Message
    }
}

function Disable-NagleOnAdapters {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    if (-not (Test-Path $base)) { return }
    Get-ChildItem $base | ForEach-Object {
        $p = $_.PSPath
        $ip = Get-RegValue $p 'DhcpIPAddress'
        if (-not $ip) { $ip = Get-RegValue $p 'IPAddress' }
        if (-not $ip) { return }
        try {
            New-ItemProperty -LiteralPath $p -Name 'TcpAckFrequency' -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -LiteralPath $p -Name 'TCPNoDelay' -Value 1 -PropertyType DWord -Force | Out-Null
            Add-Result 'Network' "Nagle off $ip" 'Set' $_.PSChildName
            Write-Ok ("Nagle off on {0}" -f $ip)
        }
        catch {
            Write-Fail ("Nagle {0}: {1}" -f $ip, $_.Exception.Message)
        }
    }
}

function New-SystemRestoreBestEffort {
    if ($NoRestorePoint) { return }
    Write-Info 'Creating a System Restore point (best effort)...'
    try {
        Checkpoint-Computer -Description 'WinOptimize' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Ok 'System Restore point created'
        Add-Result 'Backup' 'Restore point' 'Created' ''
    }
    catch {
        Write-WarnLine ("Restore point skipped: {0}" -f $_.Exception.Message)
        Add-Result 'Backup' 'Restore point' 'Skipped' $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------
function Restore-FromBackup {
    param([string]$File)
    Write-Head "RESTORE  $File"
    $data = (Get-Content -LiteralPath $File -Raw -Encoding UTF8) | ConvertFrom-Json

    Write-Info 'Services...'
    $current = Resolve-ServiceMatches
    $snapByName = @{}
    foreach ($s in @($data.services)) { $snapByName[$s.Name] = $s }
    foreach ($svc in $current) {
        $old = $snapByName[$svc.Name]
        if (-not $old) { continue }
        $want = $old.StartType
        if ($want -eq 'AutomaticDelayedStart') { $want = 'Automatic' }
        if (-not $want) { continue }
        try {
            Set-Service -Name $svc.Name -StartupType $want -ErrorAction Stop
            if ($old.Status -eq 'Running') { Start-Service -Name $svc.Name -ErrorAction SilentlyContinue }
            Write-Ok ("{0}  -> {1}" -f $svc.Name, $want)
            Add-Result 'Service' $svc.Name 'Restored' $want
        }
        catch {
            Write-Fail ("{0}: {1}" -f $svc.Name, $_.Exception.Message)
        }
    }

    Write-Info 'Startup Run keys...'
    if ($data.runKeys) {
        $hives = @{
            HKCU    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
            HKLM    = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
            HKLMWow = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        }
        foreach ($hive in $hives.Keys) {
            $path = $hives[$hive]
            $bag = $data.runKeys.$hive
            if (-not $bag) { continue }
            foreach ($prop in $bag.PSObject.Properties) {
                if ($prop.Name -like 'PS*') { continue }
                try {
                    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                    New-ItemProperty -LiteralPath $path -Name $prop.Name -Value $prop.Value -PropertyType String -Force | Out-Null
                    Write-Ok ("startup restore  {0}\{1}" -f $hive, $prop.Name)
                }
                catch {
                    Write-Fail ("startup {0}: {1}" -f $prop.Name, $_.Exception.Message)
                }
            }
        }
    }

    Write-Info 'Startup folder...'
    foreach ($sf in @($data.startupFiles)) {
        if (-not $sf.FullName) { continue }
        $bak = $sf.FullName + '.bak'
        if ((Test-Path -LiteralPath $bak) -and -not (Test-Path -LiteralPath $sf.FullName)) {
            try {
                Rename-Item -LiteralPath $bak -NewName $sf.Name -Force
                Write-Ok ("startup folder restore  {0}" -f $sf.Name)
            }
            catch { Write-Fail $_.Exception.Message }
        }
    }

    Write-Info 'Scheduled tasks...'
    foreach ($t in @($data.tasks)) {
        if (-not $t.TaskName) { continue }
        if ($t.Enabled -eq $false) { continue }
        try {
            Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
            Write-Ok ("task restore  {0}{1}" -f $t.TaskPath, $t.TaskName)
        }
        catch { Write-Fail ("task {0}: {1}" -f $t.TaskName, $_.Exception.Message) }
    }

    Write-Info 'Registry...'
    foreach ($r in @($data.registry)) {
        try {
            if (-not $r.Path -or -not $r.Name) { continue }
            if (-not (Test-Path -LiteralPath $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
            $val = Convert-JsonToRegValue $r.Value $r.Type
            if ($null -eq $val -and $r.HadValue -eq $false) {
                Remove-ItemProperty -LiteralPath $r.Path -Name $r.Name -Force -ErrorAction SilentlyContinue
                continue
            }
            if ($r.Type -eq 'Binary') {
                Set-ItemProperty -LiteralPath $r.Path -Name $r.Name -Value $val -Type Binary -Force
            }
            elseif ($r.Type -eq 'DWord') {
                New-ItemProperty -LiteralPath $r.Path -Name $r.Name -Value $val -PropertyType DWord -Force | Out-Null
            }
            else {
                New-ItemProperty -LiteralPath $r.Path -Name $r.Name -Value $val -PropertyType String -Force | Out-Null
            }
            Write-Ok ("reg  {0}" -f $r.Note)
        }
        catch { Write-Fail ("reg {0}: {1}" -f $r.Name, $_.Exception.Message) }
    }

    Write-Info 'Nagle...'
    foreach ($n in @($data.nagle)) {
        if (-not $n.Path -or -not (Test-Path -LiteralPath $n.Path)) { continue }
        try {
            if ($n.HadAck) {
                New-ItemProperty -LiteralPath $n.Path -Name 'TcpAckFrequency' -Value $n.TcpAckFrequency -PropertyType DWord -Force | Out-Null
            }
            else {
                Remove-ItemProperty -LiteralPath $n.Path -Name 'TcpAckFrequency' -Force -ErrorAction SilentlyContinue
            }
            if ($n.HadDelay) {
                New-ItemProperty -LiteralPath $n.Path -Name 'TCPNoDelay' -Value $n.TCPNoDelay -PropertyType DWord -Force | Out-Null
            }
            else {
                Remove-ItemProperty -LiteralPath $n.Path -Name 'TCPNoDelay' -Force -ErrorAction SilentlyContinue
            }
        }
        catch { }
    }

    if ($data.info -and $data.info.PSObject.Properties.Name -contains 'PowerGuid' -and $data.info.PowerGuid) {
        try { powercfg -setactive $data.info.PowerGuid 2>$null | Out-Null } catch {}
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$script:IsLaptop = Test-IsLaptop
if ($Action -in @('Apply', 'Restore')) { Request-Admin }
Ensure-Dir $BackupRoot
$info = Get-MachineInfo

Write-Head 'Windows Optimize'
Write-Host ("  PC        {0}" -f $info.Computer)
Write-Host ("  OS        {0}  ({1})" -f $info.OS, $info.Version)
Write-Host ("  CPU       {0}" -f $info.CPU)
Write-Host ("  GPU       {0}" -f $info.GPU)
Write-Host ("  RAM       {0} GB" -f $info.RAM_GB)
Write-Host ("  Chassis   {0}" -f $(if ($info.Laptop) { 'laptop' } else { 'desktop' }))
Write-Host ("  Services  {0} running / {1} automatic / {2} total" -f $info.Running, $info.Automatic, $info.TotalSvcs)
Write-Host ("  Action    {0}" -f $Action)
Write-Host ("  Backups   {0}" -f $BackupRoot)

if ($Action -eq 'Audit') {
    Write-Head 'RUNNING third-party / interesting services'
    Get-Service | Where-Object {
        $_.Status -eq 'Running' -and (
            $_.Name -match 'AMD|Corsair|Steel|LGHUB|MSI|Mystic|Epic|Docker|Riot|Steam|Samsung|ss_|Google|Cowork|Light|Realtek|WSL|Xbox|Razer|NZXT|Armoury|Nahimic|Overwolf|Adobe|Killer|SmartByte|DiagTrack|SysMain|WSearch' -or
            $_.DisplayName -match 'AMD|Corsair|Steel|Logitech|MSI|Epic|Docker|Riot|Steam|Samsung|Google Play|Xbox|Razer|NZXT|Armoury|Nahimic|Overwolf|Killer|SmartByte'
        )
    } | Sort-Object DisplayName | Format-Table Name, DisplayName, StartType -AutoSize

    Write-Head 'STARTUP RUN KEYS'
    foreach ($p in @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )) {
        Write-Host "  $p" -ForegroundColor Yellow
        $map = Get-RunKeyMap $p
        if ($map.Count -eq 0) { Write-Host '    (empty)' -ForegroundColor DarkGray; continue }
        foreach ($k in $map.Keys) {
            Write-Host ("    {0}" -f $k)
            Write-Host ("      {0}" -f $map[$k]) -ForegroundColor DarkGray
        }
    }
    Write-Head 'Done (audit only - nothing changed)'
    exit 0
}

if ($Action -eq 'Restore') {
    $bak = Get-LatestBackupPath
    if (-not $bak) { Write-Fail "No backup found in $BackupRoot"; exit 1 }
    if (-not $Yes) {
        Write-Host ''
        Write-Host "Restore from:`n  $bak" -ForegroundColor Yellow
        $ans = Read-Host 'Type Y to restore'
        if ($ans -notin @('Y', 'y')) { Write-Host 'Cancelled.'; exit 0 }
    }
    Restore-FromBackup $bak
    Write-Head 'Restore finished - reboot to settle leftover processes'
    $script:Results | Format-Table -AutoSize
    exit 0
}

$svcHits = Resolve-ServiceMatches
$startHits = Get-StartupPlan
$folderHits = Get-StartupFolderHits
$taskHits = Get-TaskHits
$regPlan = Get-RegistryPlan

$regBefore = @()
foreach ($r in $regPlan) {
    $cur = Get-RegValue $r.Path $r.Name
    $regBefore += [pscustomobject]@{
        Path     = $r.Path
        Name     = $r.Name
        Type     = $r.Type
        Note     = $r.Note
        Value    = (Convert-RegValueToJson $cur)
        HadValue = ($null -ne $cur)
    }
}

$willChange = @($svcHits | Where-Object { $_.StartType -eq 'Automatic' -or $_.StartType -eq 'AutomaticDelayedStart' })
$parked = @($svcHits | Where-Object { $_.StartType -ne 'Automatic' -and $_.StartType -ne 'AutomaticDelayedStart' })
$tasksLive = @($taskHits | Where-Object { $_.State -ne 'Disabled' })

Write-Head 'PLAN - services'
if ($willChange.Count -gt 0) {
    Write-Host '  Will park (Manual, or Disabled for Killer/SmartByte):' -ForegroundColor Yellow
    $willChange | Sort-Object DisplayName | Format-Table Name, DisplayName, Status, StartType -AutoSize
}
else { Write-Skip 'Nothing left on Automatic in the known list' }
if ($parked.Count -gt 0) {
    Write-Host ("  Already parked ({0}) - left alone" -f $parked.Count) -ForegroundColor DarkGray
}

Write-Head 'PLAN - startup'
if ($startHits.Count -eq 0) { Write-Skip 'No matching Run-key sludge' }
else { $startHits | Format-Table Hive, Name, Command -AutoSize -Wrap }
if ($folderHits.Count -gt 0) {
    Write-Host '  Startup folder shortcuts that will be renamed .bak:' -ForegroundColor Yellow
    $folderHits | ForEach-Object { Write-Host ("    {0}" -f $_.FullName) }
}

Write-Head 'PLAN - scheduled tasks'
if ($tasksLive.Count -eq 0) { Write-Skip 'No matching idle/telemetry tasks left enabled' }
else { $tasksLive | Format-Table TaskPath, TaskName, State -AutoSize }

Write-Head 'PLAN - Windows / latency / power'
Write-Host '  Game Mode ON, Game DVR / overlay OFF'
if (-not $NoHags) { Write-Host '  Hardware-accelerated GPU scheduling ON' }
Write-Host '  Pointer precision OFF, animations OFF, menu delay 0'
Write-Host '  Fast Startup OFF, UWP background apps OFF, widgets / Copilot / feeds OFF'
Write-Host '  Telemetry basic (not off), consumer features OFF, Recall OFF'
Write-Host '  Prefetch/Superfetch OFF, NTFS last-access OFF, startup delay 0'
Write-Host '  Multimedia scheduler: games High, network throttle OFF, Nagle OFF'
if ($script:IsLaptop) { Write-Host '  Power: High performance (laptop)' } else { Write-Host '  Power: Ultimate Performance + hibernate off (desktop)' }
Write-Host '  AC: CPU 100%, core parking off, USB/PCIe/disk idle off'
Write-Host ''
Write-Host '  NEVER TOUCHED: Defender, Firewall, Windows Update, audio, Wi-Fi,' -ForegroundColor DarkGray
Write-Host '  core OS, GPU crash/events, Office Click-to-Run, anti-cheat, Gaming Services' -ForegroundColor DarkGray

if ($Action -eq 'Preview') {
    Write-Head 'Preview only - nothing was written'
    exit 0
}

if (-not $Yes) {
    Write-Host ''
    $ans = Read-Host 'Apply this plan?  Y / N'
    if ($ans -notin @('Y', 'y')) { Write-Host 'Cancelled.'; exit 0 }
}

$runKeys = @{
    HKCU    = Get-RunKeyMap 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    HKLM    = Get-RunKeyMap 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    HKLMWow = Get-RunKeyMap 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
}
$taskSnap = @($taskHits | ForEach-Object {
        [pscustomobject]@{
            TaskPath = $_.TaskPath
            TaskName = $_.TaskName
            Enabled  = ($_.State -ne 'Disabled')
        }
    })
$folderSnap = @($folderHits | ForEach-Object {
        [pscustomobject]@{ FullName = $_.FullName; Name = $_.Name }
    })
$nagleSnap = Get-NagleSnapshot
$svcSnap = Get-ServiceSnapshot
$backupFile = Save-Backup -Info $info -Services $svcSnap -RunKeys $runKeys -RegistryBefore $regBefore -Tasks $taskSnap -Nagle $nagleSnap -StartupFiles $folderSnap
Write-Ok "Backup written: $backupFile"
New-SystemRestoreBestEffort

Write-Head 'APPLY - services'
foreach ($s in $svcHits) { Set-ServiceParked $s }

Write-Head 'APPLY - startup'
foreach ($e in $startHits) { Remove-StartupEntry $e }
foreach ($f in $folderHits) { Disable-StartupFolderItem $f }

Write-Head 'APPLY - scheduled tasks'
foreach ($t in $taskHits) { Disable-TaskHit $t }

Write-Head 'APPLY - Windows / latency / power'
foreach ($r in $regPlan) { Set-RegDesired $r }
Enable-GamePowerPlan
Disable-NagleOnAdapters

$after = Get-Service
$runN = @($after | Where-Object Status -eq 'Running').Count
$autoN = @($after | Where-Object { $_.StartType -eq 'Automatic' -or $_.StartType -eq 'AutomaticDelayedStart' }).Count

Write-Head 'DONE'
Write-Host ("  Services now: {0} running / {1} automatic   (was {2} / {3})" -f $runN, $autoN, $info.Running, $info.Automatic)
Write-Host ("  Backup:       {0}" -f $backupFile)
Write-Host ''
Write-Host '  Reboot once. Launchers / RGB / WSL / printer start when you open them.' -ForegroundColor Gray
Write-Host '  Undo:  RESTORE.bat   or   .\Optimize.ps1 -Action Restore' -ForegroundColor Gray
Write-Host ''

$failN = @($script:Results | Where-Object Status -eq 'FAIL').Count
if ($failN -gt 0) {
    Write-WarnLine "$failN item(s) failed (often app-protected services). Listed below."
    $script:Results | Where-Object Status -eq 'FAIL' | Format-Table -AutoSize
}

exit 0
