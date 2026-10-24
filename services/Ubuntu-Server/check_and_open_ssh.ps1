# ============================================
# Ensure SSH access to an Ubuntu Server VM
# ============================================

# Disclaimer:
# The official Azure cloud image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest has an OpenSSH server installed and running by default, which listens on the standard port 22. This script is for testing purposes, it is optional during implementation. 

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
# Select Resource Group
# ============================================

Write-Host ""
Write-Host "Available Resource Groups:" -ForegroundColor Cyan

$resourceGroups = @(Get-AzResourceGroup | Sort-Object ResourceGroupName)

if ($resourceGroups.Count -eq 0) {
    Write-Host "No Resource Groups were found in the current subscription." -ForegroundColor Red
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

    $resourceGroupInput = $resourceGroupInput.Trim()

    $resourceGroup = Get-AzResourceGroup `
        -Name $resourceGroupInput `
        -ErrorAction SilentlyContinue

    if ($null -eq $resourceGroup) {
        Write-Host "Resource Group '$resourceGroupInput' was not found. Please try again." -ForegroundColor Red
    }
}

$resourceGroupName = $resourceGroup.ResourceGroupName

Write-Host ""
Write-Host "Selected Resource Group: $resourceGroupName" -ForegroundColor Green

# ============================================
# Select Ubuntu Server VM
# ============================================

