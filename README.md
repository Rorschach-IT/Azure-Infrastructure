# Azure-Infrastructure

In my personal configuration, i have two configs of resource group infrastructure:

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

**Quick info**: _sometimes azure powershell can free, type ctrl + c to skip the current zombie process_.

| File                                                                      | Usage                                                   |
| ------------------------------------------------------------------------- | ------------------------------------------------------- |
| [**create_resource_group.ps1**](/resourceGroup/create_resource_group.ps1) | Creates a new resource group.                           |
| [**check_resource_group.ps1**](/resourceGroup/check_resource_group.ps1)   | Print data of the resource group: resources, VMs e.t.c. |
