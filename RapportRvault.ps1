param(
    [Parameter(Mandatory = $true)][string]$Environnement,
    [switch]$Apply
)
$Appli = "osc"
switch($Environnement)
{
    "Developement"{
        $resourceGroupName = "rg-e2-np-app-$Appli-dev"
        $SubscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        $Env = "dev"
    }
    "Formation"{
        $resourceGroupName = "rg-e2-np-app-$Appli-for"
        $SubscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        $Env = "for"
    }
    "Integration"{
        $resourceGroupName = "rg-e2-np-app-$Appli-int"
        $SubscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        $Env = "int"
    }
    "Performance"{
        $resourceGroupName = "rg-e2-np-app-$Appli-prf"
        $SubscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        $Env = "prf"
    }
    "Qualification"{
        $resourceGroupName = "rg-e2-np-app-$Appli-qua"
        $SubscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        $Env = "qua"
    }
    "preproduction"{
        $resourceGroupName = "rg-e2-pr-app-$Appli-ppd"
        $SubscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        $Env = "ppd"
    }
    "Production"{
        $resourceGroupName = "rg-e2-pr-app-$Appli-prd"
        $SubscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        $Env = "prd"
    }
}

Set-AzContext -Subscription $SubscriptionID | Out-Null

$Report = @()
$VMs = Get-AzVM -ResourceGroupName $resourceGroupName


foreach ($vm in $VMs)
{
    $RsvState = Get-AzRecoveryServicesBackupStatus -Name $vm.name -ResourceGroupName $resourceGroupName -Type "AzureVM"
    if($RsvState.BackedUp -eq $true)
    {
        $rsv = ($RsvState).VaultId.Split('/')[-1]
        $VMRvault = New-Object PSObject -property @{
        'VM Name'           = $vm.name
        'Associated Vault'  = $rsv
        }
    }
    else 
    {
        $VMRvault = New-Object PSObject -property @{
        'VM Name'           = $vm.name
        'Associated Vault'  = "NO BACKUP !!"
        }
    }
    
    $Report += $VMRvault  
}
Write-output ""
Write-Output "Les VMs de l'environnement ${$Environnement} avec leur Recovery Vault associe : "
$Report
$Report | out-file "RvaultReport${Appli}_$Env.txt" -Encoding UTF8



