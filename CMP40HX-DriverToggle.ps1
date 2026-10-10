#requires -version 5.1

param(
    [switch]$CheckOnly,
    [string]$ValidateGameInf = '',
    [switch]$Simulation,
    [ValidateSet('Work', 'Game')][string]$SimulationStartProfile = 'Work',
    [switch]$SelfTest,
    [string]$ScanFolder = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:HardwareId = 'PCI\VEN_10DE&DEV_1F0B'
# Chỉ dùng model mô phỏng cho self-test. Chế độ thật KHÔNG tự ép model khác.
$script:GameModel = if ($Simulation) { 'NVIDIA 40HX SIMULATION MODEL' } else { '' }
$script:Version = '1.3.3-public' 
$script:AppDirectory = Split-Path -Parent $PSCommandPath
$script:Simulation = [bool]$Simulation
$script:SimulationProfile = $SimulationStartProfile
$script:FixtureDirectory = Join-Path $script:AppDirectory 'simulation-fixtures'
$script:LauncherPath = Join-Path $script:AppDirectory 'Chay-CMP40HX-DriverToggle.vbs'
$script:DesktopShortcutName = 'CMP40HX Driver Toggle.lnk'
$script:StartMenuShortcutName = 'CMP40HX Driver Toggle.lnk'
$script:ConfigPath = Join-Path $script:AppDirectory $(if ($script:Simulation) { 'cmp40hx-profiles.simulation.json' } else { 'cmp40hx-profiles.json' })
$script:LogPath = Join-Path $script:AppDirectory $(if ($script:Simulation) { 'cmp40hx-simulation.log' } else { 'cmp40hx-switch.log' })

function Write-AppLog {
    param([string]$Message)

    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
}

function Update-DesktopShortcut {
    param(
        [ValidateSet('Work', 'Game')][string]$Profile,
        [switch]$CreateIfMissing
    )
    if ($script:Simulation) { return }
    if (-not (Test-Path -LiteralPath $script:LauncherPath -PathType Leaf)) {
        throw "Không tìm thấy launcher: $($script:LauncherPath)"
    }
    $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    $programsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
    if (-not $desktopPath -or -not $programsPath) { return }
    $shortcutPaths = @(
        (Join-Path $desktopPath $script:DesktopShortcutName),
        (Join-Path $programsPath $script:StartMenuShortcutName)
    )
    if (-not $CreateIfMissing -and -not ($shortcutPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) { return }
    $shell = New-Object -ComObject WScript.Shell
    try {
        foreach ($shortcutPath in $shortcutPaths) {
            $shortcut = $null
            try {
                $shortcut = $shell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
                $shortcut.Arguments = '"{0}"' -f $script:LauncherPath
                $shortcut.WorkingDirectory = $script:AppDirectory
                $shortcut.Description = if ($Profile -eq 'Game') { 'CMP 40HX - chế độ chơi game' } else { 'CMP 40HX - chế độ làm việc' }
                $shortcut.Save()
            }
            finally {
                if ($shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
            }
        }
    }
    finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    Write-AppLog "Đã cập nhật shortcut Desktop và Start Menu: $Profile"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedCopy {
    $arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath.Replace('"', '\"')
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments | Out-Null
}

function Get-DriverStorePackages {
    if ($script:Simulation) {
        return @(
            [pscustomobject]@{
                PublishedName = 'oem-sim-work.inf'
                OriginalName  = 'nvaci-simulation.inf'
                Provider      = 'NVIDIA (simulation)'
                Version       = '03/23/2026 32.0.15.9602'
                Signer        = 'SIMULATION - no hardware access'
            },
            [pscustomobject]@{
                PublishedName = 'oem-sim-game.inf'
                OriginalName  = 'nv_dispi-simulation.inf'
                Provider      = 'NVIDIA (simulation)'
                Version       = '05/15/2020 26.21.14.4614'
                Signer        = 'SIMULATION - no hardware access'
            }
        )
    }

    $raw = (& pnputil.exe /enum-drivers 2>&1 | Out-String)
    $blocks = $raw -split '(?:\r?\n){2,}'
    $results = @()

    foreach ($block in $blocks) {
        if ($block -notmatch '(?im)^Published Name:\s*(oem\d+\.inf)\s*$') {
            continue
        }

        $publishedName = $Matches[1]
        $originalName = if ($block -match '(?im)^Original Name:\s*(.+?)\s*$') { $Matches[1].Trim() } else { '' }
        $provider = if ($block -match '(?im)^Provider Name:\s*(.+?)\s*$') { $Matches[1].Trim() } else { '' }
        $version = if ($block -match '(?im)^Driver Version:\s*(.+?)\s*$') { $Matches[1].Trim() } else { '' }
        $signer = if ($block -match '(?im)^Signer Name:\s*(.+?)\s*$') { $Matches[1].Trim() } else { '' }

        $results += [pscustomobject]@{
            PublishedName = $publishedName
            OriginalName  = $originalName
            Provider      = $provider
            Version       = $version
            Signer        = $signer
        }
    }

    return $results
}

function Get-CmpDeviceInfo {
    if ($script:Simulation) {
        $isGame = $script:SimulationProfile -eq 'Game'
        return [pscustomobject]@{
            InstanceId    = 'PCI\VEN_10DE&DEV_1F0B&SUBSYS_SIMULATION'
            Description   = if ($isGame) { $script:GameModel } else { 'NVIDIA CMP 40HX' }
            Status        = 'Started (simulation)'
            PublishedName = if ($isGame) { 'oem-sim-game.inf' } else { 'oem-sim-work.inf' }
            OriginalName  = if ($isGame) { 'nv_dispi-simulation.inf' } else { 'nvaci-simulation.inf' }
            Version       = if ($isGame) { '05/15/2020 26.21.14.4614' } else { '03/23/2026 32.0.15.9602' }
            Signer        = 'SIMULATION - no hardware access'
        }
    }

    $raw = (& pnputil.exe /enum-devices /class Display /drivers 2>&1 | Out-String)
    $blocks = [regex]::Split($raw, '(?im)(?=^Instance ID:\s*)')
    $deviceBlock = $blocks | Where-Object { $_ -match [regex]::Escape($script:HardwareId) } | Select-Object -First 1

    if (-not $deviceBlock) {
        throw "Không tìm thấy CMP 40HX có hardware ID $($script:HardwareId)."
    }

    $instanceId = if ($deviceBlock -match '(?im)^Instance ID:\s*(.+?)\s*$') { $Matches[1].Trim() } else { '' }
    $description = if ($deviceBlock -match '(?im)^Device Description:\s*(.+?)\s*$') { $Matches[1].Trim() } else { 'CMP 40HX' }
    $status = if ($deviceBlock -match '(?im)^Status:\s*(.+?)\s*$') { $Matches[1].Trim() } else { 'Unknown' }
    $publishedName = if ($deviceBlock -match '(?im)^Driver Name:\s*(oem\d+\.inf)\s*$') { $Matches[1].Trim() } else { '' }
    $package = Get-DriverStorePackages | Where-Object { $_.PublishedName -ieq $publishedName } | Select-Object -First 1

    return [pscustomobject]@{
        InstanceId    = $instanceId
        Description   = $description
        Status        = $status
        PublishedName = $publishedName
        OriginalName  = if ($package) { $package.OriginalName } else { '' }
        Version       = if ($package) { $package.Version } else { '' }
        Signer        = if ($package) { $package.Signer } else { '' }
    }
}

function Get-DriverStoreInfPath {
    param([Parameter(Mandatory = $true)][string]$PublishedName)

    if ($script:Simulation) {
        $fixtureName = if ($PublishedName -ieq 'oem-sim-game.inf') { 'game-driver.inf' } else { 'work-driver.inf' }
        return Join-Path (Join-Path $script:FixtureDirectory $(if ($PublishedName -ieq 'oem-sim-game.inf') { 'game' } else { 'work' })) $fixtureName
    }

    # Windows keeps each published OEM INF here. Reading it directly avoids the
    # very slow Get-WindowsDriver/DISM scan that can make startup appear frozen.
    $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $publishedInf = Join-Path (Join-Path $windowsDirectory 'INF') $PublishedName
    if (Test-Path -LiteralPath $publishedInf -PathType Leaf) {
        return $publishedInf
    }

    Write-AppLog "Không tìm thấy INF hiện tại tại $publishedInf"
    return ''
}

function Get-InfVersion {
    param([string]$InfPath)

    if (-not $InfPath -or -not (Test-Path -LiteralPath $InfPath)) {
        return ''
    }

    $line = Select-String -LiteralPath $InfPath -Pattern '^\s*DriverVer\s*=\s*(.+)$' -CaseSensitive:$false |
        Select-Object -First 1
    if (-not $line) {
        return ''
    }

    $value = $line.Matches[0].Groups[1].Value.Trim()
    if ($value -match ',\s*([0-9.]+)\s*$') {
        return $Matches[1]
    }
    return $value
}

# Chi quet/phan tich INF, KHONG goi API cai driver.
# Khoanh vung dong khai bao model = InstallSection,PCI\\VEN_10DE&DEV_1F0B.
# Loai tru comment va dong mo ta [Strings] chi nhac toi Hardware ID.
function Test-InfHasCmp40HxInstallEntry {
    param([Parameter(Mandatory = $true)][string]$InfPath)
    if (-not (Test-Path -LiteralPath $InfPath -PathType Leaf)) { return $false }

    $escapedId = [regex]::Escape($script:HardwareId)
    $entryPattern = '^\s*[^;#\[\]\r\n]+?\s*=\s*[^,;\r\n]+,\s*' + $escapedId + '(?=&|\s*(?:;|$))'
    $inNvidiaModelsSection = $false
    foreach ($line in [IO.File]::ReadLines($InfPath)) {
        if ($line -match '^\s*\[([^\]]+)\]') {
            $inNvidiaModelsSection = ($Matches[1] -match '\.NTamd64(?:\.|$)')
            continue
        }
        if ($inNvidiaModelsSection -and $line -match $entryPattern) { return $true }
    }
    return $false
}

function Get-DriverFolderFromInf {
    param([string]$InfPath)
    if (-not $InfPath) { return '' }
    $parent = Split-Path -Parent $InfPath
    if ((Split-Path -Leaf $parent) -ieq 'Display.Driver') {
        return (Split-Path -Parent $parent)
    }
    return $parent
}

function Resolve-DriverFolder {
    param([Parameter(Mandatory = $true)][string]$FolderPath)

    $folder = $FolderPath.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw "Không tìm thấy thư mục driver: $folder"
    }
    $fullFolder = (Get-Item -LiteralPath $folder -ErrorAction Stop).FullName
    $files = @(Get-ChildItem -LiteralPath $fullFolder -Filter '*.inf' -File -Recurse -ErrorAction Stop)
    if ($files.Count -eq 0) {
        throw "Thư mục không chứa file INF: $fullFolder"
    }

    $candidates = @()
    foreach ($file in $files) {
        # Chi xet INF driver man hinh co DriverVer va device-install entry that.
        # Khong nhan INF chỉ nhac ma 1F0B trong comment, [Strings] hay ghi chu.
        $header = Select-String -LiteralPath $file.FullName -Pattern '^\s*Class\s*=\s*Display\s*(?:;.*)?$' -CaseSensitive:$false -Quiet
        if (-not $header) { continue }
        if (-not (Test-InfHasCmp40HxInstallEntry -InfPath $file.FullName)) { continue }
        $version = Get-InfVersion -InfPath $file.FullName
        if ([string]::IsNullOrWhiteSpace($version)) { continue }
        $candidates += [pscustomobject]@{ Path = $file.FullName; Version = $version }
    }

    if ($candidates.Count -eq 0) {
        throw "Không tìm thấy INF Display hợp lệ có dòng cài đặt $($script:HardwareId) trong '$fullFolder'. Kiểm tra bộ driver đã giải nén hoặc bản mod."
    }
    if ($candidates.Count -gt 1) {
        $items = ($candidates | ForEach-Object { " - $($_.Path) (DriverVer $($_.Version))" }) -join "`r`n"
        throw "Phát hiện $($candidates.Count) INF cùng hỗ trợ CMP 40HX trong một thư mục. Không tự chọn để tránh cài nhầm. Hãy chọn thư mục con chỉ chứa đúng bộ driver cần dùng.`r`n$items"
    }

    Write-AppLog "Tự tìm INF trong '$fullFolder' -> $($candidates[0].Path), DriverVer=$($candidates[0].Version)"
    return [pscustomobject]@{
        Folder = $fullFolder
        InfPath = $candidates[0].Path
        Version = $candidates[0].Version
    }
}

function Assert-DriverProfileFolder {
    param($Config, [ValidateSet('Work', 'Game')][string]$Profile)

    $folder = if ($Profile -eq 'Work') { [string]$Config.WorkDirectory } else { [string]$Config.GameDirectory }
    $savedInf = if ($Profile -eq 'Work') { [string]$Config.WorkInf } else { [string]$Config.GameInf }
    $savedVer = if ($Profile -eq 'Work') { [string]$Config.WorkVersion } else { [string]$Config.GameVersion }
    if (-not $folder) { throw "Chưa chọn thư mục driver $Profile. Mở Thiết lập driver để chọn." }
    $found = Resolve-DriverFolder -FolderPath $folder
    if ($found.InfPath -ine $savedInf -or $found.Version -ne $savedVer) {
        throw "Thư mục driver $Profile đã thay đổi so với khi lưu cấu hình. Mở Thiết lập driver, kiểm tra và lưu lại trước khi chuyển."
    }
    return $found
}

function Test-InfSupportsCmp40Hx {
    param([string]$InfPath)

    if (-not $InfPath -or -not (Test-Path -LiteralPath $InfPath -PathType Leaf)) {
        return $false
    }

    return (Test-InfHasCmp40HxInstallEntry -InfPath $InfPath)
}

function Test-InfContainsGameModel {
    param([string]$InfPath, [string]$ModelName)

    if ([string]::IsNullOrWhiteSpace($ModelName) -or -not $InfPath -or -not (Test-Path -LiteralPath $InfPath -PathType Leaf)) {
        return $false
    }

    # Kiểm tra sơ bộ: khi cài thật, SetupAPI còn xác thực model trong danh sách driver.
    return $null -ne (Select-String -LiteralPath $InfPath -SimpleMatch $ModelName -CaseSensitive:$false | Select-Object -First 1)
}

function Get-GameInstallSelection {
    param([string]$InfPath, [string]$ModelName, [switch]$ValidateWithSetupApi)

    if (-not $InfPath -or -not (Test-Path -LiteralPath $InfPath -PathType Leaf)) {
        throw 'Chưa chọn file INF hợp lệ cho chế độ chơi game.'
    }
    if (Test-InfSupportsCmp40Hx -InfPath $InfPath) {
        return [pscustomobject]@{ Mode = 'Compatible'; ModelName = '' }
    }
    if (-not (Test-InfContainsGameModel -InfPath $InfPath -ModelName $ModelName)) {
        throw 'INF game không chứa DEV_1F0B. Hãy nhập đúng tên model trong INF hoặc dùng INF đã hỗ trợ CMP 40HX.'
    }
    if ($ValidateWithSetupApi -and -not $script:Simulation) {
        Initialize-ForcedModelDriverApi
        $device = Get-CmpDeviceInfo
        if (-not [Cmp40Hx.ForcedModelDriverApi]::ContainsModel($device.InstanceId, ([IO.Path]::GetFullPath($InfPath)), $ModelName)) {
            throw "SetupAPI không tìm thấy model '$ModelName' trong INF dành cho thiết bị hiện tại."
        }
    }
    return [pscustomobject]@{ Mode = 'ForcedModel'; ModelName = $ModelName }
}

function New-DefaultConfig {
    # Không dùng C:\Windows\INF\oem*.inf làm bộ cài nguồn: API cài driver
    # yêu cầu đường dẫn gói INF đầy đủ, có các file driver đi kèm.
    $workInf = if ($script:Simulation) { Join-Path (Join-Path $script:FixtureDirectory 'work') 'work-driver.inf' } else { '' }

    return [pscustomobject]@{
        HardwareId = $script:HardwareId
        WorkInf     = $workInf
        WorkVersion = (Get-InfVersion -InfPath $workInf)
        WorkDirectory = if ($script:Simulation) { Join-Path $script:FixtureDirectory 'work' } else { '' }
        GameDirectory = if ($script:Simulation) { Join-Path $script:FixtureDirectory 'game' } else { '' }
        GameInf     = if ($script:Simulation) { Join-Path (Join-Path $script:FixtureDirectory 'game') 'game-driver.inf' } else { '' }
        GameVersion = if ($script:Simulation) { '26.21.14.4614' } else { '' }
        GameModel   = $script:GameModel
    }
}

function Save-Config {
    param($Config)

    if (-not ($Config.PSObject.Properties.Name -contains 'GameModel')) {
        $Config | Add-Member -NotePropertyName GameModel -NotePropertyValue $script:GameModel
    }
    if (-not ($Config.PSObject.Properties.Name -contains 'WorkDirectory')) {
        $Config | Add-Member -NotePropertyName WorkDirectory -NotePropertyValue (Get-DriverFolderFromInf -InfPath $Config.WorkInf)
    }
    if (-not ($Config.PSObject.Properties.Name -contains 'GameDirectory')) {
        $Config | Add-Member -NotePropertyName GameDirectory -NotePropertyValue (Get-DriverFolderFromInf -InfPath $Config.GameInf)
    }
    # Giữ đúng model mà người dùng chọn; không tự ép model của GPU khác.
    $Config.GameModel = ([string]$Config.GameModel).Trim()
    $Config.WorkVersion = Get-InfVersion -InfPath $Config.WorkInf
    $Config.GameVersion = Get-InfVersion -InfPath $Config.GameInf
    $Config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
}

function Get-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        $config = New-DefaultConfig
        Save-Config -Config $config
        return $config
    }

    try {
        $config = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $config.HardwareId -or $config.HardwareId -ne $script:HardwareId) {
            throw 'Hardware ID trong cấu hình không hợp lệ.'
        }
        $migrated = $false
        if (-not ($config.PSObject.Properties.Name -contains 'GameModel')) {
            $config | Add-Member -NotePropertyName GameModel -NotePropertyValue $script:GameModel
            $migrated = $true
        }
        if (-not ($config.PSObject.Properties.Name -contains 'WorkDirectory')) {
            $config | Add-Member -NotePropertyName WorkDirectory -NotePropertyValue (Get-DriverFolderFromInf -InfPath $config.WorkInf)
            $migrated = $true
        }
        if (-not ($config.PSObject.Properties.Name -contains 'GameDirectory')) {
            $config | Add-Member -NotePropertyName GameDirectory -NotePropertyValue (Get-DriverFolderFromInf -InfPath $config.GameInf)
            $migrated = $true
        }
        if ($migrated) { Save-Config -Config $config }
        return $config
    }
    catch {
        $backup = "$($script:ConfigPath).invalid-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item -LiteralPath $script:ConfigPath -Destination $backup
        Write-AppLog "Cấu hình lỗi đã được chuyển sang $backup"
        $config = New-DefaultConfig
        Save-Config -Config $config
        return $config
    }
}

