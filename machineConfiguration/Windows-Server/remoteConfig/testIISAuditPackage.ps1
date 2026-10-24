# ============================================
# Test the IIS audit package on Windows-Server
# ============================================

$packagePath = "C:\MachineConfiguration\AuditIISService.zip"

try {
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "The audit package was not found: $packagePath"
    }

    Write-Host "Checking the current IIS service state..." -ForegroundColor Cyan

    Get-Service `
        -Name W3SVC `
        -ErrorAction SilentlyContinue |
        Select-Object Name, DisplayName, Status |
        Format-Table -AutoSize

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