# ============================================
# Install Apache2 and open HTTP on a Linux VM
# ============================================

Clear-Host

Write-Host "Checking Azure login and subscription context..." -ForegroundColor Cyan

if (-not (Get-AzContext)) {
    Connect-AzAccount | Out-Null
}

# ============================================
# Select Resource Group
# ============================================

Write-Host ""
Write-Host "Available Resource Groups:" -ForegroundColor Cyan

Get-AzResourceGroup |
    Sort-Object ResourceGroupName |
    Select-Object ResourceGroupName, Location |
    Format-Table -AutoSize

$resourceGroupName = $null

while ([string]::IsNullOrWhiteSpace($resourceGroupName)) {
    Write-Host ""
    $resourceGroupInput = Read-Host "Enter the Resource Group name"

    if ([string]::IsNullOrWhiteSpace($resourceGroupInput)) {
        Write-Host "Resource Group name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $resourceGroupInput = $resourceGroupInput.Trim()

    $resourceGroup = Get-AzResourceGroup `
        -Name $resourceGroupInput `
        -ErrorAction SilentlyContinue

    if ($null -eq $resourceGroup) {
        Write-Host "Resource Group '$resourceGroupInput' was not found. Please try again." -ForegroundColor Red
    }
    else {
        $resourceGroupName = $resourceGroup.ResourceGroupName
    }
}

Write-Host ""
Write-Host "Selected Resource Group: $resourceGroupName" -ForegroundColor Green

# ============================================
# Select Linux VM
# ============================================

$linuxVms = @(
    Get-AzVM -ResourceGroupName $resourceGroupName |
        Where-Object {
            $_.StorageProfile.OsDisk.OsType -eq "Linux"
        }
)

if ($linuxVms.Count -eq 0) {
    Write-Host "No Linux virtual machines were found in this Resource Group." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Available Linux virtual machines:" -ForegroundColor Cyan

$linuxVms |
    Select-Object Name, Location, ProvisioningState |
    Format-Table -AutoSize

$vm = $null

while ($null -eq $vm) {
    Write-Host ""
    $vmInput = Read-Host "Enter the Linux VM name"

    if ([string]::IsNullOrWhiteSpace($vmInput)) {
        Write-Host "Linux VM name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $vmInput = $vmInput.Trim()

    $vm = $linuxVms |
        Where-Object { $_.Name -ieq $vmInput } |
        Select-Object -First 1

    if ($null -eq $vm) {
        Write-Host "Linux VM '$vmInput' was not found. Please try again." -ForegroundColor Red
    }
}

$vmName = $vm.Name

Write-Host ""
Write-Host "Selected Linux VM: $vmName" -ForegroundColor Green

# ============================================
# Find NIC and NSG
# ============================================

$nicName = ($vm.NetworkProfile.NetworkInterfaces[0].Id -split "/")[-1]

$nic = Get-AzNetworkInterface `
    -ResourceGroupName $resourceGroupName `
    -Name $nicName `
    -ErrorAction Stop

if ($null -eq $nic.NetworkSecurityGroup) {
    Write-Host "No Network Security Group is attached directly to this VM network interface." -ForegroundColor Red
    Write-Host "Attach an NSG to the NIC before running this script." -ForegroundColor Yellow
    exit 1
}

$nsgName = ($nic.NetworkSecurityGroup.Id -split "/")[-1]

$nsg = Get-AzNetworkSecurityGroup `
    -ResourceGroupName $resourceGroupName `
    -Name $nsgName `
    -ErrorAction Stop

# ============================================
# Open HTTP in NSG
# ============================================

$httpRuleName = "Allow-HTTP-Internet"

try {
    $nsg = Get-AzNetworkSecurityGroup `
        -ResourceGroupName $resourceGroupName `
        -Name $nsgName `
        -ErrorAction Stop

    if ($nsg.SecurityRules.Name -contains $httpRuleName) {
        Write-Host "HTTP NSG rule already exists. Skipping rule creation." -ForegroundColor Yellow
    }
    else {
        $usedPriorities = @(
            $nsg.SecurityRules |
                Where-Object { $_.Direction -eq "Inbound" } |
                Select-Object -ExpandProperty Priority
        )

        $httpRulePriority = $null

        foreach ($candidatePriority in 1000..4096) {
            if ($usedPriorities -notcontains $candidatePriority) {
                $httpRulePriority = $candidatePriority
                break
            }
        }

        if ($null -eq $httpRulePriority) {
            throw "No free inbound priority was found between 1000 and 4096. Review the existing NSG rules."
        }

        Write-Host "Adding inbound HTTP rule to the Network Security Group..." -ForegroundColor Cyan
        Write-Host "Selected free priority: $httpRulePriority" -ForegroundColor White

        $nsg = Add-AzNetworkSecurityRuleConfig `
            -NetworkSecurityGroup $nsg `
            -Name $httpRuleName `
            -Description "Allow inbound HTTP traffic from the Internet" `
            -Access Allow `
            -Protocol Tcp `
            -Direction Inbound `
            -Priority $httpRulePriority `
            -SourceAddressPrefix "*" `
            -SourcePortRange "*" `
            -DestinationAddressPrefix "*" `
            -DestinationPortRange 80 `
            -ErrorAction Stop

        Set-AzNetworkSecurityGroup `
            -NetworkSecurityGroup $nsg `
            -ErrorAction Stop | Out-Null

        Write-Host "HTTP NSG rule was added successfully." -ForegroundColor Green
    }
}
catch {
    Write-Host "Failed to configure the HTTP rule in the Network Security Group." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Install Apache2
# ============================================

Write-Host ""
Write-Host "Installing Apache2 on virtual machine '$vmName'..." -ForegroundColor Cyan

$apacheInstallScript = @'
set -e
sudo apt-get update
sudo apt-get install -y apache2
sudo systemctl enable apache2
sudo systemctl restart apache2
echo "<h1>Hello from $(hostname)</h1>" | sudo tee /var/www/html/index.html
'@

try {
    Invoke-AzVMRunCommand `
        -ResourceGroupName $resourceGroupName `
        -VMName $vmName `
        -CommandId "RunShellScript" `
        -ScriptString $apacheInstallScript `
        -ErrorAction Stop | Out-Null

    Write-Host "Apache2 installation command completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Failed to install Apache2." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Display public HTTP address
# ============================================

$publicIpId = $nic.IpConfigurations[0].PublicIpAddress.Id

if ($publicIpId) {
    $publicIpName = ($publicIpId -split "/")[-1]

    $publicIp = Get-AzPublicIpAddress `
        -ResourceGroupName $resourceGroupName `
        -Name $publicIpName `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "Public IP address: $($publicIp.IpAddress)" -ForegroundColor Green
    Write-Host "HTTP address: http://$($publicIp.IpAddress)" -ForegroundColor Green
}
else {
    Write-Host "No public IP address is attached to this VM." -ForegroundColor Yellow
}