$linuxVms = @(
    Get-AzVM `
        -ResourceGroupName $resourceGroupName |
    Where-Object {
        $_.StorageProfile.OsDisk.OsType -eq "Linux"
    } |
    Sort-Object Name
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
    $vmInput = Read-Host "Enter the Ubuntu Server VM name"

    if ([string]::IsNullOrWhiteSpace($vmInput)) {
        Write-Host "Virtual machine name cannot be empty. Please try again." -ForegroundColor Red
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
Write-Host "Selected Ubuntu Server VM: $vmName" -ForegroundColor Green

# ============================================
# Check VM power state
# ============================================

$vmStatus = Get-AzVM `
    -ResourceGroupName $resourceGroupName `
    -Name $vmName `
    -Status `
    -ErrorAction Stop

$powerState = $vmStatus.Statuses |
    Where-Object { $_.Code -like "PowerState/*" } |
    Select-Object -First 1

if ($powerState.Code -ne "PowerState/running") {
    Write-Host "Virtual machine '$vmName' is not running." -ForegroundColor Red
    Write-Host "Current power state: $($powerState.DisplayStatus)" -ForegroundColor Yellow
    Write-Host "Start the VM before configuring SSH access." -ForegroundColor Yellow
    exit 1
}

Write-Host "Virtual machine is running." -ForegroundColor Green

# ============================================
# Detect the local public IP address
# ============================================

Write-Host ""
Write-Host "Detecting the current public IP address..." -ForegroundColor Cyan

try {
    $myPublicIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()

    if ([string]::IsNullOrWhiteSpace($myPublicIp)) {
        throw "The public IP service returned an empty value."
    }

    $myPublicIpCidr = "$myPublicIp/32"

    Write-Host "Detected source IP address: $myPublicIpCidr" -ForegroundColor Green
}
catch {
    Write-Host "Unable to detect the current public IP address." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Get the VM NIC and attached NSG
# ============================================

try {
    $nicId = $vm.NetworkProfile.NetworkInterfaces[0].Id
    $nicName = ($nicId -split "/")[-1]

    $nic = Get-AzNetworkInterface `
        -ResourceGroupName $resourceGroupName `
        -Name $nicName `
        -ErrorAction Stop
}
catch {
    Write-Host "Unable to retrieve the VM network interface." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($null -eq $nic.NetworkSecurityGroup) {
    Write-Host "No Network Security Group is attached directly to this VM network interface." -ForegroundColor Red
    Write-Host "Attach an NSG to the VM NIC before running this script." -ForegroundColor Yellow
    exit 1
}

$nsgName = ($nic.NetworkSecurityGroup.Id -split "/")[-1]

try {
    $nsg = Get-AzNetworkSecurityGroup `
        -ResourceGroupName $resourceGroupName `
        -Name $nsgName `
        -ErrorAction Stop
}
catch {
    Write-Host "Unable to retrieve Network Security Group '$nsgName'." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Network Security Group: $nsgName" -ForegroundColor White

# ============================================
# Create or update the SSH NSG rule
# ============================================

$sshRuleName = "Allow-SSH-From-My-Public-IP"
$sshRulePriority = 1010

$existingSshRule = $nsg.SecurityRules |
    Where-Object { $_.Name -ieq $sshRuleName } |
    Select-Object -First 1

try {
    if ($null -eq $existingSshRule) {
        Write-Host ""
        Write-Host "Creating an SSH rule in the Network Security Group..." -ForegroundColor Cyan

        $nsg | Add-AzNetworkSecurityRuleConfig `
            -Name $sshRuleName `
            -Description "Allow SSH only from the current public IP address" `
            -Access Allow `
            -Protocol Tcp `
            -Direction Inbound `
            -Priority $sshRulePriority `
            -SourceAddressPrefix $myPublicIpCidr `
            -SourcePortRange "*" `
            -DestinationAddressPrefix "*" `
            -DestinationPortRange 22
    }
    else {
        Write-Host ""
        Write-Host "Updating the existing SSH rule with the current public IP address..." -ForegroundColor Cyan

        $nsg | Set-AzNetworkSecurityRuleConfig `
            -Name $sshRuleName `
            -Description "Allow SSH only from the current public IP address" `
            -Access Allow `
            -Protocol Tcp `
            -Direction Inbound `
            -Priority $existingSshRule.Priority `
            -SourceAddressPrefix $myPublicIpCidr `
            -SourcePortRange "*" `
            -DestinationAddressPrefix "*" `
            -DestinationPortRange 22
    }

    Set-AzNetworkSecurityGroup `
        -NetworkSecurityGroup $nsg `
        -ErrorAction Stop | Out-Null

    Write-Host "SSH access is allowed in the Network Security Group." -ForegroundColor Green
}
catch {
    Write-Host "Failed to configure the SSH Network Security Group rule." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Ensure OpenSSH Server is installed and active
# ============================================

Write-Host ""
Write-Host "Checking OpenSSH Server on the Ubuntu VM..." -ForegroundColor Cyan

$sshConfigurationScript = @'
set -e

if ! command -v sshd >/dev/null 2>&1; then
    echo "OpenSSH Server is not installed. Installing openssh-server..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
else
    echo "OpenSSH Server is already installed."
fi

systemctl enable ssh
systemctl restart ssh

if systemctl is-active --quiet ssh; then
    echo "OpenSSH Server service is active."
else
    echo "OpenSSH Server service is not active."
    exit 1
fi

if ss -tulpn | grep -q ":22 "; then
    echo "SSH is listening on TCP port 22."
else
    echo "SSH is not listening on TCP port 22."
    exit 1
fi

if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
        echo "UFW is active. Allowing TCP port 22."
        ufw allow 22/tcp
    else
        echo "UFW is installed but inactive."
    fi
else
    echo "UFW is not installed."
fi

echo "SSH configuration completed successfully."
'@

try {
    $runCommandResult = Invoke-AzVMRunCommand `
        -ResourceGroupName $resourceGroupName `
        -VMName $vmName `
        -CommandId "RunShellScript" `
        -ScriptString $sshConfigurationScript `
        -ErrorAction Stop

    Write-Host "OpenSSH Server was checked and configured successfully." -ForegroundColor Green

    Write-Host ""
    Write-Host "Linux VM command output:" -ForegroundColor Cyan

    $runCommandResult.Value |
        Select-Object Code, Message |
        Format-List
}
catch {
    Write-Host "Failed to configure OpenSSH Server on the Linux VM." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Display public IP address and SSH command
# ============================================

$publicIpId = $nic.IpConfigurations[0].PublicIpAddress.Id

if (-not $publicIpId) {
    Write-Host ""
    Write-Host "No public IP address is attached to this VM." -ForegroundColor Yellow
    Write-Host "SSH is configured, but the VM cannot be reached from the Internet without a public IP, VPN, Bastion, or another private connection." -ForegroundColor Yellow
    exit 0
}

$publicIpName = ($publicIpId -split "/")[-1]

try {
    $publicIp = Get-AzPublicIpAddress `
        -ResourceGroupName $resourceGroupName `
        -Name $publicIpName `
        -ErrorAction Stop
}
catch {
    Write-Host "Unable to retrieve the VM public IP address." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "SSH configuration is complete." -ForegroundColor Green
Write-Host "Public IP address: $($publicIp.IpAddress)" -ForegroundColor Green
Write-Host "SSH command: ssh <username>@$($publicIp.IpAddress)" -ForegroundColor Green
Write-Host "Only the detected source IP '$myPublicIp' is allowed by the SSH NSG rule." -ForegroundColor Yellow