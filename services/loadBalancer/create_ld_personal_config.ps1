# ============================================
# Create a public HTTP Load Balancer
# for two or three existing virtual machines
# ============================================

Clear-Host

# ============================================
# Read a non-empty value
# ============================================

function Read-RequiredValue {
    param (
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    while ($true) {
        $value = Read-Host $Prompt

        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host "The value cannot be empty. Please try again." -ForegroundColor Red
            continue
        }

        return $value.Trim()
    }
}

# ============================================
# Get a resource using its Azure resource ID
# ============================================

function Get-ResourceIdParts {
    param (
        [Parameter(Mandatory)]
        [string]$ResourceId
    )

    $parts = $ResourceId -split "/"

    [PSCustomObject]@{
        ResourceGroupName = $parts[4]
        Name              = $parts[-1]
    }
}

# ============================================
# Check Azure context
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

    # ========================================
    # Select Resource Group
    # ========================================

    $resourceGroups = @(
        Get-AzResourceGroup -ErrorAction Stop |
            Sort-Object ResourceGroupName
    )

    if ($resourceGroups.Count -eq 0) {
        throw "No Resource Groups were found in the current subscription."
    }

    Write-Host ""
    Write-Host "Available Resource Groups:" -ForegroundColor Cyan

    $resourceGroups |
        Select-Object ResourceGroupName, Location |
        Format-Table -AutoSize

    $resourceGroup = $null

    while ($null -eq $resourceGroup) {
        $resourceGroupInput = Read-RequiredValue `
            -Prompt "Enter the Resource Group name"

        $resourceGroup = $resourceGroups |
            Where-Object {
                $_.ResourceGroupName -ieq $resourceGroupInput
            } |
            Select-Object -First 1

        if ($null -eq $resourceGroup) {
            Write-Host "Resource Group was not found. Please select a group from the list." -ForegroundColor Red
        }
    }

    $resourceGroupName = $resourceGroup.ResourceGroupName

    # ========================================
    # Display available VMs
    # ========================================

    $availableVms = @(
        Get-AzVM `
            -ResourceGroupName $resourceGroupName `
            -ErrorAction Stop |
        Sort-Object Name
    )

    if ($availableVms.Count -lt 2) {
        throw "At least two virtual machines are required in the selected Resource Group."
    }

    Write-Host ""
    Write-Host "Available virtual machines:" -ForegroundColor Cyan

    $availableVms |
        Select-Object Name, Location, @{
            Name = "OperatingSystem"
            Expression = { $_.StorageProfile.OsDisk.OsType }
        } |
        Format-Table -AutoSize

    # ========================================
    # Select the number of backend VMs
    # ========================================

    $vmCount = 0

    while ($vmCount -eq 0) {
        $countInput = Read-RequiredValue `
            -Prompt "How many VMs should be added to the Load Balancer? Enter 2 or 3"

        if ($countInput -notin @("2", "3")) {
            Write-Host "Invalid number. Please enter 2 or 3." -ForegroundColor Red
            continue
        }

        if ([int]$countInput -gt $availableVms.Count) {
            Write-Host "There are not enough VMs in this Resource Group. Please try again." -ForegroundColor Red
            continue
        }

        $vmCount = [int]$countInput
    }

    # ========================================
    # Select and validate backend VMs
    # ========================================

    $selectedBackends = @()
    $location = $null
    $selectedVnetId = $null

    for ($index = 1; $index -le $vmCount; $index++) {
        $selectionComplete = $false

        while (-not $selectionComplete) {
            Write-Host ""

            $vmInput = Read-RequiredValue `
                -Prompt "Enter VM name ($index of $vmCount)"

            if ($selectedBackends.VMName -contains $vmInput) {
                Write-Host "This VM has already been selected. Please select another VM." -ForegroundColor Red
                continue
            }

            $vm = $availableVms |
                Where-Object { $_.Name -ieq $vmInput } |
                Select-Object -First 1

            if ($null -eq $vm) {
                Write-Host "VM '$vmInput' was not found. Please try again." -ForegroundColor Red
                continue
            }

            if ($location -and $vm.Location -ine $location) {
                Write-Host "All selected VMs must be in region '$location'." -ForegroundColor Red
                continue
            }

            # Use the primary NIC, or the only NIC.
            $nicReferences = @($vm.NetworkProfile.NetworkInterfaces)

            $nicReference = $nicReferences |
                Where-Object { $_.Primary -eq $true } |
                Select-Object -First 1

            if (-not $nicReference -and $nicReferences.Count -eq 1) {
                $nicReference = $nicReferences[0]
            }

            if (-not $nicReference) {
                Write-Host "Unable to identify the primary NIC. Please select another VM." -ForegroundColor Red
                continue
            }

            $nicParts = Get-ResourceIdParts -ResourceId $nicReference.Id

            $nic = Get-AzNetworkInterface `
                -ResourceGroupName $nicParts.ResourceGroupName `
                -Name $nicParts.Name `
                -ErrorAction Stop

            $ipConfigurations = @(
                $nic.IpConfigurations |
                    Where-Object {
                        $_.PrivateIpAddressVersion -eq "IPv4"
                    }
            )

            $ipConfig = $ipConfigurations |
                Where-Object { $_.Primary -eq $true } |
                Select-Object -First 1

            if (-not $ipConfig -and $ipConfigurations.Count -eq 1) {
                $ipConfig = $ipConfigurations[0]
            }

            if (-not $ipConfig -or -not $ipConfig.Subnet.Id) {
                Write-Host "No suitable primary IPv4 configuration was found. Please select another VM." -ForegroundColor Red
                continue
            }

            $vnetId = $ipConfig.Subnet.Id -replace "/subnets/[^/]+$", ""

            if ($selectedVnetId -and $vnetId -ine $selectedVnetId) {
                Write-Host "This VM is in a different Virtual Network." -ForegroundColor Red
                Write-Host "Please select a VM from the same Virtual Network as the first VM." -ForegroundColor Yellow
                continue
            }

            # Standard LB requires compatible VM-level Public IPs.
            if ($ipConfig.PublicIpAddress.Id) {
                $pipParts = Get-ResourceIdParts `
                    -ResourceId $ipConfig.PublicIpAddress.Id

                $vmPublicIp = Get-AzPublicIpAddress `
                    -ResourceGroupName $pipParts.ResourceGroupName `
                    -Name $pipParts.Name `
                    -ErrorAction Stop

                if ($vmPublicIp.Sku.Name -ne "Standard") {
                    Write-Host "This VM has a non-Standard Public IP address." -ForegroundColor Red
                    Write-Host "Select another VM or upgrade its Public IP first." -ForegroundColor Yellow
                    continue
                }
            }

            # Inspect both NIC-level and subnet-level NSGs.
            $vnetParts = Get-ResourceIdParts -ResourceId $vnetId

            $vnet = Get-AzVirtualNetwork `
                -ResourceGroupName $vnetParts.ResourceGroupName `
                -Name $vnetParts.Name `
                -ErrorAction Stop

            $subnet = $vnet.Subnets |
                Where-Object { $_.Id -ieq $ipConfig.Subnet.Id } |
                Select-Object -First 1

            $nsgIds = @(
                if ($nic.NetworkSecurityGroup.Id) {
                    $nic.NetworkSecurityGroup.Id
                }

                if ($subnet.NetworkSecurityGroup.Id) {
                    $subnet.NetworkSecurityGroup.Id
                }
            ) | Select-Object -Unique

            if (@($nsgIds).Count -eq 0) {
                Write-Host "No NSG is attached to this NIC or subnet." -ForegroundColor Red
                Write-Host "Attach an NSG before selecting this VM." -ForegroundColor Yellow
                continue
            }

            if (-not $location) {
                $location = $vm.Location
                $selectedVnetId = $vnetId
            }

            $selectedBackends += [PSCustomObject]@{
                VMName            = $vm.Name
                NicName           = $nic.Name
                NicResourceGroup  = $nicParts.ResourceGroupName
                IpConfigName      = $ipConfig.Name
                PrivateIP         = $ipConfig.PrivateIpAddress
                NsgIds            = @($nsgIds)
            }

            Write-Host "Selected VM: $($vm.Name)" -ForegroundColor Green
            Write-Host "NIC: $($nic.Name)" -ForegroundColor White
            Write-Host "Private IP: $($ipConfig.PrivateIpAddress)" -ForegroundColor White

            $selectionComplete = $true
        }
    }

    # ========================================
    # Select unique resource names
    # ========================================

    $loadBalancerName = $null

    while ($null -eq $loadBalancerName) {
        $nameInput = Read-RequiredValue `
            -Prompt "Enter a new Load Balancer name"

        $existingLoadBalancers = @(
            Get-AzLoadBalancer `
                -ResourceGroupName $resourceGroupName `
                -ErrorAction Stop
        )

        if ($existingLoadBalancers.Name -contains $nameInput) {
            Write-Host "A Load Balancer with this name already exists. Please enter another name." -ForegroundColor Red
            continue
        }

        $loadBalancerName = $nameInput
    }

    $publicIpName = $null

    while ($null -eq $publicIpName) {
        $nameInput = Read-RequiredValue `
            -Prompt "Enter a new Load Balancer Public IP resource name"

        $existingPublicIps = @(
            Get-AzPublicIpAddress `
                -ResourceGroupName $resourceGroupName `
                -ErrorAction Stop
        )

        if ($existingPublicIps.Name -contains $nameInput) {
            Write-Host "A Public IP resource with this name already exists. Please enter another name." -ForegroundColor Red
            continue
        }

        $publicIpName = $nameInput
    }

    # ========================================
    # Confirm deployment
    # ========================================

    Write-Host ""
    Write-Host "Deployment summary:" -ForegroundColor Cyan
    Write-Host "Resource Group: $resourceGroupName" -ForegroundColor White
    Write-Host "Location: $location" -ForegroundColor White
    Write-Host "Load Balancer: $loadBalancerName" -ForegroundColor White
    Write-Host "Public IP resource: $publicIpName" -ForegroundColor White
    Write-Host "Backend VM count: $vmCount" -ForegroundColor White
    Write-Host "Frontend and backend port: TCP/80" -ForegroundColor White
    Write-Host "HTTP will be allowed from the Internet to the selected backend IPs." -ForegroundColor Yellow
    Write-Host "Existing NIC and subnet NSGs will be modified." -ForegroundColor Yellow
    Write-Host "Azure resources created by this script may incur charges." -ForegroundColor Yellow

    $selectedBackends |
        Select-Object VMName, NicName, PrivateIP |
        Format-Table -AutoSize

    $confirmation = $null

    while ($confirmation -notin @("Y", "YES", "N", "NO")) {
        $confirmation = Read-RequiredValue `
            -Prompt "Type Y to deploy or N to cancel"

        if ($confirmation -notin @("Y", "YES", "N", "NO")) {
            Write-Host "Invalid option. Please type Y or N." -ForegroundColor Red
        }
    }

    if ($confirmation -in @("N", "NO")) {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        return
    }

    # ========================================
    # Configure NSGs
    # ========================================

    $allNsgIds = @(
        $selectedBackends |
            ForEach-Object { $_.NsgIds } |
            Sort-Object -Unique
    )

    foreach ($nsgId in $allNsgIds) {
        $nsgParts = Get-ResourceIdParts -ResourceId $nsgId

        $nsg = Get-AzNetworkSecurityGroup `
            -ResourceGroupName $nsgParts.ResourceGroupName `
            -Name $nsgParts.Name `
            -ErrorAction Stop

        $destinationIPs = @(
            $selectedBackends |
                Where-Object { $_.NsgIds -contains $nsgId } |
                Select-Object -ExpandProperty PrivateIP |
                Sort-Object -Unique
        )

        Write-Host ""
        Write-Host "Configuring NSG '$($nsg.Name)'..." -ForegroundColor Cyan

        # Use a unique suffix to avoid changing existing named rules.
        $ruleSuffix = [guid]::NewGuid().ToString("N").Substring(0, 8)

        $ruleDefinitions = @(
            @{
                Name   = "Allow-LB-HTTP-$ruleSuffix"
                Source = "Internet"
            },
            @{
                Name   = "Allow-LB-Probe-$ruleSuffix"
                Source = "AzureLoadBalancer"
            }
        )

        foreach ($definition in $ruleDefinitions) {
            $usedPriorities = @(
                $nsg.SecurityRules |
                    Where-Object { $_.Direction -eq "Inbound" } |
                    Select-Object -ExpandProperty Priority
            )

            $priority = $null

            foreach ($candidatePriority in 1000..4096) {
                if ($usedPriorities -notcontains $candidatePriority) {
                    $priority = $candidatePriority
                    break
                }
            }

            if ($null -eq $priority) {
                throw "No free inbound priority was found between 1000 and 4096 in NSG '$($nsg.Name)'."
            }

            $nsg = Add-AzNetworkSecurityRuleConfig `
                -NetworkSecurityGroup $nsg `
                -Name $definition.Name `
                -Description "HTTP Load Balancer backend access" `
                -Access Allow `
                -Protocol Tcp `
                -Direction Inbound `
                -Priority $priority `
                -SourceAddressPrefix $definition.Source `
                -SourcePortRange "*" `
                -DestinationAddressPrefix $destinationIPs `
                -DestinationPortRange 80 `
                -ErrorAction Stop
        }

        Set-AzNetworkSecurityGroup `
            -NetworkSecurityGroup $nsg `
            -ErrorAction Stop | Out-Null

        Write-Host "NSG rules were saved successfully." -ForegroundColor Green
    }

    # ========================================
    # Create Standard Public IP
    # ========================================

    Write-Host ""
    Write-Host "Creating the Load Balancer Public IP..." -ForegroundColor Cyan

    $lbPublicIp = New-AzPublicIpAddress `
        -ResourceGroupName $resourceGroupName `
        -Name $publicIpName `
        -Location $location `
        -Sku Standard `
        -AllocationMethod Static `
        -IpAddressVersion IPv4 `
        -ErrorAction Stop

    # ========================================
    # Create Load Balancer configuration
    # ========================================

    $frontendName = "FrontendHTTP"
    $backendPoolName = "BackendPoolWeb"
    $healthProbeName = "HealthProbeHTTP"
    $loadBalancingRuleName = "HTTP-80"

    $frontendIpConfig = New-AzLoadBalancerFrontendIpConfig `
        -Name $frontendName `
        -PublicIpAddress $lbPublicIp

    $backendPool = New-AzLoadBalancerBackendAddressPoolConfig `
        -Name $backendPoolName

    $healthProbe = New-AzLoadBalancerProbeConfig `
        -Name $healthProbeName `
        -Protocol Tcp `
        -Port 80 `
        -IntervalInSeconds 5 `
        -ProbeCount 2

    $loadBalancingRule = New-AzLoadBalancerRuleConfig `
        -Name $loadBalancingRuleName `
        -Protocol Tcp `
        -FrontendPort 80 `
        -BackendPort 80 `
        -FrontendIpConfiguration $frontendIpConfig `
        -BackendAddressPool $backendPool `
        -Probe $healthProbe `
        -IdleTimeoutInMinutes 4 `
        -LoadDistribution Default `
        -DisableOutboundSNAT

    Write-Host ""
    Write-Host "Creating Standard Load Balancer '$loadBalancerName'..." -ForegroundColor Cyan

    $loadBalancer = New-AzLoadBalancer `
        -ResourceGroupName $resourceGroupName `
        -Name $loadBalancerName `
        -Location $location `
        -Sku Standard `
        -FrontendIpConfiguration $frontendIpConfig `
        -BackendAddressPool $backendPool `
        -Probe $healthProbe `
        -LoadBalancingRule $loadBalancingRule `
        -ErrorAction Stop

    $backendPool = $loadBalancer.BackendAddressPools |
        Where-Object { $_.Name -eq $backendPoolName } |
        Select-Object -First 1

    if (-not $backendPool) {
        throw "The backend pool was not found after Load Balancer creation."
    }

    # ========================================
    # Add selected NICs to the backend pool
    # ========================================

    foreach ($backend in $selectedBackends) {
        Write-Host ""
        Write-Host "Adding VM '$($backend.VMName)' to the backend pool..." -ForegroundColor Cyan

        $nic = Get-AzNetworkInterface `
            -ResourceGroupName $backend.NicResourceGroup `
            -Name $backend.NicName `
            -ErrorAction Stop

        $ipConfig = $nic.IpConfigurations |
            Where-Object { $_.Name -eq $backend.IpConfigName } |
            Select-Object -First 1

        if (-not $ipConfig) {
            throw "The selected IP configuration was not found on NIC '$($nic.Name)'."
        }

        # Preserve existing backend pool associations.
        $existingPools = @(
            $ipConfig.LoadBalancerBackendAddressPools |
                Where-Object { $null -ne $_ }
        )

        if ($existingPools.Id -notcontains $backendPool.Id) {
            $ipConfig.LoadBalancerBackendAddressPools = @(
                $existingPools
                $backendPool
            )

            Set-AzNetworkInterface `
                -NetworkInterface $nic `
                -ErrorAction Stop | Out-Null
        }

        Write-Host "Backend pool membership configured." -ForegroundColor Green
    }

    # ========================================
    # Display final configuration
    # ========================================

    $lbPublicIp = Get-AzPublicIpAddress `
        -ResourceGroupName $resourceGroupName `
        -Name $publicIpName `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "Load Balancer configuration completed." -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green

    Write-Host "Load Balancer: $loadBalancerName" -ForegroundColor White
    Write-Host "Public IP: $($lbPublicIp.IpAddress)" -ForegroundColor Green
    Write-Host "HTTP address: http://$($lbPublicIp.IpAddress)" -ForegroundColor Green

    Write-Host ""
    Write-Host "Selected backend virtual machines:" -ForegroundColor Cyan

    $selectedBackends |
        Select-Object VMName, NicName, PrivateIP, @{
            Name = "BackendPool"
            Expression = { $backendPoolName }
        } |
        Format-Table -AutoSize

    Write-Host "Make sure every backend VM serves HTTP on TCP port 80." -ForegroundColor Yellow
    Write-Host "Guest firewalls must allow HTTP and Azure Load Balancer health probes." -ForegroundColor Yellow
    Write-Host "Outbound connectivity was not configured by this script." -ForegroundColor Yellow
}
catch {
    Write-Host ""
    Write-Host "Load Balancer configuration failed." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Some resources or NSG changes may already exist. Review them before retrying." -ForegroundColor Yellow
    exit 1
}