function Initialize-NativeDriverApi {
    if ('Cmp40Hx.NativeDriverApi' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Cmp40Hx
{
    public static class NativeDriverApi
    {
        [DllImport("newdev.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool UpdateDriverForPlugAndPlayDevicesW(
            IntPtr hwndParent,
            string hardwareId,
            string fullInfPath,
            uint installFlags,
            out bool rebootRequired);

        private const uint INSTALLFLAG_FORCE = 0x00000001;
        private const uint INSTALLFLAG_NONINTERACTIVE = 0x00000004;

        public static bool ForceInstall(string hardwareId, string fullInfPath)
        {
            bool rebootRequired;
            bool ok = UpdateDriverForPlugAndPlayDevicesW(
                IntPtr.Zero,
                hardwareId,
                fullInfPath,
                INSTALLFLAG_FORCE | INSTALLFLAG_NONINTERACTIVE,
                out rebootRequired);

            if (!ok)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            return rebootRequired;
        }
    }
}
'@
}

function Initialize-ForcedModelDriverApi {
    if ('Cmp40Hx.ForcedModelDriverApi' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Cmp40Hx
{
    public static class ForcedModelDriverApi
    {
        private const uint SPDIT_CLASSDRIVER = 0x00000001;
        private const uint DI_SHOWALL = 0x00000007;
        private const uint DI_ENUMSINGLEINF = 0x00010000;
        private const uint DI_QUIETINSTALL = 0x00800000;
        private const uint DI_FLAGSEX_ALLOWEXCLUDEDDRVS = 0x00000800;
        private static readonly IntPtr InvalidHandleValue = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        private struct SP_DEVINFO_DATA
        {
            public uint cbSize;
            public Guid ClassGuid;
            public uint DevInst;
            public IntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct SP_DEVINSTALL_PARAMS
        {
            public uint cbSize;
            public uint Flags;
            public uint FlagsEx;
            public IntPtr hwndParent;
            public IntPtr InstallMsgHandler;
            public IntPtr InstallMsgHandlerContext;
            public IntPtr FileQueue;
            public IntPtr ClassInstallReserved;
            public uint Reserved;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string DriverPath;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct SP_DRVINFO_DATA
        {
            public uint cbSize;
            public uint DriverType;
            public IntPtr Reserved;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string Description;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string MfgName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string ProviderName;
            public System.Runtime.InteropServices.ComTypes.FILETIME DriverDate;
            public ulong DriverVersion;
        }

        [DllImport("setupapi.dll", SetLastError = true)]
        private static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr ClassGuid, IntPtr hwndParent);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetupDiOpenDeviceInfoW(IntPtr DeviceInfoSet, string DeviceInstanceId, IntPtr hwndParent, uint OpenFlags, ref SP_DEVINFO_DATA DeviceInfoData);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetupDiGetDeviceInstallParamsW(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, ref SP_DEVINSTALL_PARAMS DeviceInstallParams);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetupDiSetDeviceInstallParamsW(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, ref SP_DEVINSTALL_PARAMS DeviceInstallParams);

        [DllImport("setupapi.dll", SetLastError = true)]
        private static extern bool SetupDiBuildDriverInfoList(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, uint DriverType);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetupDiEnumDriverInfoW(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, uint DriverType, uint MemberIndex, ref SP_DRVINFO_DATA DriverInfoData);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetupDiSetSelectedDriverW(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, ref SP_DRVINFO_DATA DriverInfoData);

        [DllImport("newdev.dll", SetLastError = true)]
        private static extern bool DiInstallDevice(IntPtr hwndParent, IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, ref SP_DRVINFO_DATA DriverInfoData, uint Flags, out bool NeedReboot);

        [DllImport("setupapi.dll", SetLastError = true)]
        private static extern bool SetupDiDestroyDriverInfoList(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, uint DriverType);

        [DllImport("setupapi.dll", SetLastError = true)]
        private static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

        private static void ThrowLastError(string operation)
        {
            int code = Marshal.GetLastWin32Error();
            throw new Win32Exception(code, operation + " failed with Windows error " + code);
        }

        private static IntPtr BuildSingleInfList(string instanceId, string infPath, out SP_DEVINFO_DATA device)
        {
            IntPtr set = SetupDiCreateDeviceInfoList(IntPtr.Zero, IntPtr.Zero);
            if (set == InvalidHandleValue) ThrowLastError("SetupDiCreateDeviceInfoList");

            device = new SP_DEVINFO_DATA();
            device.cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVINFO_DATA));
            try
            {
                if (!SetupDiOpenDeviceInfoW(set, instanceId, IntPtr.Zero, 0, ref device)) ThrowLastError("SetupDiOpenDeviceInfo");

                SP_DEVINSTALL_PARAMS parameters = new SP_DEVINSTALL_PARAMS();
                parameters.cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVINSTALL_PARAMS));
                if (!SetupDiGetDeviceInstallParamsW(set, ref device, ref parameters)) ThrowLastError("SetupDiGetDeviceInstallParams");
                parameters.Flags |= DI_SHOWALL | DI_ENUMSINGLEINF | DI_QUIETINSTALL;
                parameters.FlagsEx |= DI_FLAGSEX_ALLOWEXCLUDEDDRVS;
                parameters.DriverPath = infPath;
                if (!SetupDiSetDeviceInstallParamsW(set, ref device, ref parameters)) ThrowLastError("SetupDiSetDeviceInstallParams");
                if (!SetupDiBuildDriverInfoList(set, ref device, SPDIT_CLASSDRIVER)) ThrowLastError("SetupDiBuildDriverInfoList");
                return set;
            }
            catch
            {
                SetupDiDestroyDeviceInfoList(set);
                throw;
            }
        }

        private static SP_DRVINFO_DATA FindModel(IntPtr set, ref SP_DEVINFO_DATA device, string modelName)
        {
            for (uint index = 0; ; index++)
            {
                SP_DRVINFO_DATA driver = new SP_DRVINFO_DATA();
                driver.cbSize = (uint)Marshal.SizeOf(typeof(SP_DRVINFO_DATA));
                if (!SetupDiEnumDriverInfoW(set, ref device, SPDIT_CLASSDRIVER, index, ref driver))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 259) break;
                    throw new Win32Exception(error, "SetupDiEnumDriverInfo failed");
                }
                if (String.Equals(driver.Description, modelName, StringComparison.OrdinalIgnoreCase)) return driver;
            }
            throw new InvalidOperationException("The selected INF does not contain model: " + modelName);
        }

        public static bool ContainsModel(string instanceId, string infPath, string modelName)
        {
            SP_DEVINFO_DATA device;
            IntPtr set = BuildSingleInfList(instanceId, infPath, out device);
            try
            {
                FindModel(set, ref device, modelName);
                return true;
            }
            catch (InvalidOperationException)
            {
                return false;
            }
            finally
            {
                SetupDiDestroyDriverInfoList(set, ref device, SPDIT_CLASSDRIVER);
                SetupDiDestroyDeviceInfoList(set);
            }
        }

        public static bool ForceInstallModel(string instanceId, string infPath, string modelName)
        {
            SP_DEVINFO_DATA device;
            IntPtr set = BuildSingleInfList(instanceId, infPath, out device);
            try
            {
                SP_DRVINFO_DATA driver = FindModel(set, ref device, modelName);
                if (!SetupDiSetSelectedDriverW(set, ref device, ref driver)) ThrowLastError("SetupDiSetSelectedDriver");
                bool rebootRequired;
                if (!DiInstallDevice(IntPtr.Zero, set, ref device, ref driver, 0, out rebootRequired)) ThrowLastError("DiInstallDevice");
                return rebootRequired;
            }
            finally
            {
                SetupDiDestroyDriverInfoList(set, ref device, SPDIT_CLASSDRIVER);
                SetupDiDestroyDeviceInfoList(set);
            }
        }
    }
}
'@
}

