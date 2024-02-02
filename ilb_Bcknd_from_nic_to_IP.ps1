<#
Auteur : Sebastien ARTHAUD
Date : 15/06/23
Fonction : Ce script modifie la configuration des regles de load balancer pour que ces derniers pointent vers les adresses IP des backend et non les NIC.

Detail : Tout d'abord le script creer des nouveaux Backend pool en fonction des existants en les configurant avec les adresse IP et non les NIC

Dans un second lieu, le script va modifier toutes les regles associees a chaque backen pool existant pour les changer avec les nouveaux pool.

Parametres en entree : 
        - resourceGroupName : Nom du resource group dans lequel se trouve le load balancer
        - Lb : Nom du Load balancer a configurer
#>



param(
    [Parameter(Mandatory = $true)][string]$Environnement,
    [switch]$Apply
)
switch($Environnement)
{
    "Developement"{
        $resourceGroupName = "rg-e2-np-app-pgs-dev"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "dev"
    }
    "Formation"{
        $resourceGroupName = "rg-e2-np-app-pgs-for"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "for"
    }
    "Integration"{
        $resourceGroupName = "rg-e2-np-app-pgs-int"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "int"
    }
    "Performance"{
        $resourceGroupName = "rg-e2-np-app-pgs-prf"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "prf"
    }
    "Qualification"{
        $resourceGroupName = "rg-e2-np-app-pgs-qua"
        $SubscriptionID = "8197d8ee-b7df-4b0a-bdaf-bd38b0f19aaf"
        $Env = "qua"
    }
    "preproduction"{
        $resourceGroupName = "rg-e2-pr-app-pgs-ppd"
        $SubscriptionID = "57197bef-475c-4be3-85ed-057c27149ed1"
        $Env = "ppd"
    }
    "Production"{
        $resourceGroupName = "rg-e2-pr-app-pgs-prd"
        $SubscriptionID = "57197bef-475c-4be3-85ed-057c27149ed1"
        $Env = "prd"
    }
}
Set-AzContext -Subscription $SubscriptionID | Out-Null



#Declaration de variables
$BackendAssociatedRule = @()




#Declaration de fonctions


#Cette focntion va definir le nom du nouveau Backend.
Function GetNewBackEndName {
    param(
        [String]$Environnement,
        [String]$BriqueHastus
    )

        if ($Environnement -eq "prd" -or $Environnement -eq "ppd")
        {
            $NewBackendName = "pool-$BriqueHastus-pr-app-pgs-$env"
        }
        else {
            $NewBackendName = "pool-$BriqueHastus-np-app-pgs-$env"
        }
        
        
        return $NewBackendName
}


# Verification de la souscription. Il faut se trouver sur "e.sncf mobilite nprd". Sinon, nous devons bien verifier la souscription dans laquelle nous nous trouvons ! surtout si cest la prod...
if ($SubscriptionID.ToLower() -eq "57197bef-475c-4be3-85ed-057c27149ed1")
{
    Write-Warning "ATTENTION - Vous êtes dans la souscription PRODUCTION."
    $Response = Read-Host "Continuer ?"
    if ("y","o","yes","oui" -NotContains $Response.ToLower())
    {
        Exit
    }
}


$LoadBalancers = Get-AzLoadBalancer -ResourceGroupName $resourceGroupName

$IndexLB = 1

write-host "Pour l'environnement $Environnement, voici les load balancers presents :"

foreach($LoadBalancer in $LoadBalancers)
{
    Write-Host "$IndexLB. $($LoadBalancer.Name)"
    $IndexLB ++
}

$Choix = Read-Host "Quel Load balancer souhaitez-vous reconfigurer ?"
$Lb = $LoadBalancers[$Choix - 1].Name

#Recuperation des backendpool existant sur le load balancer
$LbBackend = Get-AzLoadBalancerBackendAddressPool -ResourceGroupName $resourceGroupName -LoadBalancerName $Lb

