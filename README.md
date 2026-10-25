# Azure-Infrastructure

The configuration, that you want to achieve is up to you. Publicated scripts are based on my personal configuration, but you can use them as your automated scripts for creating a quick infrastructure in Az resource group. I have two configs of resource group infrastructure:

![](/images/VM-infrastructure.png)

![](/images/VM-infrastructure-2.png)

In my case: subscription Azure For Students => I can only have maximum 3 public IP addresses, so in my case, there are two configurations, i can choose and manually create both of them in automated implementation.

Machine configuration config can be set for example with something like that:

![](/images/VM-infrastructure-3.png)

## Requirements

- Minimal **Windows Powershell 5.1**, but recommended: **Powershell 7 or higher** for (Windows, Linux, macOS). Visit: https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6
- **Azure powershell** => https://learn.microsoft.com/pl-pl/powershell/azure/install-azps-windows?view=azps-16.4.0&viewFallbackFrom=azps-16.3.0&tabs=powershell&pivots=windows-psgallery

## Preparation

To connect to your default tenant, simply run:

```powershell
Connect-AzAccount
```

If your account belongs to multiple tenants or you want to target a specific directory, explicitly pass your Tenant ID or primary Domain Name:

```powershell
Connect-AzAccount -Tenant "your-tenant-id-or-domain.com"
```

You may receive an error when trying some global operations:

![](/images/MFA-error.png)

In order to make administration operations ex. creating resource_name, you need to authenticate with MFA:

```powershell
Connect-AzAccount -Tenant (Get-AzContext).Tenant.Id -ClaimsChallenge "your_personal_claims_challenge_id"
```

## How to use?

**Quick info:** Some Azure PowerShell operations may take a while to complete. If an operation appears unresponsive, you can press `Ctrl+C` to stop waiting in the current terminal. Check the operation status in Azure before running it again.

### Resource groups

| File                                                                                 | Usage                                                                                      |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| [/resourceGroup/create_resource_group.ps1](/resourceGroup/create_resource_group.ps1) | Creates a new Azure resource group.                                                        |
| [/resourceGroup/check_resource_group.ps1](/resourceGroup/check_resource_group.ps1)   | Displays information about a resource group and its resources, including virtual machines. |

### Virtual machines

| File                                                                               | Usage                                                                |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| [/createVM/create_vm_personal_config.ps1](/createVM/create_vm_personal_config.ps1) | Creates an Azure virtual machine using a personalized configuration. |

### Load balancer

| File                                                                                                         | Usage                                                              |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| [/services/loadBalancer/create_ld_personal_config.ps1](/services/loadBalancer/create_ld_personal_config.ps1) | Creates an Azure Load Balancer using a personalized configuration. |

### Ubuntu Server

| File                                                                                                           | Usage                                                              |
| -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| [/services/Ubuntu-Server/add_apache2_and_open_http.ps1](/services/Ubuntu-Server/add_apache2_and_open_http.ps1) | Installs Apache2 on an Ubuntu VM and configures HTTP access.       |
| [/services/Ubuntu-Server/allow_icmp.ps1](/services/Ubuntu-Server/allow_icmp.ps1)                               | Configures ICMP access for connectivity testing with ping.         |
| [/services/Ubuntu-Server/check_and_open_ssh.ps1](/services/Ubuntu-Server/check_and_open_ssh.ps1)               | Checks SSH availability on an Ubuntu VM and configures SSH access. |

### Windows Server

| File                                                                                                       | Usage                                                                 |
| ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| [/services/Windows-Server/add_iis_and_open_http.ps1](/services/Windows-Server/add_iis_and_open_http.ps1)   | Installs IIS on a Windows Server VM and configures HTTP access.       |
| [/services/Windows-Server/allow_icmp.ps1](/services/Windows-Server/allow_icmp.ps1)                         | Configures ICMP access for connectivity testing with ping.            |
| [/services/Windows-Server/open_rdp_for_localhost.ps1](/services/Windows-Server/open_rdp_for_localhost.ps1) | Configures RDP access to a Windows Server VM from the local computer. |

### Experimental zone

All files located in [**/machineConfiguration**](/machineConfiguration/) may have bugs and are not fully tested.
