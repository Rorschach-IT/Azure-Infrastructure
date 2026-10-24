# ============================================
# Compile the SSH audit DSC configuration
# This file is called by buildSSHAuditPackage.ps1
# ============================================

Configuration AuditSshService {
    Import-DscResource `
        -ModuleName LinuxServiceAudit

    Node localhost {
        LinuxServiceState SshService {
            ServiceName  = "ssh"
            DesiredState = "active"
        }
    }
}

$artifactsPath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "artifacts"

$compiledPath = Join-Path `
    -Path $artifactsPath `
    -ChildPath "compiled"

New-Item `
    -Path $compiledPath `
    -ItemType Directory `
    -Force | Out-Null

AuditSshService -OutputPath $compiledPath | Out-Null

Write-Host "The SSH audit configuration was compiled." -ForegroundColor Green