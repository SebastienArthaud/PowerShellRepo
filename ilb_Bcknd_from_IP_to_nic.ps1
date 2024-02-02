<#
Auteur : Sebastien ARTHAUD
Date : 15/06/23
Fonction : Ce script modifie la configuration des regles de load balancer pour que ces derniers pointent vers les cartes réseaux des backend et non les adresses IP.

Detail : Tout d'abord le script creer des nouveaux Backend pool en fonction des existants en les configurant avec les NIC et non les adresses IP

Dans un second lieu, le script va modifier toutes les regles associees a chaque backen pool existant pour les changer avec les nouveaux pool.

Parametres en entree : 
        - resourceGroupName : Nom du resource group dans lequel se trouve le load balancer
        - Lb : Nom du Load balancer a configurer
#>


param(
    [Parameter(Mandatory = $true)][string]$sid,
    [Parameter(Mandatory = $true)][string]$resourceGroupName,
    [switch]$Apply
)

$Env = $resourceGroupName.Split('-')[-1]

Set-AzContext -Subscription $sid | Out-Null

###################Declaration de fonctions##############################
#Cette focntion va definir le nom du nouveau Backend.
Function GetNewBackEndName {
    param(
        [String]$Environnement,
        [String]$BriqueHastus
    )
        $Brique = ""
        switch($BriqueHastus)
        {
            "co"{$Brique = "connect"}
            "pt"{$Brique = "scheduler"}
        }

        if ($Environnement -eq "prd" -or $Environnement -eq "ppd")
        {
            $NewBackendName = "Backend-Pool-lb-pgs-$Brique-$Environnement-pr"

            
        }
        else {
            $NewBackendName = "Backend-Pool-lb-pgs-$Brique-$Environnement-np"
        }
        
        
        return $NewBackendName
}
########################################################################



# Verification de la souscription. Il faut se trouver sur "e.sncf mobilite nprd". Sinon, nous devons bien verifier la souscription dans laquelle nous nous trouvons ! surtout si cest la prod...
if ($sid.ToLower() -eq "57197bef-475c-4be3-85ed-057c27149ed1")
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
$Lb = $LoadBalancers[$Choix - 1]

#Recuperation des backendpool existant sur le load balancer
$LbBackend = Get-AzLoadBalancerBackendAddressPool -ResourceGroupName $resourceGroupName -LoadBalancerName $Lb.Name

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
while($BriqueHastus -ne "pt" -and $BriqueHastus -ne "co")
{
    $BriqueHastus = Read-Host "Quel type de brique Hastus se trouve derriere ce backend $($Backend.Name) ? ('co' ou 'pt')"

    if ($BriqueHastus -ne "pt" -and $BriqueHastus -ne "co")
    {
        Write-Warning "Veuillez entrer une valeur valide ! : 'co' ou 'pt'"
    }
}

$BackendAssociatedRule = @()
$NicName = ""

Write-Host ""
Write-Host "Backend traite : $($Backend.Name)"
Write-Host "Brique Hastus liee a ce backend : $BriqueHastus"

foreach ($rule in $Backend.LoadBalancingRules)
{
    $RuleName = $rule.Id.SPlit('/')[-1]
    $BackendAssociatedRule += $RuleName
}

#Dans chaque Backend, il peut y avoiir plusieurs adresses IP. Ici nous recuperons toutes ces adresse IP via leur Id AZURE et nous allons
#Recuperer leur nom.


if(!($Backend.LoadBalancerBackendAddresses))
{
    write-host "Le Backend $($Backend.Name) n'a aucun NIC ou IP associee" -ForegroundColor Red
    exit
}

#Regroupement des cartes dans le resource group avec leur adresse IP, ce sera réutilisé pour faire correspondre l'IP du Backend Pool avec ces IP regroupées.
$NicsIPs= @()
Get-AzVM -ResourceGroupName $resourceGroupName | ForEach-Object {
    $VMName = $_.Name
    $NICs = $_.NetworkProfile.NetworkInterfaces

    $NICs | ForEach-Object {
        $HashId = $_.Id.Split('/')
        $NicRG = $HashId[4]
        $NicName = $HashId[-1]

        $Object = Get-AzNetworkInterface -ResourceGroupName $NicRG -Name $NicName

        $Object.IpConfigurations | foreach-object {
            $NICObject = New-Object PSObject -Property @{
                VMName = $VMName
                Name = $Object.Name
                IpConfigName = $_.name
                IpAddress = $_.PrivateIPAddress
                rg = $NicRG
            }
            $NicsIPs += $NICObject
        }
    }
}

$NicToReconfigure = @()
$BackEndOK = $False