function Install-CmpDriver {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileName,
        [Parameter(Mandatory = $true)][string]$InfPath,
        [ValidateSet('Compatible', 'ForcedModel')][string]$InstallMode = 'Compatible',
        [string]$ModelName = ''
    )

    $fullPath = [IO.Path]::GetFullPath($InfPath)
    Write-AppLog "Bắt đầu chuyển sang '$ProfileName': $fullPath"

    if ($script:Simulation) {
        if ($InstallMode -eq 'ForcedModel') {
            if (-not $ModelName -or -not (Test-InfContainsGameModel -InfPath $fullPath -ModelName $ModelName)) {
                throw "INF mô phỏng không chứa model '$ModelName'."
            }
            $script:SimulationProfile = 'Game'
        }
        else {
            if (-not (Test-InfSupportsCmp40Hx -InfPath $fullPath)) {
                throw "INF mô phỏng không chứa $($script:HardwareId)."
            }
            $script:SimulationProfile = if ($ProfileName -match 'LOL|Game|Valorant') { 'Game' } else { 'Work' }
        }

        $after = Get-CmpDeviceInfo
        Write-AppLog "MÔ PHỎNG hoàn tất '$ProfileName': $($after.Description), $($after.PublishedName), $($after.Version)"
        return [pscustomobject]@{
            RebootRequired = $false
            Device         = $after
            Simulation     = $true
        }
    }

    if ($InstallMode -eq 'ForcedModel') {
        if (-not $ModelName) {
            throw 'Chưa cấu hình model giả lập cho GPU chơi LOL / Valorant.'
        }
        Initialize-ForcedModelDriverApi
        $deviceBefore = Get-CmpDeviceInfo
        if (-not [Cmp40Hx.ForcedModelDriverApi]::ContainsModel($deviceBefore.InstanceId, $fullPath, $ModelName)) {
            throw "INF LOL / Valorant không chứa model '$ModelName'."
        }
        $rebootRequired = [Cmp40Hx.ForcedModelDriverApi]::ForceInstallModel($deviceBefore.InstanceId, $fullPath, $ModelName)
    }
    else {
        if (-not (Test-InfSupportsCmp40Hx -InfPath $fullPath)) {
            throw "INF GPU công suất tối đa không chứa $($script:HardwareId)."
        }
        Initialize-NativeDriverApi
        $rebootRequired = [Cmp40Hx.NativeDriverApi]::ForceInstall($script:HardwareId, $fullPath)
    }

    Start-Sleep -Seconds 2
    $after = Get-CmpDeviceInfo
    Write-AppLog "Hoàn tất '$ProfileName': $($after.Description), $($after.PublishedName), $($after.Version), reboot=$rebootRequired"
    if (-not $rebootRequired) {
        $expectedVersion = Get-InfVersion -InfPath $fullPath
        $actualVersion = Convert-DriverVersionForComparison -Value $after.Version
        if ($expectedVersion -and $actualVersion -and $expectedVersion -ne $actualVersion) {
            throw "API trả về thành công nhưng driver hiện tại ($actualVersion) chưa trùng INF đã chọn ($expectedVersion). Kiểm tra Device Manager và nhật ký; KHÔNG coi chuyển đổi đã hoàn tất."
        }
    }

    return [pscustomobject]@{
        RebootRequired = $rebootRequired
        Device         = $after
        Simulation     = $false
    }
}

