#Requires -RunAsAdministrator
#Requires -Version 4.0

# GitHub requires TLS v1.2, but it's not enabled by default in PowerShell v5.0 and older releases
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

# Allow alternate base URL as first command-line argument, for testing and development
if ($args.Count -eq 0) {
    $BaseURL = "https://raw.githubusercontent.com/4xura/just-the-browser/main"
} else {
    $BaseURL = $args[0]
}

$OS = Get-CimInstance Win32_OperatingSystem
$MicrosoftEdgeInstallRegistry = "$BaseURL/edge/install.reg"
$MicrosoftEdgeUninstallRegistry = "$BaseURL/edge/uninstall.reg"
$GoogleChromeInstallRegistry = "$BaseURL/chrome/install.reg"
$GoogleChromeUninstallRegistry = "$BaseURL/chrome/uninstall.reg"
$FirefoxInstallRegistry = "$BaseURL/firefox/install.reg"
$FirefoxUninstallRegistry = "$BaseURL/firefox/uninstall.reg"
$BraveInstallRegistry = "$BaseURL/brave/install.reg"
$BraveUninstallRegistry = "$BaseURL/brave/uninstall.reg"

# Render initial interface for all pages
function Show-Header {
    Clear-Host
    Write-Host "`nJust the Browser ($($OS.Caption) Build $($OS.BuildNumber))`n========`n"
}

# Find installed Firefox release and Developer Edition directories
function Get-FirefoxInstallPaths {
    $Candidates = New-Object System.Collections.Generic.List[string]
    $InstallPaths = New-Object System.Collections.Generic.List[string]

    # Mozilla records release and Developer Edition under separate product keys.
    $MozillaRegistryPaths = @(
        "HKLM:\SOFTWARE\Mozilla\Mozilla Firefox",
        "HKLM:\SOFTWARE\Mozilla\Firefox Developer Edition",
        "HKLM:\SOFTWARE\WOW6432Node\Mozilla\Mozilla Firefox",
        "HKLM:\SOFTWARE\WOW6432Node\Mozilla\Firefox Developer Edition",
        "HKCU:\SOFTWARE\Mozilla\Mozilla Firefox",
        "HKCU:\SOFTWARE\Mozilla\Firefox Developer Edition"
    )
    foreach ($RegistryPath in $MozillaRegistryPaths) {
        if (Test-Path -LiteralPath $RegistryPath) {
            $Version = (Get-ItemProperty -LiteralPath $RegistryPath -ErrorAction SilentlyContinue).CurrentVersion
            if ($Version) {
                $MainRegistryPath = "$RegistryPath\$Version\Main"
                $InstallDirectory = (Get-ItemProperty -LiteralPath $MainRegistryPath -ErrorAction SilentlyContinue)."Install Directory"
                if ($InstallDirectory) {
                    $Candidates.Add($InstallDirectory)
                }
            }
        }
    }

    # Also check uninstall entries, which can contain custom installation paths.
    $UninstallRegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($RegistryPath in $UninstallRegistryPaths) {
        Get-ChildItem -LiteralPath $RegistryPath -ErrorAction SilentlyContinue | ForEach-Object {
            $Application = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if (($Application.DisplayName -like "*Firefox*") -and $Application.InstallLocation) {
                $Candidates.Add($Application.InstallLocation)
            }
        }
    }

    # Include the default directories in case registry registration is missing.
    $ProgramDirectories = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432)
    foreach ($ProgramDirectory in $ProgramDirectories) {
        if ($ProgramDirectory) {
            $Candidates.Add((Join-Path $ProgramDirectory "Mozilla Firefox"))
            $Candidates.Add((Join-Path $ProgramDirectory "Firefox Developer Edition"))
        }
    }

    # Only return real Firefox directories, without case-insensitive duplicates.
    $SeenPaths = @{}
    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path -LiteralPath (Join-Path $Candidate "firefox.exe") -PathType Leaf)) {
            $InstallPath = (Get-Item -LiteralPath $Candidate).FullName
            if (-not $SeenPaths.ContainsKey($InstallPath)) {
                $SeenPaths[$InstallPath] = $true
                $InstallPaths.Add($InstallPath)
            }
        }
    }
    Return $InstallPaths.ToArray()
}

