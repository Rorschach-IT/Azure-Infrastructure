# ============================================
# Open RDP only from the current public IP
# ============================================

# Disclaimer:
# The official MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest image has RDP automatically enabled at the OS level when deployed as a virtual machine in the Microsoft Azure cloud. This script is for testing purposes, it is optional during implementation.

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
    $inputResourceGroup = Read-Host "Enter the Resource Group name"

    if ([string]::IsNullOrWhiteSpace($inputResourceGroup)) {
        Write-Host "Resource Group name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $inputResourceGroup = $inputResourceGroup.Trim()

    $resourceGroup = Get-AzResourceGroup `
        -Name $inputResourceGroup `
        -ErrorAction SilentlyContinue

    if ($null -eq $resourceGroup) {
        Write-Host "Resource Group '$inputResourceGroup' was not found. Please try again." -ForegroundColor Red
    }
    else {
        $resourceGroupName = $resourceGroup.ResourceGroupName
    }
}

Write-Host ""
Write-Host "Selected Resource Group: $resourceGroupName" -ForegroundColor Green

# ============================================
# Select Windows VM
# ============================================

$windowsVms = @(
    Get-AzVM -ResourceGroupName $resourceGroupName |
        Where-Object {
            $_.StorageProfile.OsDisk.OsType -eq "Windows"
        }
)

if ($windowsVms.Count -eq 0) {
    Write-Host "No Windows virtual machines were found in this Resource Group." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Available Windows virtual machines:" -ForegroundColor Cyan

$windowsVms |
    Select-Object Name, Location |
    Format-Table -AutoSize

$vm = $null

while ($null -eq $vm) {
    Write-Host ""
    $vmInput = Read-Host "Enter the Windows VM name"

    if ([string]::IsNullOrWhiteSpace($vmInput)) {
        Write-Host "Windows VM name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

    $vmInput = $vmInput.Trim()

    $vm = $windowsVms |
        Where-Object { $_.Name -ieq $vmInput } |
        Select-Object -First 1

    if ($null -eq $vm) {
        Write-Host "Windows VM '$vmInput' was not found. Please try again." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Selected Windows VM: $($vm.Name)" -ForegroundColor Green

# ============================================
# Detect local public IP address
# ============================================

Write-Host ""
Write-Host "Detecting the current public IP address..." -ForegroundColor Cyan

try {
    $myPublicIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
    $myPublicIpCidr = "$myPublicIp/32"

    Write-Host "Detected source IP: $myPublicIpCidr" -ForegroundColor Green
}
catch {
    Write-Host "Unable to detect the current public IP address." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

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
    exit 1
}

$nsgName = ($nic.NetworkSecurityGroup.Id -split "/")[-1]

$nsg = Get-AzNetworkSecurityGroup `
    -ResourceGroupName $resourceGroupName `
    -Name $nsgName `
    -ErrorAction Stop

# ============================================
# Add RDP rule
# ============================================

$rdpRuleName = "Allow-RDP-From-My-Public-IP"

if ($nsg.SecurityRules.Name -contains $rdpRuleName) {
    Write-Host "RDP NSG rule already exists. Skipping rule creation." -ForegroundColor Yellow
}
else {
    Write-Host "Adding RDP rule to the Network Security Group..." -ForegroundColor Cyan

    $nsg | Add-AzNetworkSecurityRuleConfig `
        -Name $rdpRuleName `
        -Description "Allow RDP only from the current public IP address" `
        -Access Allow `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 1010 `
        -SourceAddressPrefix $myPublicIpCidr `
        -SourcePortRange "*" `
        -DestinationAddressPrefix "*" `
        -DestinationPortRange 3389

    Set-AzNetworkSecurityGroup `
        -NetworkSecurityGroup $nsg `
        -ErrorAction Stop | Out-Null

    Write-Host "RDP NSG rule was added successfully." -ForegroundColor Green
}

# ============================================
# Display RDP connection command
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
    Write-Host "RDP command: mstsc /v:$($publicIp.IpAddress)" -ForegroundColor Green
}
else {
    Write-Host "No public IP address is attached to this VM." -ForegroundColor Yellow
}