#Vérification des backen, Aucun Backend ne doit être ne mode NIC ou, aucune VM associée à chaque backend ip ne doit être une des vm suivantes : 
foreach($BackendAddress in $Backend.LoadBalancerBackendAddresses)
{
    if($BackendAddress.NetworkInterfaceIpConfiguration)
    {
        $BackendOK = $True
    }
    else
    {
        $IpAddress = $BackendAddress.IpAddress
        # on récupère l'adresse IP correspondante dans la liste de toutes les cartes réseaux récupérées avant (ligne : 137), on exclue les machines de type web self service, BD...etc.
        $NicToReconfigure += $NicsIPs | where-object {$_.IpAddress -eq $IpAddress -and  ($_.Name -notlike "*wzht*" -and $_.Name -notlike "*wzbd*" -and $_.Name -notlike "*wzex*")}
    }
    
}

if(!$NicToReconfigure)
{
    Write-Output "Aucune NIC conforme n'a pu etre trouvee (surement un backend pool composé de VM web selfservice ou base de donnees)"
    exit
}

if ($BackEndOK -eq $True)
{
    write-warning "Attention, $($Backend.Name) est déjà en mode NIC"
    exit
}

$NewBackendName = GetNewBackEndName -Environnement $Env -BriqueHastus $BriqueHastus    #Convention de Nommage du nouveau Backend
Write-Output "Nous allons reconfigurer les NICs : "
$NicToReconfigure
write-output "Nom nouveau backend pool : $NewBackendName"
write-host "Regles associees a ce Backend : $($BackendAssociatedRule | ForEach-Object {"$_, "})"


if($Apply)
{
    $Now = get-date  -Format "HH:mm:ss"
    Write-Host "$Now - $($Lb.Name) création du Backend Pool $NewBackendName dans le RG $resourceGroupName" -ForegroundColor Green

    $NewBckPool = New-AzLoadBalancerBackendAddressPool -Name $NewBackendName -LoadBalancer $Lb
    $NicToReconfigure | foreach-object {

        $Now = get-date  -Format "HH:mm:ss"
        Write-Host "$Now - configuration de la NIC $($_.Name) dans le backend pool $($NewBckPool.Name) dans le RG $resourceGroupName " -ForegroundColor Green
        
        $Nic = Get-AzNetworkInterface -ResourceGroupName $_.rg -Name $_.Name
        Set-AzNetworkInterfaceIpConfig -name $_.IpConfigName -NetworkInterface $Nic -LoadBalancerBackendAddressPool $NewBckPool | out-null
        $Nic | Set-AzNetworkInterface
    }

    foreach ($rule in $Backend.LoadBalancingRules)
    {
        
        
        #recuperation du nom de la regle existante via son Id 
        $RuleName = $rule.Id.Split('/')[-1]
        $Now = get-date  -Format "HH:mm:ss"
        Write-Host "$Now - configuration de règle $RuleName " -ForegroundColor Green

        #Recuperation de la configuration de la regle existante
        $OldRuleConfig = get-AzLoadBalancerRuleConfig -LoadBalancer $Lb -Name $RuleName
        #Recuperation de la configuration de l'adresse IP en Front existante
        $RuleFrontEndIpConfig = Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $Lb -Name (($OldRuleConfig.FrontendIPConfiguration.Id).Split('/'))[-1]
        
        # recuperation du health Probe existant et configure sur la regle deja en place
        $ProbeToConfigure = get-AzLoadBalancerProbeConfig -LoadBalancer $Lb -Name (($OldRuleConfig.Probe.Id).Split('/'))[-1]
        

        <#
        Nécessaire car, entre la ligne 82, ou on récupère l'objet load balancer qu'on veut modifier et maintenant, un backend pool a été
        créé. Donc si on ne recharge pas l'objet, il sera incapable de modifier le backend pool ca ril n'existe pas dans l'objet chargé
        à la ligne 82.
        #>

        $Now = get-date  -Format "HH:mm:ss"
        Write-Host "$Now - rechargement du load balancer $($Lb.Name) dans le code " -ForegroundColor Green


        $LbProperties = Get-AzLoadBalancer -ResourceGroupName $resourceGroupName -name $Lb.Name
        
        

        $Now = get-date  -Format "HH:mm:ss"
        Write-Host "$Now - Liaison de la règle $RuleName au backend $($NewBckPool.Name)" -ForegroundColor Green

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
          -BackendAddressPool $NewBckPool `
          -FrontendIpConfiguration $RuleFrontEndIpConfig `
          -Protocol $OldRuleConfig.Protocol `
          -Probe $ProbeToConfigure `
          -FrontendPort $OldRuleConfig.FrontendPort `
          -BackendPort $OldRuleConfig.BackendPort `
          -LoadDistribution $OldRuleConfig.LoadDistribution `
          @extraArgs | out-null


          $Now = get-date  -Format "HH:mm:ss"
          Write-Host "$Now - Mise à jour du load balancer $($LbProperties.Name) " -ForegroundColor Green
        $LbProperties | set-AzLoadBalancer
    }
    
}

    




