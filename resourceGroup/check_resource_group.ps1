# ============================================
# Connect to and display an Azure Resource Group and its resources
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
# Ask for an existing Resource Group in a loop
# ============================================

$resourceGroup = $null
$resourceGroupName = $null

while ($null -eq $resourceGroup) {
    Write-Host ""
    $resourceGroupName = Read-Host "Enter the Resource Group name"

    if ([string]::IsNullOrWhiteSpace($resourceGroupName)) {
        Write-Host "Resource Group name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    Write-Host "Searching for Resource Group '$resourceGroupName'..." -ForegroundColor Cyan

    $resourceGroup = Get-AzResourceGroup `
        -Name $resourceGroupName `
        -ErrorAction SilentlyContinue

    if ($null -eq $resourceGroup) {
        Write-Host "Resource Group '$resourceGroupName' was not found in the current subscription." -ForegroundColor Red
        Write-Host "Please verify the Resource Group name and try again." -ForegroundColor Yellow
    }
}

# ============================================
# Display selected Resource Group details
# ============================================

Write-Host ""
Write-Host "Resource Group '$resourceGroupName' was found successfully." -ForegroundColor Green

Write-Host ""
Write-Host "Resource Group details:" -ForegroundColor Cyan

$resourceGroup |
    Select-Object `
        ResourceGroupName,
        Location,
        ProvisioningState,
        ResourceId,
        Tags |
    Format-List

Write-Host ""
Write-Host "Resources in Resource Group '$resourceGroupName':" -ForegroundColor Cyan

$resources = @(Get-AzResource `
    -ResourceGroupName $resourceGroupName |
    Sort-Object ResourceType, Name)

if ($resources.Count -eq 0) {
    Write-Host "No resources were found in this Resource Group." -ForegroundColor Yellow
}
else {
    $resources |
        Select-Object `
            Name,
            ResourceType,
            Location,
            ProvisioningState |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "Total resources found: $($resources.Count)" -ForegroundColor Green
}