function Select-DriverFolder {
    param(
        [string]$InitialPath,
        [string]$DialogTitle = 'Chọn thư mục driver đã giải nén'
    )
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $DialogTitle
    $dialog.ShowNewFolderButton = $false
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath -PathType Container)) {
        $dialog.SelectedPath = $InitialPath
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return ''
}

function Show-SettingsDialog {
    param($Config)

    $settings = New-Object System.Windows.Forms.Form
    $settings.Text = 'Thiết lập thư mục driver CMP 40HX'
    $settings.StartPosition = 'CenterParent'
    $settings.Size = New-Object Drawing.Size(760, 470)
    $settings.FormBorderStyle = 'FixedDialog'
    $settings.MaximizeBox = $false
    $settings.MinimizeBox = $false

    $info = New-Object System.Windows.Forms.Label
    $info.Location = New-Object Drawing.Point(20, 14)
    $info.Size = New-Object Drawing.Size(710, 48)
    $info.Text = 'Chỉ chọn THƯ MỤC chứa bộ driver đã giải nén (có thể là thư mục cha của Display.Driver). Phần mềm sẽ tự tìm INF Display chứa DEV_1F0B; không cài driver khi bấm Lưu.'
    $settings.Controls.Add($info)

    $workLabel = New-Object System.Windows.Forms.Label
    $workLabel.Location = New-Object Drawing.Point(20, 74)
    $workLabel.Size = New-Object Drawing.Size(150, 24)
    $workLabel.Text = 'GPU công suất tối đa:'
    $settings.Controls.Add($workLabel)

    $workText = New-Object System.Windows.Forms.TextBox
    $workText.Location = New-Object Drawing.Point(170, 72)
    $workText.Size = New-Object Drawing.Size(480, 24)
    $workText.Text = [string]$Config.WorkDirectory
    $settings.Controls.Add($workText)

    $workResult = New-Object System.Windows.Forms.Label
    $workResult.Location = New-Object Drawing.Point(170, 103)
    $workResult.Size = New-Object Drawing.Size(560, 34)
    $workResult.ForeColor = [Drawing.Color]::DimGray
    $workResult.Text = if ($Config.WorkInf) { "INF đã lưu: $([IO.Path]::GetFileName([string]$Config.WorkInf)) - $($Config.WorkVersion)" } else { 'Chưa tìm INF' }
    $settings.Controls.Add($workResult)

    $workBrowse = New-Object System.Windows.Forms.Button
    $workBrowse.Location = New-Object Drawing.Point(660, 70)
    $workBrowse.Size = New-Object Drawing.Size(70, 28)
    $workBrowse.Text = 'Chọn...'
    $workBrowse.Add_Click({
        $selected = Select-DriverFolder -InitialPath $workText.Text -DialogTitle 'Chọn THƯ MỤC driver tác vụ AI / làm việc'
        if ($selected) {
            $workText.Text = $selected
            try {
                $resolved = Resolve-DriverFolder -FolderPath $selected
                $workResult.Text = "Tìm thấy: $([IO.Path]::GetFileName($resolved.InfPath)) - DriverVer $($resolved.Version)"
            }
            catch { $workResult.Text = "Không hợp lệ: $($_.Exception.Message)" }
        }
    })
    $settings.Controls.Add($workBrowse)

    $gameLabel = New-Object System.Windows.Forms.Label
    $gameLabel.Location = New-Object Drawing.Point(20, 146)
    $gameLabel.Size = New-Object Drawing.Size(150, 24)
    $gameLabel.Text = 'GPU LOL / Valorant:'
    $settings.Controls.Add($gameLabel)

    $gameText = New-Object System.Windows.Forms.TextBox
    $gameText.Location = New-Object Drawing.Point(170, 144)
    $gameText.Size = New-Object Drawing.Size(480, 24)
    $gameText.Text = [string]$Config.GameDirectory
    $settings.Controls.Add($gameText)

    $gameResult = New-Object System.Windows.Forms.Label
    $gameResult.Location = New-Object Drawing.Point(170, 175)
    $gameResult.Size = New-Object Drawing.Size(560, 34)
    $gameResult.ForeColor = [Drawing.Color]::DimGray
    $gameResult.Text = if ($Config.GameInf) { "INF đã lưu: $([IO.Path]::GetFileName([string]$Config.GameInf)) - $($Config.GameVersion)" } else { 'Chưa tìm INF' }
    $settings.Controls.Add($gameResult)

    $gameBrowse = New-Object System.Windows.Forms.Button
    $gameBrowse.Location = New-Object Drawing.Point(660, 142)
    $gameBrowse.Size = New-Object Drawing.Size(70, 28)
    $gameBrowse.Text = 'Chọn...'
    $gameBrowse.Add_Click({
        $selected = Select-DriverFolder -InitialPath $gameText.Text -DialogTitle 'Chọn THƯ MỤC driver 460 mod chơi LOL'
        if ($selected) {
            $gameText.Text = $selected
            try {
                $resolved = Resolve-DriverFolder -FolderPath $selected
                $gameResult.Text = "Tìm thấy: $([IO.Path]::GetFileName($resolved.InfPath)) - DriverVer $($resolved.Version)"
            }
            catch { $gameResult.Text = "Không hợp lệ: $($_.Exception.Message)" }
        }
    })
    $settings.Controls.Add($gameBrowse)

    $modelLabel = New-Object System.Windows.Forms.Label
    $modelLabel.Location = New-Object Drawing.Point(20, 218)
    $modelLabel.Size = New-Object Drawing.Size(150, 35)
    $modelLabel.Text = 'Model ép (nếu cần):'
    $settings.Controls.Add($modelLabel)

    $modelText = New-Object System.Windows.Forms.TextBox
    $modelText.Location = New-Object Drawing.Point(170, 216)
    $modelText.Size = New-Object Drawing.Size(560, 24)
    $modelText.Text = [string]$Config.GameModel
    $settings.Controls.Add($modelText)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object Drawing.Point(20, 263)
    $hint.Size = New-Object Drawing.Size(710, 76)
    $hint.ForeColor = [Drawing.Color]::DimGray
    $hint.Text = 'Cả hai bộ driver 460 mod và 617.14 bạn đang dùng đều có DEV_1F0B: để trống Model ép. Nếu nhiều INF cùng khớp, công cụ sẽ DỪNG chứ không chọn bừa. Đổi thư mục hoặc sửa INF phải vào đây lưu lại.'
    $settings.Controls.Add($hint)

    $save = New-Object System.Windows.Forms.Button
    $save.Location = New-Object Drawing.Point(540, 351)
    $save.Size = New-Object Drawing.Size(90, 32)
    $save.Text = 'Lưu'
    $save.Add_Click({
        try {
            $work = Resolve-DriverFolder -FolderPath $workText.Text
            $game = Resolve-DriverFolder -FolderPath $gameText.Text
            $choice = Get-GameInstallSelection -InfPath $game.InfPath -ModelName $modelText.Text -ValidateWithSetupApi
            if ($work.Version -eq $game.Version) {
                throw 'Hai INF có cùng DriverVer nên không phân biệt được hai chế độ. Chọn hai phiên bản driver khác nhau.'
            }
            if ($choice.Mode -eq 'ForcedModel') {
                throw 'Chế độ tự chọn thư mục chỉ hỗ trợ INF cài trực tiếp cho DEV_1F0B, không tự ép model khác.'
            }
            $Config.WorkDirectory = $work.Folder
            $Config.GameDirectory = $game.Folder
            $Config.WorkInf = $work.InfPath
            $Config.GameInf = $game.InfPath
            $Config.GameModel = $modelText.Text.Trim()
            Save-Config -Config $Config
            $settings.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $settings.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'CMP 40HX - Không thể lưu', 'OK', 'Warning') | Out-Null
        }
    })
    $settings.Controls.Add($save)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Location = New-Object Drawing.Point(640, 351)
    $cancel.Size = New-Object Drawing.Size(90, 32)
    $cancel.Text = 'Hủy'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $settings.Controls.Add($cancel)

    return $settings.ShowDialog()
}

