param(
    [Parameter(Mandatory = $true)][string]$Environnement,
    [switch]$Apply
)
$Appli = "osc"
switch($Environnement)
{
    "Developement"{
        $resourceGroupName = "rg-e2-np-app-$Appli-dev"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "dev"
    }
    "Formation"{
        $resourceGroupName = "rg-e2-np-app-$Appli-for"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "for"
    }
    "Integration"{
        $resourceGroupName = "rg-e2-np-app-$Appli-int"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "int"
    }
    "Performance"{
        $resourceGroupName = "rg-e2-np-app-$Appli-prf"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "prf"
    }
    "Qualification"{
        $resourceGroupName = "rg-e2-np-app-$Appli-qua"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "qua"
    }
    "preproduction"{
        $resourceGroupName = "rg-e2-pr-app-$Appli-ppd"
        $SubscriptionID = "57197bef-475c-4be3-85ed-057c27149ed1"
        $Env = "ppd"
    }
    "Production"{
        $resourceGroupName = "rg-e2-pr-app-$Appli-prd"
        $SubscriptionID = "57197bef-475c-4be3-85ed-057c27149ed1"
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