#Stockage du load balancer dans un PSObject. Cela servira plus tard dans le code
$LbProperties = Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -name $Lb


write-host "Pour le load balancer $($Lb.Name), voici les backend presents :"
$IndexBcknd = 1
foreach($Bck in $LbBackend)
{
    Write-Host "$IndexBcknd. $($Bck.Name)"
    $IndexBcknd ++
}
$BackendChoice = Read-Host "Quel Backend souhaitez-vous reconfigurer ?"

$Backend = $LbBackend[$BackendChoice - 1]


$BriqueHastus = ""
while($BriqueHastus -ne "vd" -and $BriqueHastus -ne "pt" -and $BriqueHastus -ne "co")
{
    $BriqueHastus = Read-Host "Quel type de brique Hastus se trouve derriere ce backend $($Backend.Name) ? ('vd', 'co' ou 'pt')"

    if ($BriqueHastus -ne "vd" -and $BriqueHastus -ne "pt" -and $BriqueHastus -ne "co")
    {
        Write-Warning "Veuillez entrer une valeur valide ! : 'co', 'vd' ou 'pt'"
    }
}



$BackendAssociatedRule = @()
$BackendIps = @()
$IpMessage = @()
$NicName = ""


Write-Host ""
Write-Host "Backend traite : $($Backend.Name)"
Write-Host "Brique Hastus liee a ce backend : $BriqueHastus"
foreach ($rule in $Backend.LoadBalancingRules)
{
    $RuleName = $rule.Id.SPlit('/')[-1]
    $BackendAssociatedRule += $RuleName
}