function Convert-DriverVersionForComparison {
    param([string]$Value)
    if (-not $Value) { return '' }
    if ($Value -match '([0-9]+(?:\.[0-9]+){2,})\s*$') { return $Matches[1] }
    return $Value.Trim()
}

function Start-Gui {
    Write-AppLog "ApartmentState=$([Threading.Thread]::CurrentThread.ApartmentState)"
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Write-AppLog 'Đã nạp Windows Forms.'

    Write-AppLog 'Đang đọc cấu hình.'
    $script:Config = Get-Config
    Write-AppLog 'Đã đọc cấu hình; đang tạo giao diện.'

    $navy = [Drawing.Color]::FromArgb(19, 42, 76)
    $blue = [Drawing.Color]::FromArgb(37, 99, 235)
    $green = [Drawing.Color]::FromArgb(22, 163, 74)
    $orange = [Drawing.Color]::FromArgb(194, 65, 12)
    $surface = [Drawing.Color]::White
    $background = [Drawing.Color]::FromArgb(241, 245, 249)
    $muted = [Drawing.Color]::FromArgb(71, 85, 105)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = if ($script:Simulation) { 'CMP40HX Driver Toggle - MÔ PHỎNG' } else { 'CMP40HX Driver Toggle' }
    $form.StartPosition = 'CenterScreen'
    $form.ClientSize = New-Object Drawing.Size(720, 728)
    $form.MinimumSize = New-Object Drawing.Size(736, 767)
    $form.BackColor = $background
    $form.Font = New-Object Drawing.Font('Segoe UI', 9)
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.Add_Shown({
        $form.Activate()
        $form.BringToFront()
    })

    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object Drawing.Point(0, 0)
    $header.Size = New-Object Drawing.Size(720, 88)
    $header.BackColor = $navy
    $form.Controls.Add($header)

    $title = New-Object System.Windows.Forms.Label
    $title.Location = New-Object Drawing.Point(24, 17)
    $title.Size = New-Object Drawing.Size(470, 32)
    $title.Font = New-Object Drawing.Font('Segoe UI Semibold', 18, [Drawing.FontStyle]::Bold)
    $title.ForeColor = [Drawing.Color]::White
    $title.Text = 'CMP40HX-DriverToggle'
    $header.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Location = New-Object Drawing.Point(27, 53)
    $subtitle.Size = New-Object Drawing.Size(500, 22)
    $subtitle.ForeColor = [Drawing.Color]::FromArgb(203, 213, 225)
    $subtitle.Text = 'Chuyển hồ sơ driver có kiểm tra • Bản CMP 40HX'
    $header.Controls.Add($subtitle)

    $modeBadge = New-Object System.Windows.Forms.Label
    $modeBadge.Location = New-Object Drawing.Point(556, 25)
    $modeBadge.Size = New-Object Drawing.Size(136, 36)
    $modeBadge.TextAlign = 'MiddleCenter'
    $modeBadge.Font = New-Object Drawing.Font('Segoe UI Semibold', 10, [Drawing.FontStyle]::Bold)
    if ($script:Simulation) {
        $modeBadge.Text = '● MÔ PHỎNG'
        $modeBadge.BackColor = [Drawing.Color]::FromArgb(220, 252, 231)
        $modeBadge.ForeColor = $green
    }
    else {
        $modeBadge.Text = '● CHẾ ĐỘ THẬT'
        $modeBadge.BackColor = [Drawing.Color]::FromArgb(254, 226, 226)
        $modeBadge.ForeColor = [Drawing.Color]::FromArgb(185, 28, 28)
    }
    $header.Controls.Add($modeBadge)

    $modePanel = New-Object System.Windows.Forms.Panel
    $modePanel.Location = New-Object Drawing.Point(24, 108)
    $modePanel.Size = New-Object Drawing.Size(672, 160)
    $modePanel.BackColor = $navy
    $form.Controls.Add($modePanel)

    $modeHeading = New-Object System.Windows.Forms.Label
    $modeHeading.Location = New-Object Drawing.Point(25, 40)
    $modeHeading.Size = New-Object Drawing.Size(620, 43)
    $modeHeading.TextAlign = 'MiddleCenter'
    $modeHeading.Font = New-Object Drawing.Font('Segoe UI Semibold', 18, [Drawing.FontStyle]::Bold)
    $modeHeading.ForeColor = [Drawing.Color]::White
    $modePanel.Controls.Add($modeHeading)

    $modeDetail = New-Object System.Windows.Forms.Label
    $modeDetail.Location = New-Object Drawing.Point(30, 92)
    $modeDetail.Size = New-Object Drawing.Size(610, 35)
    $modeDetail.TextAlign = 'MiddleCenter'
    $modeDetail.ForeColor = [Drawing.Color]::FromArgb(203, 213, 225)
    $modePanel.Controls.Add($modeDetail)

    $deviceCard = New-Object System.Windows.Forms.Panel
    $deviceCard.Location = New-Object Drawing.Point(24, 284)
    $deviceCard.Size = New-Object Drawing.Size(672, 156)
    $deviceCard.BackColor = $surface
    $deviceCard.BorderStyle = 'FixedSingle'
    $form.Controls.Add($deviceCard)

    $sectionTitle = New-Object System.Windows.Forms.Label
    $sectionTitle.Location = New-Object Drawing.Point(18, 14)
    $sectionTitle.Size = New-Object Drawing.Size(250, 20)
    $sectionTitle.Font = New-Object Drawing.Font('Segoe UI Semibold', 9, [Drawing.FontStyle]::Bold)
    $sectionTitle.ForeColor = $muted
    $sectionTitle.Text = 'TRẠNG THÁI HIỆN TẠI'
    $deviceCard.Controls.Add($sectionTitle)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Location = New-Object Drawing.Point(18, 39)
    $profileLabel.Size = New-Object Drawing.Size(623, 30)
    $profileLabel.Font = New-Object Drawing.Font('Segoe UI Semibold', 15, [Drawing.FontStyle]::Bold)
    $profileLabel.ForeColor = $navy
    $deviceCard.Controls.Add($profileLabel)

    $deviceLabel = New-Object System.Windows.Forms.Label
    $deviceLabel.Location = New-Object Drawing.Point(20, 76)
    $deviceLabel.Size = New-Object Drawing.Size(621, 70)
    $deviceLabel.Font = New-Object Drawing.Font('Segoe UI', 9)
    $deviceLabel.ForeColor = $muted
    $deviceCard.Controls.Add($deviceLabel)

    $warningPanel = New-Object System.Windows.Forms.Panel
    $warningPanel.Location = New-Object Drawing.Point(24, 456)
    $warningPanel.Size = New-Object Drawing.Size(672, 54)
    $warningPanel.BackColor = if ($script:Simulation) { [Drawing.Color]::FromArgb(220, 252, 231) } else { [Drawing.Color]::FromArgb(255, 237, 213) }
    $form.Controls.Add($warningPanel)

    $warningIcon = New-Object System.Windows.Forms.Label
    $warningIcon.Location = New-Object Drawing.Point(16, 14)
    $warningIcon.Size = New-Object Drawing.Size(28, 28)
    $warningIcon.Font = New-Object Drawing.Font('Segoe UI Symbol', 14, [Drawing.FontStyle]::Bold)
    $warningIcon.ForeColor = if ($script:Simulation) { $green } else { $orange }
    $warningIcon.Text = if ($script:Simulation) { '✓' } else { '!' }
    $warningPanel.Controls.Add($warningIcon)

    $warning = New-Object System.Windows.Forms.Label
    $warning.Location = New-Object Drawing.Point(49, 9)
    $warning.Size = New-Object Drawing.Size(600, 38)
    $warning.TextAlign = 'MiddleLeft'
    $warning.ForeColor = if ($script:Simulation) { [Drawing.Color]::FromArgb(21, 128, 61) } else { $orange }
    $warning.Text = if ($script:Simulation) {
        'Mô phỏng an toàn: không gọi pnputil, SetupAPI, NewDev hoặc thay đổi driver thật.'
    }
    else {
        'Đóng game và mọi ứng dụng dùng GPU trước khi chuyển. Màn hình có thể chớp trong vài giây.'
    }
    $warningPanel.Controls.Add($warning)

    $actionTitle = New-Object System.Windows.Forms.Label
    $actionTitle.Location = New-Object Drawing.Point(24, 527)
    $actionTitle.Size = New-Object Drawing.Size(250, 20)
    $actionTitle.Font = New-Object Drawing.Font('Segoe UI Semibold', 9, [Drawing.FontStyle]::Bold)
    $actionTitle.ForeColor = $muted
    $actionTitle.Text = 'THAO TÁC TIẾP THEO'
    $form.Controls.Add($actionTitle)

    $toggle = New-Object System.Windows.Forms.Button
    $toggle.Location = New-Object Drawing.Point(24, 552)
    $toggle.Size = New-Object Drawing.Size(672, 64)
    $toggle.FlatStyle = 'Flat'
    $toggle.FlatAppearance.BorderSize = 0
    $toggle.Font = New-Object Drawing.Font('Segoe UI Semibold', 13, [Drawing.FontStyle]::Bold)
    $toggle.ForeColor = [Drawing.Color]::White
    $toggle.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($toggle)

    $progressTitle = New-Object System.Windows.Forms.Label
    $progressTitle.Location = New-Object Drawing.Point(27, 627)
    $progressTitle.Size = New-Object Drawing.Size(105, 22)
    $progressTitle.Font = New-Object Drawing.Font('Segoe UI Semibold', 9, [Drawing.FontStyle]::Bold)
    $progressTitle.ForeColor = $muted
    $progressTitle.Text = 'TIẾN TRÌNH'
    $form.Controls.Add($progressTitle)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(139, 626)
    $progress.Size = New-Object Drawing.Size(493, 23)
    $progress.Minimum = 0
    $progress.Maximum = 100
    $progress.Value = 0
    $progress.Style = 'Continuous'
    $form.Controls.Add($progress)

    $progressPercent = New-Object System.Windows.Forms.Label
    $progressPercent.Location = New-Object Drawing.Point(640, 625)
    $progressPercent.Size = New-Object Drawing.Size(56, 24)
    $progressPercent.TextAlign = 'MiddleRight'
    $progressPercent.Font = New-Object Drawing.Font('Segoe UI Semibold', 10, [Drawing.FontStyle]::Bold)
    $progressPercent.ForeColor = $navy
    $progressPercent.Text = '0%'
    $form.Controls.Add($progressPercent)

    $confirm = New-Object System.Windows.Forms.CheckBox
    $confirm.Location = New-Object Drawing.Point(27, 658)
    $confirm.Size = New-Object Drawing.Size(360, 25)
    $confirm.Text = 'Tôi đã đóng game và các ứng dụng đang dùng GPU'
    $confirm.ForeColor = $muted
    $confirm.Visible = -not $script:Simulation
    $form.Controls.Add($confirm)

    $status = New-Object System.Windows.Forms.Label
    $status.Location = New-Object Drawing.Point(27, 691)
    $status.Size = New-Object Drawing.Size(380, 28)
    $status.Font = New-Object Drawing.Font('Segoe UI Semibold', 9)
    $status.ForeColor = $muted
    $status.Text = '● Sẵn sàng'
    $form.Controls.Add($status)

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Location = New-Object Drawing.Point(424, 686)
    $refreshButton.Size = New-Object Drawing.Size(82, 32)
    $refreshButton.Text = 'Làm mới'
    $form.Controls.Add($refreshButton)

    $settingsButton = New-Object System.Windows.Forms.Button
    $settingsButton.Location = New-Object Drawing.Point(514, 686)
    $settingsButton.Size = New-Object Drawing.Size(182, 32)
    $settingsButton.Text = if ($script:Simulation) { 'Cấu hình mô phỏng...' } else { 'Thiết lập driver...' }
    $form.Controls.Add($settingsButton)

    $script:CurrentDevice = $null
    $script:NextProfile = ''
    function Set-ProgressValue {
        param(
            [int]$Value,
            [string]$Message = ''
        )

        $safeValue = [Math]::Max(0, [Math]::Min(100, $Value))
        $progress.Value = $safeValue
        $progressPercent.Text = "$safeValue%"
        if ($Message) {
            $status.Text = $Message
            $status.ForeColor = $blue
        }
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Animate-Progress {
        param(
            [int]$From,
            [int]$To,
            [string]$Message
        )

        for ($value = $From; $value -le $To; $value += 5) {
            Set-ProgressValue -Value $value -Message $Message
            if ($script:Simulation) {
                Start-Sleep -Milliseconds 25
            }
        }
        if ($progress.Value -ne $To) {
            Set-ProgressValue -Value $To -Message $Message
        }
    }

    function Refresh-UiState {
        param([switch]$KeepStatus)

        try {
            $script:CurrentDevice = Get-CmpDeviceInfo
            $currentVersion = Convert-DriverVersionForComparison $script:CurrentDevice.Version
            $workVersion = Convert-DriverVersionForComparison $script:Config.WorkVersion
            $gameVersion = Convert-DriverVersionForComparison $script:Config.GameVersion
            $nl = [Environment]::NewLine

            $profileKnown = $true
            if ($gameVersion -and $currentVersion -eq $gameVersion) {
                $currentProfile = 'GPU CHƠI LOL / VALORANT'
                $desktopProfile = 'Game'
                $modeHeading.Text = 'CHẾ ĐỘ CHƠI GAME'
                $modeDetail.Text = 'LOL / Valorant • Driver theo cấu hình'
                $modePanel.BackColor = [Drawing.Color]::FromArgb(22, 101, 52)
                $script:NextProfile = 'Work'
                $toggle.Text = 'CHUYỂN SANG GPU CÔNG SUẤT TỐI ĐA  →'
                $toggle.BackColor = $blue
            }
            elseif ($workVersion -and $currentVersion -eq $workVersion) {
                $currentProfile = 'GPU CÔNG SUẤT TỐI ĐA'
                $desktopProfile = 'Work'
                $modeHeading.Text = 'CHẾ ĐỘ LÀM VIỆC'
                $modeDetail.Text = 'Đồ họa / AI • Driver theo cấu hình'
                $modePanel.BackColor = $navy
                $script:NextProfile = 'Game'
                $toggle.Text = 'CHUYỂN SANG GPU CHƠI LOL / VALORANT  →'
                $toggle.BackColor = $green
            }
            else {
                $currentProfile = 'CHƯA XÁC ĐỊNH HỒ SƠ'
                $desktopProfile = ''
                $modeHeading.Text = 'CHƯA XÁC ĐỊNH'
                $modeDetail.Text = 'Hãy thiết lập hai thư mục driver'
                $modePanel.BackColor = $muted
                $script:NextProfile = ''
                $profileKnown = $false
                $toggle.Text = 'THIẾT LẬP DRIVER TRƯỚC KHI CHUYỂN'
                $toggle.BackColor = $muted
            }

            $profileLabel.Text = $currentProfile
            if (-not $script:Simulation -and $profileKnown) {
                try { Update-DesktopShortcut -Profile $desktopProfile -CreateIfMissing }
                catch { Write-AppLog "Không cập nhật được shortcut Desktop/Start Menu: $($_.Exception.Message)" }
            }
            $deviceLabel.Text = ('GPU: {0}{1}Phiên bản: {2}    •    INF: {3}{1}Chữ ký: {4}' -f $script:CurrentDevice.Description, $nl, $script:CurrentDevice.Version, $script:CurrentDevice.PublishedName, $script:CurrentDevice.Signer)
            $toggle.Enabled = $profileKnown -and ($script:Simulation -or $confirm.Checked)
            if (-not $KeepStatus) {
                Set-ProgressValue -Value 0
                $status.Text = if ($profileKnown) { '● Sẵn sàng' } else { '● Cần thiết lập driver / phiên bản chưa khớp' }
                $status.ForeColor = $muted
            }
        }
        catch {
            $profileLabel.Text = 'KHÔNG NHẬN DIỆN ĐƯỢC THIẾT BỊ'
            $deviceLabel.Text = $_.Exception.Message
            $toggle.Enabled = $false
            $status.Text = '● Không thực hiện thay đổi'
            $status.ForeColor = [Drawing.Color]::Firebrick
        }
    }

    $confirm.Add_CheckedChanged({
        $toggle.Enabled = $confirm.Checked -and -not [string]::IsNullOrWhiteSpace($script:NextProfile)
    })

    $refreshButton.Add_Click({
        Refresh-UiState
    })

    $settingsButton.Add_Click({
        if ((Show-SettingsDialog -Config $script:Config) -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:Config = Get-Config
            $status.Text = '● Đã lưu cấu hình driver'
            $status.ForeColor = $green
            Refresh-UiState -KeepStatus
        }
    })

    $toggle.Add_Click({
        $operationSucceeded = $false
        try {
            Set-ProgressValue -Value 0 -Message '● Đang chuẩn bị chuyển driver...'
            Animate-Progress -From 0 -To 15 -Message '● Đang kiểm tra hồ sơ driver...'

            if ($script:NextProfile -eq 'Game') {
                try {
                    $choice = Get-GameInstallSelection -InfPath $script:Config.GameInf -ModelName $script:Config.GameModel -ValidateWithSetupApi
                }
                catch {
                    $status.Text = '● Cần thiết lập driver game'
                    if ((Show-SettingsDialog -Config $script:Config) -ne [System.Windows.Forms.DialogResult]::OK) { return }
                    $script:Config = Get-Config
                    $choice = Get-GameInstallSelection -InfPath $script:Config.GameInf -ModelName $script:Config.GameModel -ValidateWithSetupApi
                }
                $profileName = 'LOL / Valorant'
                $resolvedGame = Assert-DriverProfileFolder -Config $script:Config -Profile Game
                $infPath = $resolvedGame.InfPath
                $installMode = $choice.Mode
                $modelName = $choice.ModelName
                if ($installMode -eq 'ForcedModel' -and -not $script:Simulation) {
                    $answer = [System.Windows.Forms.MessageBox]::Show(
                        "Chuẩn bị ép model '$modelName' lên CMP 40HX. Bạn đã thử bộ driver này và có phương án khôi phục nếu GPU mất hình?",
                        'Xác nhận chuyển driver ép', 'YesNo', 'Warning')
                    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                }
            }
            elseif ($script:NextProfile -eq 'Work') {
                if (-not (Test-InfSupportsCmp40Hx -InfPath $script:Config.WorkInf)) {
                    throw 'INF GPU làm việc không còn hợp lệ hoặc không chứa DEV_1F0B. Mở Thiết lập driver.'
                }
                $profileName = 'GPU công suất tối đa'
                $resolvedWork = Assert-DriverProfileFolder -Config $script:Config -Profile Work
                $infPath = $resolvedWork.InfPath
                $installMode = 'Compatible'
                $modelName = ''
            }
            else {
                throw 'Không xác định được chế độ hiện tại. Hãy thiết lập hai INF và kiểm tra driver trước.'
            }

            $toggle.Enabled = $false
            $settingsButton.Enabled = $false
            $refreshButton.Enabled = $false
            Animate-Progress -From 20 -To 35 -Message '● Đang xác thực INF đã chọn...'
            Animate-Progress -From 40 -To 60 -Message "● Đang chuyển sang driver $profileName..."

            $result = Install-CmpDriver -ProfileName $profileName -InfPath $infPath -InstallMode $installMode -ModelName $modelName
            Animate-Progress -From 65 -To 90 -Message '● Đang xác nhận trạng thái driver mới...'
            Refresh-UiState -KeepStatus
            $operationSucceeded = $true
            if ($result.RebootRequired) {
                [System.Windows.Forms.MessageBox]::Show(
                    'Driver đã được đổi nhưng Windows yêu cầu khởi động lại để hoàn tất.',
                    'CMP 40HX',
                    'OK',
                    'Information') | Out-Null
            }
        }
        catch {
            Write-AppLog "LỖI: $($_.Exception.Message)"
            $status.Text = '● Không đổi được driver'
            $status.ForeColor = [Drawing.Color]::Firebrick
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                'Không đổi được driver CMP 40HX',
                'OK',
                'Error') | Out-Null
        }
        finally {
            $settingsButton.Enabled = $true
            $refreshButton.Enabled = $true
            if (-not $script:Simulation) { $confirm.Checked = $false }
            Refresh-UiState -KeepStatus
        }

        if ($operationSucceeded) {
            Animate-Progress -From 95 -To 100 -Message '● Hoàn tất chuyển driver'
            $status.Text = if ($script:Simulation) { "● Mô phỏng thành công: $profileName" } else { "● Đã chuyển sang $profileName - $($result.Device.Version)" }
            $status.ForeColor = $green
        }
    })

    Write-AppLog 'Đang nhận diện trạng thái driver hiện tại.'
    Refresh-UiState
    Write-AppLog 'Chuẩn bị hiển thị cửa sổ chính.'
    $dialogResult = $form.ShowDialog()
    Write-AppLog "Cửa sổ chính đã đóng: $dialogResult"
}

