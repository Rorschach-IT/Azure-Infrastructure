# ============================================
# Create an Azure Virtual Machine
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

# ============================================
# Select an existing Resource Group
# ============================================

Write-Host ""
Write-Host "Available Resource Groups:" -ForegroundColor Cyan

$resourceGroups = @(Get-AzResourceGroup | Sort-Object ResourceGroupName)

if ($resourceGroups.Count -eq 0) {
    Write-Host "No Resource Groups were found in the current subscription." -ForegroundColor Red
    Write-Host "Create a Resource Group before creating a virtual machine." -ForegroundColor Yellow
    exit 1
}

$resourceGroups |
    Select-Object ResourceGroupName, Location, ProvisioningState |
    Format-Table -AutoSize

$resourceGroup = $null

while ($null -eq $resourceGroup) {
    Write-Host ""
    $resourceGroupInput = Read-Host "Enter the Resource Group name"

    if ([string]::IsNullOrWhiteSpace($resourceGroupInput)) {
        Write-Host "Resource Group name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $resourceGroup = Get-AzResourceGroup `
        -Name $resourceGroupInput `
        -ErrorAction SilentlyContinue

    if ($null -eq $resourceGroup) {
        Write-Host "Resource Group '$resourceGroupInput' was not found. Please try again." -ForegroundColor Red
    }
}

$resourceGroupName = $resourceGroup.ResourceGroupName
$location = $resourceGroup.Location

Write-Host ""
Write-Host "Selected Resource Group: $resourceGroupName" -ForegroundColor Green
Write-Host "Resource Group location: $location" -ForegroundColor White

# ============================================
# Select operating system
# ============================================

$operatingSystem = $null

Write-Host ""
Write-Host "Available operating systems:" -ForegroundColor Cyan
Write-Host "1 - Windows Server 2022" -ForegroundColor White
Write-Host "2 - Ubuntu Server 22.04 LTS" -ForegroundColor White

while ($null -eq $operatingSystem) {
    $osChoice = Read-Host "Select an operating system by number"

    switch ($osChoice) {
        "1" {
            $operatingSystem = "Windows"
            $image = "MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest"
        }

        "2" {
            $operatingSystem = "Linux"
            $image = "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest"
        }

        default {
            Write-Host "Invalid operating system selection. Please enter 1 or 2." -ForegroundColor Red
        }
    }
}

Write-Host "Selected operating system: $operatingSystem" -ForegroundColor Green
Write-Host "Selected image: $image" -ForegroundColor White

# ============================================
# Select a unique VM name
# ============================================

$vmName = $null

while ($null -eq $vmName) {
    Write-Host ""
    $vmNameInput = Read-Host "Enter a new virtual machine name"

    if ([string]::IsNullOrWhiteSpace($vmNameInput)) {
        Write-Host "Virtual machine name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $existingVm = Get-AzVM `
        -ResourceGroupName $resourceGroupName `
        -Name $vmNameInput `
        -ErrorAction SilentlyContinue

    if ($null -ne $existingVm) {
        Write-Host "Virtual machine '$vmNameInput' already exists in this Resource Group." -ForegroundColor Yellow
        Write-Host "Please enter a different virtual machine name." -ForegroundColor Yellow
        continue
    }

    $vmName = $vmNameInput
    Write-Host "Virtual machine name '$vmName' is available." -ForegroundColor Green
}

# ============================================
# Select VM size
# ============================================

$vmSize = $null

Write-Host ""
Write-Host "Available VM sizes in location '$location' are being retrieved..." -ForegroundColor Cyan

$availableVmSizes = @(
    Get-AzComputeResourceSku |
    Where-Object {
        $_.ResourceType -eq "virtualMachines" -and
        $_.Locations -contains $location -and
        $_.Restrictions.Count -eq 0
    } |
    Sort-Object Name
)

if ($availableVmSizes.Count -gt 0) {
    Write-Host "Sample available VM sizes:" -ForegroundColor Cyan

    $availableVmSizes |
        Select-Object -First 30 Name, Family, Size, Tier |
        Format-Table -AutoSize
}
else {
    Write-Host "Unable to retrieve VM sizes for location '$location'." -ForegroundColor Yellow
    Write-Host "You can still enter a VM size manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Recommended VM sizes:" -ForegroundColor Cyan
Write-Host "1 - Standard_B2s_v2" -ForegroundColor White
Write-Host "2 - Standard_D2s_v5" -ForegroundColor White
Write-Host "3 - Enter a custom VM size" -ForegroundColor White

while ($null -eq $vmSize) {
    $sizeChoice = Read-Host "Select a VM size by number"

    switch ($sizeChoice) {
        "1" {
            $vmSize = "Standard_B2s_v2"
        }

        "2" {
            $vmSize = "Standard_D2s_v5"
        }

        "3" {
            $customVmSize = Read-Host "Enter the Azure VM size name"

            if ([string]::IsNullOrWhiteSpace($customVmSize)) {
                Write-Host "VM size cannot be empty. Please try again." -ForegroundColor Red
            }
            elseif ($availableVmSizes.Count -gt 0 -and -not ($availableVmSizes.Name -contains $customVmSize)) {
                Write-Host "The size '$customVmSize' is not available in location '$location' or is invalid. Please try again." -ForegroundColor Red
            }
            else {
                $vmSize = $customVmSize
            }
        }

        default {
            Write-Host "Invalid VM size selection. Please try again." -ForegroundColor Red
        }
    }
}

Write-Host "Selected VM size: $vmSize" -ForegroundColor Green

# ============================================
# Select unique network resource names
# ============================================

Write-Host ""
Write-Host "Network configuration:" -ForegroundColor Cyan
Write-Host "The script will create a new Virtual Network, subnet, Network Security Group, and Public IP resource." -ForegroundColor DarkGray
Write-Host "The names entered below must not already exist in this Resource Group." -ForegroundColor DarkGray

# ============================================
# Select or Reuse a Virtual Network name
# ============================================

$vnetName = $null

while ($null -eq $vnetName) {
    Write-Host ""
    $vnetNameInput = Read-Host "Enter Virtual Network name (to create new or reuse existing)"

    if ([string]::IsNullOrWhiteSpace($vnetNameInput)) {
        Write-Host "Virtual Network name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    # Sprawdzamy, czy sieć już istnieje w grupie zasobów
    $existingVnet = Get-AzVirtualNetwork `
        -ResourceGroupName $resourceGroupName `
        -Name $vnetNameInput `
        -ErrorAction SilentlyContinue

    if ($null -ne $existingVnet) {
        # Sieć istnieje - możemy jej użyć ponownie!
        Write-Host "Virtual Network '$vnetNameInput' already exists. Reusing existing VNet." -ForegroundColor Green
        $vnetName = $vnetNameInput
    }
    else {
        # Sieć nie istnieje - nazwa jest wolna, zostanie utworzona nowa
        $vnetName = $vnetNameInput
        Write-Host "Virtual Network name '$vnetName' is available and will be created." -ForegroundColor Green
    }
}

# ============================================
# Select a unique subnet name
# ============================================

# The subnet does not exist yet because the VNet will be new.
# The name is still collected separately for clarity and future expansion.

$subnetName = $null

while ($null -eq $subnetName) {
    Write-Host ""
    $subnetNameInput = Read-Host "Enter a new subnet name"

    if ([string]::IsNullOrWhiteSpace($subnetNameInput)) {
        Write-Host "Subnet name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $subnetName = $subnetNameInput
    Write-Host "Subnet name '$subnetName' will be created inside Virtual Network '$vnetName'." -ForegroundColor Green
}

# ============================================
# Select a unique Network Security Group name
# ============================================

$nsgName = $null

while ($null -eq $nsgName) {
    Write-Host ""
    $nsgNameInput = Read-Host "Enter a new Network Security Group name"

    if ([string]::IsNullOrWhiteSpace($nsgNameInput)) {
        Write-Host "Network Security Group name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $existingNsg = Get-AzNetworkSecurityGroup `
        -ResourceGroupName $resourceGroupName `
        -Name $nsgNameInput `
        -ErrorAction SilentlyContinue

    if ($null -ne $existingNsg) {
        Write-Host "Network Security Group '$nsgNameInput' already exists in this Resource Group." -ForegroundColor Yellow
        Write-Host "Please enter a different Network Security Group name." -ForegroundColor Yellow
        continue
    }

    $nsgName = $nsgNameInput
    Write-Host "Network Security Group name '$nsgName' is available." -ForegroundColor Green
}

# ============================================
# Select a unique Public IP resource name
# ============================================

$publicIpName = $null

while ($null -eq $publicIpName) {
    Write-Host ""
    $publicIpNameInput = Read-Host "Enter a new Public IP resource name"

    if ([string]::IsNullOrWhiteSpace($publicIpNameInput)) {
        Write-Host "Public IP resource name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $existingPublicIp = Get-AzPublicIpAddress `
        -ResourceGroupName $resourceGroupName `
        -Name $publicIpNameInput `
        -ErrorAction SilentlyContinue

    if ($null -ne $existingPublicIp) {
        Write-Host "Public IP resource '$publicIpNameInput' already exists in this Resource Group." -ForegroundColor Yellow
        Write-Host "Please enter a different Public IP resource name." -ForegroundColor Yellow
        continue
    }

    $publicIpName = $publicIpNameInput
    Write-Host "Public IP resource name '$publicIpName' is available." -ForegroundColor Green
}

# ============================================
# Define network address prefixes
# ============================================

# These address ranges are used only for the newly created VNet.
# Change them if they overlap with another connected network.

$addressPrefix = "10.10.0.0/16"
$subnetAddressPrefix = "10.10.0.0/24"

Write-Host ""
Write-Host "New Virtual Network address space: $addressPrefix" -ForegroundColor White
Write-Host "New subnet address range: $subnetAddressPrefix" -ForegroundColor White

# ============================================
# Request administrator credentials
# ============================================

Write-Host ""
Write-Host "Enter local administrator credentials for the virtual machine." -ForegroundColor Cyan
Write-Host "Do not store credentials in this script or in a public repository." -ForegroundColor Yellow

$credential = $null

while (
    $null -eq $credential -or
    [string]::IsNullOrWhiteSpace($credential.UserName) -or
    [string]::IsNullOrWhiteSpace($credential.GetNetworkCredential().Password)
) {
    $credential = Get-Credential `
        -Message "Enter local administrator credentials for '$vmName'"

    if ($null -eq $credential) {
        Write-Host "Credentials were not provided. Please try again." -ForegroundColor Red
        continue
    }

    if (
        [string]::IsNullOrWhiteSpace($credential.UserName) -or
        [string]::IsNullOrWhiteSpace($credential.GetNetworkCredential().Password)
    ) {
        Write-Host "Username and password cannot be empty. Please try again." -ForegroundColor Red
        $credential = $null
    }
}

# ============================================
# Confirm VM creation
# ============================================

Write-Host ""
Write-Host "---------------------------------------------" -ForegroundColor DarkGray
Write-Host "The following resources will be created:" -ForegroundColor Cyan

Write-Host "Resource Group: " -ForegroundColor White -NoNewline; Write-Host "$resourceGroupName" -ForegroundColor Yellow
Write-Host "Location: " -ForegroundColor White -NoNewline; Write-Host "$location" -ForegroundColor Yellow
Write-Host "VM name: " -ForegroundColor White -NoNewline; Write-Host "$vmName" -ForegroundColor Yellow
Write-Host "Operating system: " -ForegroundColor White -NoNewline; Write-Host "$operatingSystem" -ForegroundColor Yellow
Write-Host "Image: " -ForegroundColor White -NoNewline; Write-Host "$image" -ForegroundColor Yellow
Write-Host "VM size: " -ForegroundColor White -NoNewline; Write-Host "$vmSize" -ForegroundColor Yellow
Write-Host "Virtual Network: " -ForegroundColor White -NoNewline; Write-Host "$vnetName" -ForegroundColor Yellow
Write-Host "Virtual Network address space: " -ForegroundColor White -NoNewline; Write-Host "$addressPrefix" -ForegroundColor Yellow
Write-Host "Subnet: " -ForegroundColor White -NoNewline; Write-Host "$subnetName" -ForegroundColor Yellow
Write-Host "Subnet address prefix: " -ForegroundColor White -NoNewline; Write-Host "$subnetAddressPrefix" -ForegroundColor Yellow
Write-Host "Network Security Group: " -ForegroundColor White -NoNewline; Write-Host "$nsgName" -ForegroundColor Yellow
Write-Host "Public IP resource: " -ForegroundColor White -NoNewline; Write-Host "$publicIpName" -ForegroundColor Yellow
Write-Host "---------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$confirmation = Read-Host "Type Y to create the VM or N to cancel"

if ($confirmation -notmatch '^(Y|YES)$') {
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    exit 0
}

# ============================================
# Create VM and network resources
# ============================================

try {
    Write-Host ""
    Write-Host "Creating virtual machine '$vmName'. This may take several minutes..." -ForegroundColor Cyan

    New-AzVM `
        -ResourceGroupName $resourceGroupName `
        -Location $location `
        -Name $vmName `
        -Image $image `
        -Size $vmSize `
        -Credential $credential `
        -VirtualNetworkName $vnetName `
        -AddressPrefix $addressPrefix `
        -SubnetName $subnetName `
        -SubnetAddressPrefix $subnetAddressPrefix `
        -SecurityGroupName $nsgName `
        -PublicIpAddressName $publicIpName `
        -ErrorAction Stop | Out-Null

    Write-Host "Virtual machine and network resources were created successfully." -ForegroundColor Green
}
catch {
    Write-Host "Failed to create virtual machine '$vmName'." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Display VM status and public IP
# ============================================

$vmStatus = Get-AzVM `
    -ResourceGroupName $resourceGroupName `
    -Name $vmName `
    -Status `
    -ErrorAction Stop

$publicIp = Get-AzPublicIpAddress `
    -ResourceGroupName $resourceGroupName `
    -Name $publicIpName `
    -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Final VM status:" -ForegroundColor Cyan

$vmStatus.Statuses |
    Select-Object Code, DisplayStatus |
    Format-Table -AutoSize

if ($publicIp -and $publicIp.IpAddress) {
    Write-Host "Public IP address: $($publicIp.IpAddress)" -ForegroundColor Green

    if ($operatingSystem -eq "Windows") {
        Write-Host "RDP command: mstsc /v:$($publicIp.IpAddress)" -ForegroundColor Green
    }
    else {
        Write-Host "SSH command: ssh $($credential.UserName)@$($publicIp.IpAddress)" -ForegroundColor Green
    }
}
else {
    Write-Host "Public IP address is not available yet. Please wait and run the check again." -ForegroundColor Yellow
}