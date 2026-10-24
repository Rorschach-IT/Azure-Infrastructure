# ============================================
# Generate an RDP audit + autocorrect policy JSON
# Run locally on Windows in PowerShell 7
# ============================================

Import-Module GuestConfiguration -ErrorAction Stop

$packagePath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "artifacts\packages\AuditRDPAuditService.zip"

$outputPath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "artifacts\policies"

New-Item `
    -Path $outputPath `
    -ItemType Directory `
    -Force | Out-Null

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    Write-Host "The package was not found: $packagePath" -ForegroundColor Red
    Write-Host "Run buildRDPAuditPackage.ps1 first." -ForegroundColor Yellow
    exit 1
}

# ============================================
# Read the real Blob Storage package URL
# ============================================

$contentUri = $null

while ($null -eq $contentUri) {
    Write-Host ""
    $urlInput = Read-Host "Enter the HTTPS URL of the uploaded RDP ZIP package in Blob Storage without a SAS token"

    if ([string]::IsNullOrWhiteSpace($urlInput)) {
        Write-Host "The package URL cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $parsedUri = $null

    $validUri = [Uri]::TryCreate(
        $urlInput.Trim(),
        [UriKind]::Absolute,
        [ref]$parsedUri
    )

    if (
        -not $validUri -or
        $parsedUri.Scheme -ne "https" -or
        -not [string]::IsNullOrEmpty($parsedUri.Query) -or
        -not [string]::IsNullOrEmpty($parsedUri.Fragment) -or
        -not $parsedUri.AbsolutePath.EndsWith(
            ".zip",
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        Write-Host "Enter a valid HTTPS ZIP URL without query parameters or fragments." -ForegroundColor Red
        continue
    }

    $contentUri = $parsedUri.AbsoluteUri
}

# ============================================
# Generate the policy JSON
# ============================================

$PolicyConfig = @{
    PolicyId      = [Guid]::NewGuid()
    ContentUri    = $contentUri
    DisplayName   = "Ensure the RDP service is running on Windows Server"
    Description   = "Ensures that the Remote Desktop Services service is running on Windows virtual machines."
    Path          = $outputPath
    Platform      = "Windows"
    PolicyVersion = "1.0.0"
}

Write-Host "Generating the RDP ApplyAndAutoCorrect policy JSON..." -ForegroundColor Cyan

New-GuestConfigurationPolicy `
    @PolicyConfig `
    -Mode ApplyAndAutoCorrect

Write-Host "The RDP policy JSON was generated." -ForegroundColor Green

Get-ChildItem `
    -LiteralPath $outputPath `
    -Filter "*.json" |
    Select-Object Name, FullName |
    Format-List