function Invoke-SimulationSelfTest {
    if (-not $script:Simulation) {
        throw 'SelfTest chỉ được phép chạy cùng -Simulation.'
    }

    function Assert-Simulation {
        param([bool]$Condition, [string]$Name)
        if ($Condition) {
            $script:SelfTestPassed++
            Write-Host "PASS: $Name"
        }
        else {
            $script:SelfTestFailed++
            Write-Host "FAIL: $Name"
        }
    }

    $script:SelfTestPassed = 0
    $script:SelfTestFailed = 0
    $script:SimulationProfile = 'Work'

    $config = New-DefaultConfig
    Save-Config -Config $config

    Assert-Simulation (Test-Path -LiteralPath $script:LauncherPath -PathType Leaf) 'Có launcher cho chế độ thật'
    Assert-Simulation ($script:HardwareId -eq 'PCI\VEN_10DE&DEV_1F0B') 'Đúng mã thiết bị CMP 40HX'

    Assert-Simulation (Test-Path -LiteralPath $config.WorkInf -PathType Leaf) 'Có INF mô phỏng cho GPU công suất tối đa'
    Assert-Simulation (Test-Path -LiteralPath $config.GameInf -PathType Leaf) 'Có INF mô phỏng cho GPU chơi LOL / Valorant'
    Assert-Simulation (Test-InfSupportsCmp40Hx -InfPath $config.WorkInf) 'INF GPU công suất tối đa chứa DEV_1F0B'
    Assert-Simulation (Test-InfContainsGameModel -InfPath $config.GameInf -ModelName $script:GameModel) 'INF mô phỏng game chứa model được chọn'

    $before = Get-CmpDeviceInfo
    Assert-Simulation ($before.PublishedName -eq 'oem-sim-work.inf') 'Trạng thái đầu là GPU công suất tối đa'

    $toGame = Install-CmpDriver -ProfileName 'LOL / Valorant' -InfPath $config.GameInf -InstallMode ForcedModel -ModelName $script:GameModel
    Assert-Simulation ($toGame.Simulation -and $toGame.Device.PublishedName -eq 'oem-sim-game.inf') 'Chuyển mô phỏng sang GPU chơi LOL / Valorant'
    Assert-Simulation (-not $toGame.RebootRequired) 'Mô phỏng không yêu cầu khởi động lại'

    $toWork = Install-CmpDriver -ProfileName 'GPU công suất tối đa' -InfPath $config.WorkInf -InstallMode Compatible
    Assert-Simulation ($toWork.Simulation -and $toWork.Device.PublishedName -eq 'oem-sim-work.inf') 'Chuyển mô phỏng về GPU công suất tối đa'

    $realOperations = Select-String -LiteralPath $script:LogPath -Pattern 'ForceInstall|pnputil|SetupDi|DiInstallDevice' -ErrorAction SilentlyContinue
    Assert-Simulation ($null -eq $realOperations) 'Nhật ký không chứa lời gọi cài driver thật'

    Write-Host "RESULT: $($script:SelfTestPassed) passed, $($script:SelfTestFailed) failed"
    return $script:SelfTestFailed
}

