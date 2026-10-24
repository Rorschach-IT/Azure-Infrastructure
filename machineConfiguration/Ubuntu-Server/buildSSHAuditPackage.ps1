# ============================================
# Build an audit-only package for the SSH service
# Run locally on Windows in PowerShell 7
# ============================================

Import-Module PSDesiredStateConfiguration `
    -ErrorAction Stop

Import-Module GuestConfiguration -ErrorAction Stop

# ============================================
# Make the local DSC module discoverable
# ============================================

$modulesPath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "Modules"

if ($env:PSModulePath -notlike "*$modulesPath*") {
    $env:PSModulePath = "$modulesPath;$env:PSModulePath"
}

# ============================================
# Create the custom Linux DSC resource module
# ============================================

$moduleRoot = Join-Path `
    -Path $modulesPath `
    -ChildPath "LinuxServiceAudit"

$modulePath = Join-Path `
    -Path $moduleRoot `
    -ChildPath "LinuxServiceAudit.psm1"

$manifestPath = Join-Path `
    -Path $moduleRoot `
    -ChildPath "LinuxServiceAudit.psd1"

New-Item `
    -Path $moduleRoot `
    -ItemType Directory `
    -Force | Out-Null

$moduleContent = @'
[DscResource()]
class LinuxServiceState {
    [DscProperty(Key)]
    [string]$ServiceName

    [DscProperty(Mandatory)]
    [string]$DesiredState

    [LinuxServiceState] Get() {
        $currentState = & systemctl is-active $this.ServiceName 2>$null

        $result = [LinuxServiceState]::new()
        $result.ServiceName = $this.ServiceName

        if ($currentState -eq "active") {
            $result.DesiredState = "active"
        }
        else {
            $result.DesiredState = "inactive"
        }

        return $result
    }

    [bool] Test() {
        $currentState = & systemctl is-active $this.ServiceName 2>$null
        return $currentState -eq $this.DesiredState
    }

    [void] Set() {
        & systemctl enable $this.ServiceName
        & systemctl restart $this.ServiceName
    }
}
'@

Set-Content `
    -LiteralPath $modulePath `
    -Value $moduleContent `
    -Encoding UTF8

$manifestContent = @'
@{
    RootModule = "LinuxServiceAudit.psm1"
    ModuleVersion = "1.0.0"
    GUID = "b7f4d9e2-8a51-4c67-9d23-6f0a1e8c4b77"
    Author = "Machine Configuration"
    Description = "Custom DSC resource for auditing and managing Linux services."
    PowerShellVersion = "7.0"
    DscResourcesToExport = @("LinuxServiceState")
}
'@

Set-Content `
    -LiteralPath $manifestPath `
    -Value $manifestContent `
    -Encoding UTF8

# ============================================
# Prepare artifact folders
# ============================================

$artifactsPath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "artifacts"

$compiledPath = Join-Path `
    -Path $artifactsPath `
    -ChildPath "compiled"

$packagePath = Join-Path `
    -Path $artifactsPath `
    -ChildPath "packages"

New-Item `
    -Path $compiledPath `
    -ItemType Directory `
    -Force | Out-Null

New-Item `
    -Path $packagePath `
    -ItemType Directory `
    -Force | Out-Null

# ============================================
# Compile the DSC configuration
# ============================================

$compileScript = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "compileSSHAuditConfiguration.ps1"

if (-not (Test-Path -LiteralPath $compileScript -PathType Leaf)) {
    Write-Host "The DSC compilation script was not found:" -ForegroundColor Red
    Write-Host $compileScript -ForegroundColor Red
    exit 1
}

Write-Host "Compiling the SSH service audit configuration..." -ForegroundColor Cyan

& $compileScript

# ============================================
# Create the Machine Configuration package
# ============================================

$sourceMof = Join-Path `
    -Path $compiledPath `
    -ChildPath "localhost.mof"

$packageMof = Join-Path `
    -Path $compiledPath `
    -ChildPath "AuditSshService.mof"

if (-not (Test-Path -LiteralPath $sourceMof -PathType Leaf)) {
    Write-Host "The compiled MOF file was not found: $sourceMof" -ForegroundColor Red
    exit 1
}

Copy-Item `
    -LiteralPath $sourceMof `
    -Destination $packageMof `
    -Force `
    -ErrorAction Stop

Write-Host "Creating an audit-only Machine Configuration package..." -ForegroundColor Cyan

$package = New-GuestConfigurationPackage `
    -Name "AuditSshService" `
    -Configuration $packageMof `
    -Path $packagePath `
    -Type Audit `
    -Force

Write-Host "The SSH audit package was created." -ForegroundColor Green

$package |
    Select-Object Name, Path |
    Format-List