$BackEndOK = $True
#Dans chaque Backend, il peut y avoiir plusieurs adresses IP. Ici nous recuperons toutes ces adresse IP via leur Id AZURE et nous allons
#Recuperer leur nom.
if(($Backend.BackendIpConfigurations.Id))
{
    $i = 1
    foreach($BackendId in ($Backend.BackendIpConfigurations.Id))
    {
        
        #Nous recuperons leur nom en effectuant un Hash de l'ID
        $HashId = $BackendId.Split('/')
        write-host ""
        $Type = $HashId[7]
        $NicName = $HashId[8]

        #Il faut que l'adresse IP ou le backend soit une carte reseau ! sinon, cela ne sert a rien de reconfigurer ce backend pool
        if($Type -like "*networkinterfaces*" -and ($NicName -notlike "*wzht*" -and $NicName -notlike "*wzbd*" -and $NicName -notlike "*wzex*"))
        {

            $BackEndName = $Backend.Name
            $NicRg = $HashId[4]
            $NicInfos = Get-AzNetworkInterface -ResourceGroupName $NicRg -Name $NicName
            #$NicConfig = Get-AzNetworkInterfaceIpConfig -NetworkInterface $NicInfos
            #$NicConfigId = $NicConfig.Subnet.Id
            $NicConfigId = $NicInfos.IpConfigurations.Subnet.Id
            $Vnet = (Get-AzVirtualNetwork -Name ($NicConfigId.Split('/')[8])).Id
            $NicIP = $NicInfos.IpConfigurations.PrivateIpAddress
            

            write-host "Type Backend : $Type"
            write-host "Nom du NIC : $NicName"
            write-host "Resource Group du NIC : $NicRg"
            write-host "Adresse IP : $NicIP"
            $NewBackendName = GetNewBackEndName -Environnement $Env -BriqueHastus $BriqueHastus    #Convention de Nommage du nouveau Backend
            write-host "Nom de l'ancien Backend : $BackEndName"
            write-host "Nom du nouveau BackEnd : $NewBackendName"

            write-host "Regles associees a ce Backend : $($BackendAssociatedRule | ForEach-Object {"$_, "})"
            $ip = New-AzLoadBalancerBackendAddressConfig -IpAddress $NicIP -Name "$NewBackendName-$($i.ToString())" -VirtualNetworkId $Vnet
            $BackendIps += $ip
            $IpMessage += "$($ip.IpAddress) "
        }
        else{
            
            if($Type -notlike "*networkinterfaces*")
            {
                write-host "$($BackendId) n'est pas un NIC mais une adresse IP !" -ForegroundColor Red
            }
            
            $BackEndOK = $False
        }
        $i++
        
    }

    #Si le parametre Apply est entre et que le backend est bon (pas une adresse IP mais une NIC) alors on effectue les modifications
    if($Apply -and $BackEndOK -eq $True)
    {

        $NewBackendPool = New-AzLoadBalancerBackendAddressPool -ResourceGroupName $resourceGroupName -LoadBalancerName $Lb -LoadBalancerBackendAddress $BackendIps -Name $NewBackendName

        #Pour chaque regle de load balancing associee a ce backend...
        foreach ($rule in $Backend.LoadBalancingRules)
        {
            

            #recuperation du nom de la regle existante via son Id 
            $RuleName = $rule.Id.Split('/')[-1]
            
            #Recuperation de la configuration de la regle existante
            $OldRuleConfig = get-AzLoadBalancerRuleConfig -LoadBalancer $LbProperties -Name $RuleName
            #Recuperation de la configuration de l'adresse IP en Front existante
            $RuleFrontEndIpConfig = Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $LbProperties -Name (($OldRuleConfig.FrontendIPConfiguration.Id).Split('/'))[-1]
            
            # recuperation du health Probe existant et configure sur la regle deja en place
            $ProbeToConfigure = get-AzLoadBalancerProbeConfig -LoadBalancer $LbProperties -Name (($OldRuleConfig.Probe.Id).Split('/'))[-1]
            
            $LbProperties = Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -name $Lb
            

            $extraArgs = @{}
            if ($OldRuleConfig.EnableFloatingIP)
            {
                $extraArgs["EnableFloatingIP"] = $true
            }
            if ($OldRuleConfig.EnableTcpReset)
            {
                $extraArgs["EnableTcpReset"] = $true
            }
            if ($OldRuleConfig.DisableOutboundSNAT)
            {
                $extraArgs["DisableOutboundSNAT"] = $OldRuleConfig.DisableOutboundSNAT
            }
            Set-AzLoadBalancerRuleConfig `
            -LoadBalancer $LbProperties `
            -Name $RuleName `
            -BackendAddressPool $NewBackendPool `
            -FrontendIpConfiguration $RuleFrontEndIpConfig `
            -Protocol $OldRuleConfig.Protocol `
            -Probe $ProbeToConfigure `
            -FrontendPort $OldRuleConfig.FrontendPort `
            -BackendPort $OldRuleConfig.BackendPort `
            -LoadDistribution $OldRuleConfig.LoadDistribution `
            @extraArgs

            $LbProperties | set-AzLoadBalancer
        }
        
        #>
    }
    #Si le parametre Apply n'est pas entre, alors on ne fais qu'une execution a blanc
    elseif($BackEndOK -eq $True)
    {
        Write-host "Le backend $($Backend.Name) est a modifier !" -ForegroundColor Green
        write-host "Voici les IP du Backend qui doivent etre associees au nouveau backend : $IpMessage" -ForegroundColor Green
    }
    #Que le Apply soit entre ou non, si le backend est base sur les adresses IP alors il n'y a pas besoin de le reconfigurer
    elseif (($Apply -and $BackEndOK -eq $False) -or $BackEndOK -eq $False) 
    {
        if($NicName -like "*wzht*" -or $NicName -like "*wzbd*" -or $NicName -like "*wzex*")
        {
            Write-Host "Ce backend est compose de serveurs Web self service ou serveur de BDD, ils ne sont pas concernes par l'ASR" -ForegroundColor DarkRed
        }
        write-host "Aucune action a prevoir sur le backend $($Backend.Name)" -ForegroundColor Cyan
    }
}
else {
    write-host "Le Backend $($Backend.Name) n'a aucun NIC ou IP associee" -ForegroundColor Red
}



