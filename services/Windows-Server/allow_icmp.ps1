# ============================================
# Allow ICMP ping from the current public IP
# on a Windows VM
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

$vmName = $vm.Name

Write-Host ""
Write-Host "Selected Windows VM: $vmName" -ForegroundColor Green

# ============================================
# Detect source public IP
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
# Add ICMP rule to NSG
# ============================================

$icmpRuleName = "Allow-ICMP-From-My-Public-IP"

if ($nsg.SecurityRules.Name -contains $icmpRuleName) {
    Write-Host "ICMP NSG rule already exists. Skipping rule creation." -ForegroundColor Yellow
}
else {
    Write-Host "Adding ICMP rule to the Network Security Group..." -ForegroundColor Cyan

    $nsg | Add-AzNetworkSecurityRuleConfig `
        -Name $icmpRuleName `
        -Description "Allow ICMP only from the current public IP address" `
        -Access Allow `
        -Protocol Icmp `
        -Direction Inbound `
        -Priority 1020 `
        -SourceAddressPrefix $myPublicIpCidr `
        -SourcePortRange "*" `
        -DestinationAddressPrefix "*" `
        -DestinationPortRange "*"

    Set-AzNetworkSecurityGroup `
        -NetworkSecurityGroup $nsg `
        -ErrorAction Stop | Out-Null

    Write-Host "ICMP NSG rule was added successfully." -ForegroundColor Green
}

# ============================================
# Allow ICMP in Windows Firewall
# ============================================

Write-Host ""
Write-Host "Allowing ICMP echo requests in Windows Firewall..." -ForegroundColor Cyan

$windowsFirewallScript = @'
$ruleName = "Allow ICMPv4 Echo Request"
Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
New-NetFirewallRule `
    -DisplayName $ruleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol ICMPv4 `
    -IcmpType 8 `
    -Profile Any
'@

try {
    Invoke-AzVMRunCommand `
        -ResourceGroupName $resourceGroupName `
        -VMName $vmName `
        -CommandId "RunPowerShellScript" `
        -ScriptString $windowsFirewallScript `
        -ErrorAction Stop | Out-Null

    Write-Host "Windows Firewall ICMP rule was configured successfully." -ForegroundColor Green
}
catch {
    Write-Host "Failed to configure Windows Firewall." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Get public IP and test ICMP
# ============================================

$publicIpId = $nic.IpConfigurations[0].PublicIpAddress.Id

if (-not $publicIpId) {
    Write-Host "No public IP address is attached to this VM." -ForegroundColor Yellow
    exit 0
}

$publicIpName = ($publicIpId -split "/")[-1]

$publicIp = Get-AzPublicIpAddress `
    -ResourceGroupName $resourceGroupName `
    -Name $publicIpName `
    -ErrorAction Stop

Write-Host ""
Write-Host "Public IP address: $($publicIp.IpAddress)" -ForegroundColor Green
Write-Host "Testing ICMP ping..." -ForegroundColor Cyan

Test-Connection `
    -ComputerName $publicIp.IpAddress `
    -Count 4