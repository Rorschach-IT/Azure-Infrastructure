# ============================================
# Publish an existing IIS audit policy definition
# with a package URL from Azure Blob Storage
# Run locally in PowerShell 7
# ============================================

Clear-Host

# ============================================
# Check Azure login and subscription context
# ============================================

try {
    Write-Host "Checking Azure login and subscription context..." -ForegroundColor Cyan

    $context = Get-AzContext

    if (-not $context) {
        Write-Host "No active Azure session was found." -ForegroundColor Yellow
        Write-Host "Starting Azure sign-in..." -ForegroundColor Cyan

        Connect-AzAccount -ErrorAction Stop | Out-Null
        $context = Get-AzContext
    }

    if (-not $context -or -not $context.Subscription.Id) {
        throw "No active Azure subscription was found."
    }

    Write-Host ""
    Write-Host "Current subscription:" -ForegroundColor Green
    Write-Host "Name: $($context.Subscription.Name)" -ForegroundColor White
    Write-Host "ID: $($context.Subscription.Id)" -ForegroundColor White
}
catch {
    Write-Host "Unable to establish the Azure session." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Select and validate a local JSON file
# ============================================

$policyFile = $null
$parsedJson = $null
$definitionProperties = $null

while ($null -eq $policyFile) {
    Write-Host ""
    $pathInput = Read-Host "Enter the path to the generated policy JSON file"

    if ([string]::IsNullOrWhiteSpace($pathInput)) {
        Write-Host "The file path cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $pathInput = $pathInput.Trim()

    # Remove matching surrounding quotation marks.
    if (
        $pathInput.Length -ge 2 -and
        (
            ($pathInput.StartsWith('"') -and $pathInput.EndsWith('"')) -or
            ($pathInput.StartsWith("'") -and $pathInput.EndsWith("'"))
        )
    ) {
        $pathInput = $pathInput.Substring(1, $pathInput.Length - 2)
    }

    try {
        $selectedFile = Get-Item `
            -LiteralPath $pathInput `
            -ErrorAction Stop

        if ($selectedFile.PSIsContainer) {
            throw "The selected path is a directory. Please select the JSON file inside it."
        }

        if ($selectedFile.Extension -ine ".json") {
            throw "The selected file must have a .json extension."
        }

        $candidateJson = Get-Content `
            -LiteralPath $selectedFile.FullName `
            -Raw `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($candidateJson)) {
            throw "The selected JSON file is empty."
        }

        $candidateObject = ConvertFrom-Json `
            -InputObject $candidateJson `
            -ErrorAction Stop

        if ($null -ne $candidateObject.properties) {
            $candidateProperties = $candidateObject.properties
        }
        else {
            $candidateProperties = $candidateObject
        }

        if ($null -eq $candidateProperties.policyRule) {
            throw "The JSON does not contain a policyRule."
        }

        $guestConfiguration = $candidateProperties.metadata.guestConfiguration

        if ($null -eq $guestConfiguration) {
            throw "Machine Configuration metadata was not found in the JSON."
        }

        if ([string]::IsNullOrWhiteSpace($guestConfiguration.contentUri)) {
            throw "The JSON does not contain a Machine Configuration contentUri."
        }

        if ([string]::IsNullOrWhiteSpace($guestConfiguration.contentHash)) {
            throw "The JSON does not contain a Machine Configuration contentHash."
        }

        $parsedJson = $candidateObject
        $definitionProperties = $candidateProperties
        $policyFile = $selectedFile.FullName

        Write-Host "The policy JSON file was loaded successfully." -ForegroundColor Green
        Write-Host "Selected file: $policyFile" -ForegroundColor White
    }
    catch {
        Write-Host "Unable to load the selected policy definition." -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please verify the file and try again." -ForegroundColor Yellow
    }
}

# ============================================
# Read the Blob package URL
# ============================================

$contentUri = $null

while ($null -eq $contentUri) {
    Write-Host ""
    $urlInput = Read-Host "Enter the HTTPS URL of the ZIP package in Blob Storage without a SAS token"

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
# Update matching package references in memory
# ============================================

function Update-PackageUri {
    param (
        [AllowNull()]
        [object]$Node,

        [Parameter(Mandatory)]
        [string]$OldUri,

        [Parameter(Mandatory)]
        [string]$NewUri
    )

    if ($null -eq $Node) {
        return
    }

    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Node.PSObject.Properties) {
            if (
                $property.Name -ieq "contentUri" -and
                $property.Value -is [string] -and
                $property.Value -ceq $OldUri
            ) {
                $property.Value = $NewUri
            }
            else {
                Update-PackageUri `
                    -Node $property.Value `
                    -OldUri $OldUri `
                    -NewUri $NewUri
            }
        }
    }
    elseif (
        $Node -is [System.Collections.IEnumerable] -and
        $Node -isnot [string]
    ) {
        foreach ($item in $Node) {
            Update-PackageUri `
                -Node $item `
                -OldUri $OldUri `
                -NewUri $NewUri
        }
    }
}

$oldContentUri = [string]$definitionProperties.metadata.guestConfiguration.contentUri

Update-PackageUri `
    -Node $parsedJson `
    -OldUri $oldContentUri `
    -NewUri $contentUri

$policyJson = ConvertTo-Json `
    -InputObject $parsedJson `
    -Depth 100 `
    -ErrorAction Stop

# ============================================
# Confirm publication
# ============================================

$policyName = "Audit-SSH-Service-Running"

Write-Host ""
Write-Host "Publication summary:" -ForegroundColor Cyan
Write-Host "Subscription: $($context.Subscription.Name)" -ForegroundColor White
Write-Host "Policy definition name: $policyName" -ForegroundColor White
Write-Host "JSON file: $policyFile" -ForegroundColor White
Write-Host "Package URL: $contentUri" -ForegroundColor White
Write-Host ""
Write-Host "The existing package hash and authentication settings will be preserved." -ForegroundColor Yellow
Write-Host "The Blob ZIP must be the exact package used to generate this JSON." -ForegroundColor Yellow
Write-Host "The original local JSON file will not be modified." -ForegroundColor Yellow
Write-Host "This operation does not upload the ZIP or assign the policy to a VM." -ForegroundColor Yellow
Write-Host "An existing policy definition with the same name may be updated." -ForegroundColor Yellow

$confirmation = $null

while ($confirmation -notin @("Y", "YES", "N", "NO")) {
    $confirmation = Read-Host "Type Y to publish or N to cancel"

    if ([string]::IsNullOrWhiteSpace($confirmation)) {
        Write-Host "The confirmation cannot be empty. Please type Y or N." -ForegroundColor Red
        continue
    }

    $confirmation = $confirmation.Trim()

    if ($confirmation -notin @("Y", "YES", "N", "NO")) {
        Write-Host "Invalid option. Please type Y or N." -ForegroundColor Red
    }
}

if ($confirmation -in @("N", "NO")) {
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    return
}

# ============================================
# Publish the updated JSON content
# ============================================

try {
    Write-Host ""
    Write-Host "Publishing the SSH audit policy definition..." -ForegroundColor Cyan

    $policyDefinition = New-AzPolicyDefinition `
        -Name $policyName `
        -Policy $policyJson `
        -ErrorAction Stop

    Write-Host "The SSH audit policy definition was published successfully." -ForegroundColor Green

    $policyDefinition |
        Format-List Name, DisplayName, ResourceId
}
catch {
    Write-Host ""
    Write-Host "Failed to publish the SSH audit policy definition." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}