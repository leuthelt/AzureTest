# Required Azure Automation Account Modules => AzureRM.RecoveryServices.Backup

# Logging in to Azure with Run As Connection
function Login() {

    $connectionName = "AzureRunAsConnection"
    
    try
    {
        Write-Verbose "Acquiring service principal for connection ‘$connectionName'" -Verbose
        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName
    
        Write-Verbose "Logging in to Azure…" -Verbose
        
        Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null

        Write-Output "Authenticated with Automation Run As Account"
    }
    catch 
    {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }
}
Login
 
#define global variables
$rsVaultName = "sharedsvcs-rsv"
$rgName = "ffwred-hub-sharedsvcs-rg"
$backupPolicy = "ffwred-vm-default"

# Set Recovery Services Vault context and create protection policy 
$rsv = Get-AzureRmRecoveryServicesVault -Name $rsVaultName
Set-AzureRmRecoveryServicesVaultContext -Vault $rsv

[array]$backupvms = Get-AzureRmResource -Tag @{ backup="true" } -ResourceType "Microsoft.Compute/virtualMachines" | foreach { $_.Name }
$pol = Get-AzureRmRecoveryServicesBackupProtectionPolicy -Name $backupPolicy 

foreach($backupvm in $backupvms)
{

    if( !$( Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $backupvm ) ) {

        Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name $backupvm -ResourceGroupName $rgName

        # Trigger a backup and monitor backup job
        $namedContainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $backupvm
        $item = Get-AzureRmRecoveryServicesBackupItem -Container $namedContainer -WorkloadType "AzureVM"
        $job = Backup-AzureRmRecoveryServicesBackupItem -Item $item
        $joblist = Get-AzureRmRecoveryservicesBackupJob –Status "InProgress"
        Wait-AzureRmRecoveryServicesBackupJob -Job $joblist[0] -Timeout 43200

    } else {

        Write-Output "Virtual machine $backupvm already registered."

    }

}
