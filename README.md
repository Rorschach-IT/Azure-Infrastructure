# Azure-Infrastructure

## Requirements (23_10_2026)

1. Minimal **Windows Powershell 5.1**, but recommended: **Powershell 7 or higher** for (Windows, Linux, macOS). Visit: https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6
2. **Azure powershell** => https://learn.microsoft.com/pl-pl/powershell/azure/install-azps-windows?view=azps-16.4.0&viewFallbackFrom=azps-16.3.0&tabs=powershell&pivots=windows-psgallery

## Preparation

1. To connect to your default tenant, simply run:

```powershell
Connect-AzAccount
```

2. If your account belongs to multiple tenants or you want to target a specific directory, explicitly pass your Tenant ID or primary Domain Name:

```powershell
Connect-AzAccount -Tenant "your-tenant-id-or-domain.com"
```

## How to use?
