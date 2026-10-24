# ============================================
# Test the SSH audit package on Linux
# ============================================

$packagePath = "/home/$env:USER/MachineConfiguration/AuditSshService.zip"

try {
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "The audit package was not found: $packagePath"
    }

    Write-Host "Checking the current SSH service state..." -ForegroundColor Cyan

    systemctl status ssh --no-pager

    Write-Host "Testing the Machine Configuration audit package..." -ForegroundColor Cyan

    $auditResult = Get-GuestConfigurationPackageComplianceStatus `
        -Path $packagePath `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "Audit result:" -ForegroundColor Cyan

    $auditResult | Format-List *

    Write-Host ""
    Write-Host "Resource details:" -ForegroundColor Cyan

    $auditResult.resources | Format-List *
}
catch {
    Write-Host "The audit package test failed." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}