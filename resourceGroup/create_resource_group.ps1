# ============================================
# Create an Azure Resource Group
# ============================================

Clear-Host

Write-Host "Checking Azure login and subscription context..." -ForegroundColor Cyan

$context = Get-AzContext

if (-not $context) {
    Write-Host "No active Azure session was found." -ForegroundColor Red
    Write-Host "Starting Azure sign-in..." -ForegroundColor Yellow

    Connect-AzAccount | Out-Null
    $context = Get-AzContext
}

if (-not $context) {
    Write-Host "Unable to sign in to Azure. The script will now exit." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Current subscription:" -ForegroundColor Green
Write-Host "Name: $($context.Subscription.Name)" -ForegroundColor White
Write-Host "ID: $($context.Subscription.Id)" -ForegroundColor White
Write-Host "Tenant ID: $($context.Tenant.Id)" -ForegroundColor White

Write-Host ""
Write-Host "Available resource groups in the current subscription:" -ForegroundColor Cyan

Get-AzResourceGroup |
    Sort-Object ResourceGroupName |
    Select-Object ResourceGroupName, Location, ProvisioningState |
    Format-Table -AutoSize


# ============================================
# Repeat until the Resource Group is created
# ============================================

$resourceGroupCreated = $false

while (-not $resourceGroupCreated) {

    # ========================================
    # Ask for a unique Resource Group name
    # ========================================

    $resourceGroupName = $null
    $existingResourceGroup = $null

    while ($null -eq $resourceGroupName) {
        Write-Host ""
        $nameInput = Read-Host "Enter a new Resource Group name"

        if ([string]::IsNullOrWhiteSpace($nameInput)) {
            Write-Host "Resource Group name cannot be empty. Please try again." -ForegroundColor Red
            continue
        }

        Write-Host "Checking whether Resource Group '$nameInput' already exists..." -ForegroundColor Cyan

        $existingResourceGroup = Get-AzResourceGroup `
            -Name $nameInput `
            -ErrorAction SilentlyContinue

        if ($null -ne $existingResourceGroup) {
            Write-Host "Resource Group '$nameInput' already exists." -ForegroundColor Yellow
            Write-Host "Existing location: $($existingResourceGroup.Location)" -ForegroundColor White
            Write-Host "Please enter a different Resource Group name." -ForegroundColor Yellow
            continue
        }

        $resourceGroupName = $nameInput
        Write-Host "Resource Group name '$resourceGroupName' is available." -ForegroundColor Green
    }

    # ============================================
    # Retrieve available locations once
    # ============================================

    Write-Host ""
    Write-Host "Retrieving available Azure locations for the current subscription..." -ForegroundColor Cyan

    $availableLocations = @(Get-AzLocation | Sort-Object DisplayName)

    if ($availableLocations.Count -eq 0) {
        Write-Host "Unable to retrieve Azure locations. The script will now exit." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "Available Azure locations:" -ForegroundColor Green

    $availableLocations |
        Select-Object DisplayName, Location, GeographyGroup |
        Format-Table -AutoSize

    # ========================================
    # Ask for a valid Azure location
    # ========================================

    $selectedLocation = $null

    while ($null -eq $selectedLocation) {
        Write-Host ""
        $locationInput = Read-Host "Enter an Azure location"

        if ([string]::IsNullOrWhiteSpace($locationInput)) {
            Write-Host "Azure location cannot be empty. Please try again." -ForegroundColor Red
            continue
        }

        # The user can enter a location code, e.g. polandcentral,
        # or a display name, e.g. Poland Central.
        $selectedLocation = $availableLocations | Where-Object {
            $_.Location -ieq $locationInput -or
            $_.DisplayName -ieq $locationInput
        } | Select-Object -First 1

        if ($null -eq $selectedLocation) {
            Write-Host "Location '$locationInput' is not available in the current subscription." -ForegroundColor Red
            Write-Host "Please enter a location code or a display name." -ForegroundColor Yellow
        }
        else {
            Write-Host "Location validated successfully." -ForegroundColor Green
            Write-Host "Selected location: $($selectedLocation.DisplayName) ($($selectedLocation.Location))" -ForegroundColor White
        }
    }

    # ========================================
    # Confirm or restart the data entry
    # ========================================

    $validConfirmation = $false

    while (-not $validConfirmation) {
        Write-Host ""
        Write-Host "The following Resource Group will be created:" -ForegroundColor Cyan
        Write-Host "Name: $resourceGroupName" -ForegroundColor White
        Write-Host "Location: $($selectedLocation.DisplayName) ($($selectedLocation.Location))" -ForegroundColor White

        $confirmation = Read-Host "Type Y to create or N to enter data again"

        switch -Regex ($confirmation) {
            '^(Y|YES)$' {
                $validConfirmation = $true

                Write-Host ""
                Write-Host "Creating Resource Group '$resourceGroupName'..." -ForegroundColor Cyan

                try {
                    $newResourceGroup = New-AzResourceGroup `
                        -Name $resourceGroupName `
                        -Location $selectedLocation.Location `
                        -ErrorAction Stop

                    Write-Host "Resource Group was created successfully." -ForegroundColor Green

                    Write-Host ""
                    Write-Host "New Resource Group details:" -ForegroundColor Cyan

                    $newResourceGroup |
                        Select-Object `
                            ResourceGroupName,
                            Location,
                            ProvisioningState,
                            ResourceId |
                        Format-List

                    $resourceGroupCreated = $true
                }
                catch {
                    Write-Host "Failed to create Resource Group '$resourceGroupName'." -ForegroundColor Red
                    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "You can enter the data again." -ForegroundColor Yellow

                    $validConfirmation = $true
                }
            }

            '^(N|NO)$' {
                Write-Host "Please enter the Resource Group data again." -ForegroundColor Yellow
                $validConfirmation = $true
            }

            default {
                Write-Host "Invalid option. Please type Y, N, or Q." -ForegroundColor Red
            }
        }
    }
}