if ($ScanFolder) {
    try {
        $resolved = Resolve-DriverFolder -FolderPath $ScanFolder
        Write-Output "OK: $($resolved.InfPath) | DriverVer=$($resolved.Version)"
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}

if ($CheckOnly) {
    try {
        $device = Get-CmpDeviceInfo
        $currentInf = Get-DriverStoreInfPath -PublishedName $device.PublishedName
        if (-not $currentInf) {
            throw "Không tìm thấy INF hiện tại cho $($device.PublishedName)."
        }
        Write-Output "OK: $($device.Description) | $($device.PublishedName) | $($device.Version) | $($device.InstanceId) | $currentInf"
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}

if ($ValidateGameInf) {
    try {
        $device = Get-CmpDeviceInfo
        $fullPath = [IO.Path]::GetFullPath($ValidateGameInf)
        $savedConfig = Get-Config
        $script:GameModel = [string]$savedConfig.GameModel
        if ((Test-InfSupportsCmp40Hx -InfPath $fullPath)) {
            Write-Output "OK: INF có DEV_1F0B | $fullPath"
            exit 0
        }
        if ($script:Simulation) {
            $containsModel = Test-InfContainsGameModel -InfPath $fullPath -ModelName $script:GameModel
        }
        else {
            Initialize-ForcedModelDriverApi
            $containsModel = [Cmp40Hx.ForcedModelDriverApi]::ContainsModel($device.InstanceId, $fullPath, $script:GameModel)
        }
        if (-not $containsModel) {
            throw "Không tìm thấy model $($script:GameModel) trong INF."
        }
        Write-Output "OK: $($script:GameModel) | $fullPath | $($device.InstanceId)"
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}

if ($SelfTest) {
    try {
        $failureCount = Invoke-SimulationSelfTest
        if ($failureCount -gt 0) { exit 1 }
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}

if (-not $script:Simulation -and -not (Test-IsAdministrator)) {
    Start-ElevatedCopy
    exit
}

try {
    Write-AppLog "Khởi động CMP40HX-DriverToggle v$($script:Version). Simulation=$($script:Simulation)"
    Start-Gui
}
catch {
    Write-AppLog "LỖI KHỞI ĐỘNG: $($_.Exception.Message)"
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'CMP40HX-DriverToggle', 'OK', 'Error') | Out-Null
    exit 1
}
