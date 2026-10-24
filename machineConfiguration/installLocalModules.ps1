# ============================================
# Check PowerShell Environment
# ============================================
Write-Host "Checking PowerShell version and platform:" -ForegroundColor Cyan

$PSVersionTable |
    Select-Object PSVersion, PSEdition, Platform |
    Format-Table -AutoSize

# ============================================
# Ensure NuGet provider is ready (prevents hangs)
# ============================================
$null = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NuGet provider..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}

# ============================================
# Install Machine Configuration authoring tools
# ============================================
Write-Host ""
Write-Host "Installing modules (GuestConfiguration, PSDscResources)..." -ForegroundColor Cyan

$modulesToInstall = @(
    @{ Name = "GuestConfiguration"; Scope = "CurrentUser" },
    @{ Name = "PSDesiredStateConfiguration"; RequiredVersion = "2.0.7"; Scope = "CurrentUser" },
    @{ Name = "PSDscResources"; Scope = "CurrentUser" }
)

foreach ($mod in $modulesToInstall) {
    if (-not (Get-Module -ListAvailable -Name $mod.Name)) {
        Write-Host "Installing module: $($mod.Name)..." -ForegroundColor Yellow
        Install-Module @mod -Force -AllowClobber -Scope CurrentUser
    } else {
        Write-Host "Module $($mod.Name) is already installed." -ForegroundColor Green
    }
}

# ============================================
# Import Modules
# ============================================
Write-Host ""
Write-Host "Importing modules..." -ForegroundColor Cyan

Import-Module GuestConfiguration -Force
Import-Module PSDesiredStateConfiguration -RequiredVersion 2.0.7 -Force

# ============================================
# Verification
# ============================================
Write-Host ""
Write-Host "Verifying available commands in GuestConfiguration:" -ForegroundColor Cyan
Get-Command -Module GuestConfiguration | Select-Object Name, CommandType | Format-Table -AutoSize

Write-Host "Complete!" -ForegroundColor Green
Write-Host ""