# Find per-installation policy files without modifying files owned by the user or another tool
function Get-FirefoxJSONPolicyFiles {
    Param(
        [Parameter(Position = 0)]
        [String[]]$InstallPaths
    )
    foreach ($InstallPath in $InstallPaths) {
        $PolicyPath = Join-Path $InstallPath "distribution\policies.json"
        if (Test-Path -LiteralPath $PolicyPath -PathType Leaf) {
            Write-Output $PolicyPath
        }
    }
}

# Install Google Chrome settings
function Install-Chrome {
    Show-Header
    Write-Host "Downloading registry file, please wait..."
    # Download file
    try {
        Invoke-WebRequest $GoogleChromeInstallRegistry -OutFile "$env:LocalAppData\chrome.reg"
    }
    catch {
        Read-Host -Prompt "Download failed! Press Enter/Return to continue" | Out-Null
        Return
    }
    # Install file
    $ChromeInstall = Start-Process "reg.exe" -ArgumentList "import `"$env:LocalAppData\chrome.reg`"" -WindowStyle Hidden -Wait -PassThru
    if ($ChromeInstall.ExitCode -eq 0) {
        Read-Host -Prompt "Updated Google Chrome settings. Press Enter/Return to continue" | Out-Null
    }
    else {
        Read-Host -Prompt "Install failed! Press Enter/Return to continue" | Out-Null
    }
}

# Remove Google Chrome settings
function Uninstall-Chrome {
    Show-Header
    Write-Host "Downloading registry file, please wait..."
    # Download file
    try {
        Invoke-WebRequest $GoogleChromeUninstallRegistry -OutFile "$env:LocalAppData\chrome.reg"
    }
    catch {
        Read-Host -Prompt "Download failed! Press Enter/Return to continue" | Out-Null
        Return
    }
    # Install file
    $ChromeUninstall = Start-Process "reg.exe" -ArgumentList "import `"$env:LocalAppData\chrome.reg`"" -WindowStyle Hidden -Wait -PassThru
    if ($ChromeUninstall.ExitCode -eq 0) {
        Read-Host -Prompt "Removed Google Chrome settings. Press Enter/Return to continue" | Out-Null
    }
    else {
        Read-Host -Prompt "Remove failed! Press Enter/Return to continue" | Out-Null
    }
}

# Install Microsoft Edge settings
function Install-Edge {
    Show-Header
    Write-Host "Downloading registry file, please wait..."
    # Download file
    try {
        Invoke-WebRequest $MicrosoftEdgeInstallRegistry -OutFile "$env:LocalAppData\edge.reg"
    }
    catch {
        Read-Host -Prompt "Download failed! Press Enter/Return to continue" | Out-Null
        Return
    }
    # Install file
    $EdgeInstall = Start-Process "reg.exe" -ArgumentList "import `"$env:LocalAppData\edge.reg`"" -WindowStyle Hidden -Wait -PassThru
    if ($EdgeInstall.ExitCode -eq 0) {
        Read-Host -Prompt "Updated Microsoft Edge settings. Press Enter/Return to continue" | Out-Null
    }
    else {
        Read-Host -Prompt "Install failed! Press Enter/Return to continue" | Out-Null
    }
}

# Remove Microsoft Edge settings
function Uninstall-Edge {
    Show-Header
    Write-Host "Downloading registry file, please wait..."
    # Download file
    try {
        Invoke-WebRequest $MicrosoftEdgeUninstallRegistry -OutFile "$env:LocalAppData\edge.reg"
    }
    catch {
        Read-Host -Prompt "Download failed! Press Enter/Return to continue" | Out-Null
        Return
    }
    # Install file
    $EdgeUninstall = Start-Process "reg.exe" -ArgumentList "import `"$env:LocalAppData\edge.reg`"" -WindowStyle Hidden -Wait -PassThru
    if ($EdgeUninstall.ExitCode -eq 0) {
        Read-Host -Prompt "Removed Microsoft Edge settings. Press Enter/Return to continue" | Out-Null
    }
    else {
        Read-Host -Prompt "Remove failed! Press Enter/Return to continue" | Out-Null
    }
}

