# ============================================
# Build an audit-only package for the IIS service
# Run on Windows in PowerShell 7
# ============================================

Import-Module PSDesiredStateConfiguration `
    -RequiredVersion 2.0.7 `
    -ErrorAction Stop

Import-Module GuestConfiguration -ErrorAction Stop

Configuration AuditIISService {
    Import-DscResource `
        -ModuleName PSDscResources `
        -Name Service

    Node localhost {
        Service IISService {
            Name   = "W3SVC"
            Ensure = "Present"
            State  = "Running"
        }
    }
}

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

Write-Host "Compiling the IIS service audit configuration..." -ForegroundColor Cyan

AuditIISService -OutputPath $compiledPath | Out-Null

$sourceMof = Join-Path `
    -Path $compiledPath `
    -ChildPath "localhost.mof"

$packageMof = Join-Path `
    -Path $compiledPath `
    -ChildPath "AuditIISService.mof"

Copy-Item `
    -LiteralPath $sourceMof `
    -Destination $packageMof `
    -Force `
    -ErrorAction Stop

Write-Host "Creating an audit-only Machine Configuration package..." -ForegroundColor Cyan

$package = New-GuestConfigurationPackage `
    -Name "AuditIISService" `
    -Configuration $packageMof `
    -Path $packagePath `
    -Type Audit `
    -Force

Write-Host "The audit package was created." -ForegroundColor Green

$package |
    Select-Object Name, Path |
    Format-List