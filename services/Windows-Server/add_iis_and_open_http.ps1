# ============================================
# Install IIS and open HTTP on a Windows VM
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
$resourceGroupName = $null

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
    else {
        $resourceGroupName = $resourceGroup.ResourceGroupName
    }
}

Write-Host ""
Write-Host "Selected Resource Group: $resourceGroupName" -ForegroundColor Green

# ============================================
# Select Windows VM
# ============================================

$windowsVms = @(Get-AzVM `
    -ResourceGroupName $resourceGroupName `
    -ErrorAction Stop |
    Where-Object {
        $_.StorageProfile.OsDisk.OsType -eq "Windows"
    } |
    Sort-Object Name)

if ($windowsVms.Count -eq 0) {
    Write-Host "No Windows virtual machines were found in this Resource Group." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Available Windows virtual machines for this Resource Group:" -ForegroundColor Cyan

$windowsVms |
    Select-Object Name, Location, ProvisioningState |
    Format-Table -AutoSize

$vm = $null

while ($null -eq $vm) {
    Write-Host ""
    $vmInput = Read-Host "Enter the Windows VM name"

    if ([string]::IsNullOrWhiteSpace($vmInput)) {
        Write-Host "Windows VM name cannot be empty. Please try again." -ForegroundColor Red
        continue
    }

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
# Find NIC and NSG
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
    Write-Host "Attach an NSG to the NIC before running this script." -ForegroundColor Yellow
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
# Add NSG rule for HTTP
# ============================================

$httpRuleName = "Allow-HTTP-Internet"

try {
    # Reload the NSG after any previous failed update.
    $nsg = Get-AzNetworkSecurityGroup `
        -ResourceGroupName $resourceGroupName `
        -Name $nsgName `
        -ErrorAction Stop

    $existingHttpRule = $nsg.SecurityRules |
        Where-Object { $_.Name -ieq $httpRuleName } |
        Select-Object -First 1

    if ($null -ne $existingHttpRule) {
        Write-Host ""
        Write-Host "HTTP NSG rule already exists. Skipping rule creation." -ForegroundColor Yellow
        Write-Host "Existing rule priority: $($existingHttpRule.Priority)" -ForegroundColor White
    }
    else {
        # Only inbound priorities can conflict with this inbound rule.
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

        Write-Host ""
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
    Write-Host ""
    Write-Host "Failed to configure the HTTP rule in the Network Security Group." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Install IIS
# ============================================

Write-Host ""
Write-Host "Installing IIS on virtual machine '$vmName'..." -ForegroundColor Cyan

$installIisScript = @'
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
$computerName = $env:COMPUTERNAME
Set-Content -Path "C:\inetpub\wwwroot\Default.htm" -Value "<h1>Hello from $computerName</h1>"
'@

try {
    $runCommandResult = Invoke-AzVMRunCommand `
        -ResourceGroupName $resourceGroupName `
        -VMName $vmName `
        -CommandId "RunPowerShellScript" `
        -ScriptString $installIisScript `
        -ErrorAction Stop

    Write-Host "IIS installation command completed successfully." -ForegroundColor Green

    Write-Host ""
    Write-Host "IIS installation output:" -ForegroundColor Cyan

    $runCommandResult.Value |
        Select-Object Code, Message |
        Format-List
}
catch {
    Write-Host "Failed to install IIS." -ForegroundColor Red
    Write-Host "Azure error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================
# Display public HTTP address
# ============================================

$publicIpId = $nic.IpConfigurations[0].PublicIpAddress.Id

if ([string]::IsNullOrWhiteSpace($publicIpId)) {
    Write-Host ""
    Write-Host "No public IP address is attached to this VM." -ForegroundColor Yellow
    Write-Host "IIS was installed, but the website is not reachable from the Internet without a public IP address." -ForegroundColor Yellow
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
Write-Host "Public IP address: $($publicIp.IpAddress)" -ForegroundColor Green
Write-Host "HTTP address: http://$($publicIp.IpAddress)" -ForegroundColor Green