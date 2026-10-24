# ============================================
# Build an audit-only package for the RDP service
# Run locally on Windows in PowerShell 7
# ============================================

Import-Module PSDesiredStateConfiguration `
    -RequiredVersion 2.0.7 `
    -ErrorAction Stop

Import-Module GuestConfiguration -ErrorAction Stop

Configuration AuditRDPAuditService {
    Import-DscResource `
        -ModuleName PSDscResources `
        -Name Service

    Node localhost {
        Service RDPAuditService {
            Name   = "TermService"
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

Write-Host "Compiling the RDP service audit configuration..." -ForegroundColor Cyan

AuditRDPAuditService -OutputPath $compiledPath | Out-Null

$sourceMof = Join-Path `
    -Path $compiledPath `
    -ChildPath "localhost.mof"

$packageMof = Join-Path `
    -Path $compiledPath `
    -ChildPath "AuditRDPAuditService.mof"

Copy-Item `
    -LiteralPath $sourceMof `
    -Destination $packageMof `
    -Force `
    -ErrorAction Stop

Write-Host "Creating an audit-only Machine Configuration package..." -ForegroundColor Cyan

$package = New-GuestConfigurationPackage `
    -Name "AuditRDPAuditService" `
    -Configuration $packageMof `
    -Path $packagePath `
    -Type AuditAndSet `
    -Force

Write-Host "The RDP audit package was created." -ForegroundColor Green

$package |
    Select-Object Name, Path |
    Format-List