# Install Brave settings
function Install-Brave {
    Show-Header
    Write-Host "Downloading registry file, please wait..."
    # Download file
    try {
        Invoke-WebRequest $BraveInstallRegistry -OutFile "$env:LocalAppData\brave.reg"
    }
    catch {
        Read-Host -Prompt "Download failed! Press Enter/Return to continue" | Out-Null
        Return
    }
    # Install file
    $BraveInstall = Start-Process "reg.exe" -ArgumentList "import `"$env:LocalAppData\brave.reg`"" -WindowStyle Hidden -Wait -PassThru
    if ($BraveInstall.ExitCode -eq 0) {
        Read-Host -Prompt "Updated Brave settings. Press Enter/Return to continue" | Out-Null
    }
    else {
        Read-Host -Prompt "Install failed! Press Enter/Return to continue" | Out-Null
    }
}

# Remove Brave settings
function Uninstall-Brave {
    Show-Header
    Write-Host "Downloading registry file, please wait..."
    # Download file
    try {
        Invoke-WebRequest $BraveUninstallRegistry -OutFile "$env:LocalAppData\brave.reg"
    }
    catch {
        Read-Host -Prompt "Download failed! Press Enter/Return to continue" | Out-Null
        Return
    }
    # Install file
    $BraveUninstall = Start-Process "reg.exe" -ArgumentList "import `"$env:LocalAppData\brave.reg`"" -WindowStyle Hidden -Wait -PassThru
    if ($BraveUninstall.ExitCode -eq 0) {
        Read-Host -Prompt "Removed Brave settings. Press Enter/Return to continue" | Out-Null
    }
    else {
        Read-Host -Prompt "Remove failed! Press Enter/Return to continue" | Out-Null
    }
}

# Install Firefox settings
function Install-Firefox {
    Param(
        [Parameter(Position = 0)]
        [String[]]$InstallPaths
    )
    Show-Header
    # Registry policies can coexist with per-installation JSON policies. Never overwrite or delete an existing file.
    $JSONPolicyFiles = @(Get-FirefoxJSONPolicyFiles $InstallPaths)
    if ($JSONPolicyFiles.Count -gt 0) {
        Write-Host "Existing Firefox policies.json file(s) found and left unchanged:"
        foreach ($PolicyFile in $JSONPolicyFiles) {
            Write-Host "  $PolicyFile"
        }
        Write-Host ""
    }
    # Download file
    Write-Host "Downloading registry file, please wait..."
    try {
        Invoke-WebRequest $FirefoxInstallRegistry -OutFile "$env:LocalAppData\firefox.reg"
    }
    catch {
        Read-Host -Prompt "Download failed! Press Enter/Return to continue" | Out-Null
        Return
    }
    # Install file
    $FirefoxInstall = Start-Process "reg.exe" -ArgumentList "import `"$env:LocalAppData\firefox.reg`"" -WindowStyle Hidden -Wait -PassThru
    if ($FirefoxInstall.ExitCode -eq 0) {
        Read-Host -Prompt "Updated Mozilla Firefox settings. Press Enter/Return to continue" | Out-Null
    }
    else {
        Read-Host -Prompt "Install failed! Press Enter/Return to continue" | Out-Null
    }
}

# Remove Firefox settings
function Uninstall-Firefox {
    Param(
        [Parameter(Position = 0)]
        [String[]]$InstallPaths
    )
    Show-Header
    # Download file
    try {
        Invoke-WebRequest $FirefoxUninstallRegistry -OutFile "$env:LocalAppData\firefox.reg"
    }
    catch {
        Read-Host -Prompt "Download failed! Press Enter/Return to continue" | Out-Null
        Return
    }
    # Install file
    $FirefoxUninstall = Start-Process "reg.exe" -ArgumentList "import `"$env:LocalAppData\firefox.reg`"" -WindowStyle Hidden -Wait -PassThru
    if ($FirefoxUninstall.ExitCode -eq 0) {
        $JSONPolicyFiles = @(Get-FirefoxJSONPolicyFiles $InstallPaths)
        if ($JSONPolicyFiles.Count -gt 0) {
            Write-Host "Removed the Just the Browser registry settings. These existing policy files were left unchanged:"
            foreach ($PolicyFile in $JSONPolicyFiles) {
                Write-Host "  $PolicyFile"
            }
            Write-Host "Firefox may still show policies from those files."
        }
        Read-Host -Prompt "Removed Mozilla Firefox registry settings. Press Enter/Return to continue" | Out-Null
    }
    else {
        Read-Host -Prompt "Remove failed! Press Enter/Return to continue" | Out-Null
    }
}


# Main menu selection
function Show-Menu {
    # Create list for menu options
    $options = New-Object System.Collections.Generic.List[psobject]
    # Google Chrome without settings applied
    $options.Add(@{
            Label  = "Google Chrome: Update settings"
            Action = { Install-Chrome }
        })
    # Google Chrome with settings applied
    if (Test-Path "HKLM:\SOFTWARE\Policies\Google\Chrome") {
        $GoogleChromeCheck = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -ErrorAction SilentlyContinue).AIModeSettings
        if ($null -ne $GoogleChromeCheck) {
            $options.Add(@{
                    Label  = "Google Chrome: Remove settings"
                    Action = { Uninstall-Chrome }
                })
        }
    }
    # Microsoft Edge without settings applied
    $options.Add(@{
            Label  = "Microsoft Edge: Update settings"
            Action = { Install-Edge }
        })
    # Microsoft Edge with settings applied
    if (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge") {
        $MicrosoftEdgeCheck = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -ErrorAction SilentlyContinue).HideFirstRunExperience
        if ($null -ne $MicrosoftEdgeCheck) {
            $options.Add(@{
                    Label  = "Microsoft Edge: Remove settings"
                    Action = { Uninstall-Edge }
                })
        }
    }
    # Brave without settings applied
    $options.Add(@{
            Label  = "Brave: Update settings"
            Action = { Install-Brave }
        })
    # Brave with settings applied
    if (Test-Path "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave") {
        $BraveCheck = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave" -ErrorAction SilentlyContinue).BraveAIChatEnabled
        if ($null -ne $BraveCheck) {
            $options.Add(@{
                    Label  = "Brave: Remove settings"
                    Action = { Uninstall-Brave }
                })
        }
    }
    # Mozilla Firefox release and Developer Edition
    $FirefoxPaths = @(Get-FirefoxInstallPaths)
    if ($FirefoxPaths.Count -gt 0) {
        $options.Add(@{
                Label  = "Mozilla Firefox: Update settings"
                Action = { Install-Firefox $FirefoxPaths }
            })
    }
    if (Test-Path "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\FirefoxHome") {
        $options.Add(@{
                Label  = "Mozilla Firefox: Remove settings"
                Action = { Uninstall-Firefox $FirefoxPaths }
            })
    }
    # Exit option
    $options.Add(@{
            Label = "Exit"; Action = { exit }
        })
    # Show main menu
    Show-Header
    Write-Host "Select an option by typing the number, then pressing Return/Enter on your keyboard to confirm.`n`nYou will need to restart your browser for changes to take effect.`n"
    for ($i = 0; $i -lt $options.Count; $i++) {
        Write-Host "[$($i + 1)] $($options[$i].Label)"
    }
    $selection = Read-Host "`n#"
    # Process menu selections
    if ($selection -match '^\d+$' -and $selection -le $options.Count) {
        $index = [int]$selection - 1
        & $options[$index].Action
        # Return to main menu after complete
        Show-Menu
    }
    else {
        Show-Menu
    }

}

Show-Menu
