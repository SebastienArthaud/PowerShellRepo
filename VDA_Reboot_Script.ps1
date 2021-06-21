<#

Citrix_Universal_Rolling_Reboot-24/7

AUTHOR : Sebastien Arthaud

DATE : 05/12/2021

VERSION : 1.0

This Script will be able to reboot your VDA servers from a specified delivery group at any time of the week. 


HOW DOES IT WORK ? : By specifying a percentage of server to reboot. The script will execute the following tasks :

    - It will calculate the number of machine to reboot at a time 
      EXAMPLE : IF there are 20 servers in a delivery group and the percentage rate of machine to keep online is equal to 80%,
                The Script will reboot 4 servers at a time.

    - It will turn on the maintenance mode on the servers to reboot

    - It will wait for the sessions to be closed on the servers to reboot

    - Once they are empty, it will reboot the corresponding server.

    - Once all the servers to reboot are rebooted, it will do the same thing for the next servers until there is no server to reboot anymore.




PARAMETERS : 

 - DeliveryGroup : Name of the Delivery group to treat

 - ServerType : "V" (Virtual) or "P" (Physical)

 - HoldPercent : Number of servers to keep alive at a time, the others will be rebooted

 - TimeOut : If the script has been launched a longer time ago than the TimeOut parameters, it will stop

 - OutFilePath : Log file


#>


[CmdletBinding(SupportsShouldProcess = $False, ConfirmImpact = "None", DefaultParameterSetName = "") ]

Param([parameter(
Position = 0,
Mandatory=$False)
]
[Alias("DG")]
[ValidateNotNullOrEmpty()]
[string]$DeliveryGroup="DG NAME",

[parameter(
Position = 1,
Mandatory=$False)
]
[Alias("ST")]
[ValidateNotNullOrEmpty()]
[string]$ServerType="V",

[parameter(
Position = 1,
Mandatory=$False)
]
[Alias("PCO")]
[ValidateNotNullOrEmpty()]
[decimal]$HoldPercent="50",

[parameter(
Position = 2,
Mandatory=$False)
]

[Alias("TO")]
[ValidateNotNullOrEmpty()]
[int]$TimeOut="168",


[parameter(
Position = 3,
Mandatory=$False)
]

[Alias("OF")]
[ValidateNotNullOrEmpty()]
[string]$OutFilePath=("C:\RollingReboot\Logs\")
)



Set-StrictMode -Version 2

Add-PSSnapin Citrix.* -erroraction silentlycontinue


#Error message if the percentage of the servers to reboot is to weak
$LessThanOneError = "All Session Host servers had active sessions. HoldPercent was calculated to be less than 1 server, script terminated to prevent blocking logons to the Delivery Group."


#Error message if the timeout is expired
$TimeOutError = "The script did not finish before the timeout and was therefore terminated. All servers have been returned to out of maintenance."

#percentage of machine that will be rebooted
$HoldPercent = 1-($HoldPercent/100)

#Log parameters
$ScriptStarted = Get-Date
$logDate = Get-Date -format "yyyyMMdd-HHmm"

Write-Host 'r'n "Continual Progress Report is also being saved to" $($OutFilePath) -BackgroundColor Yellow -ForeGroundColor DarkBlue
Write-Host 'r'n "Script will timeout after" $($ScriptStarted.AddHours($TimeOut)) -BackgroundColor Yellow -ForeGroundColor DarkBlue

#Get all servers for specified desktop group and exclude servers alredy in Maintenance Mode

[System.Collections.ArrayList]$Servers = Get-BrokerMachine -DesktopGroupName $DeliveryGroup | Where-Object {$_.InMaintenanceMode -ne "True"}

#Create RebootList Array

[System.Collections.ArrayList]$RebootList = @()

Foreach ($Server in $Servers)
{
$obj = New-Object -TypeName PSObject
$obj | Add-Member -MemberType NoteProperty -Name DNSName -Value $Server.DNSName
$obj | Add-Member -MemberType NoteProperty -Name MachineName -Value $Server.MachineName
$obj | Add-Member -MemberType NoteProperty -Name InMaintenanceMode -Value $False
$obj | Add-Member -MemberType NoteProperty -Name RebootStatus -Value "Pending"
$obj | Add-Member -MemberType NoteProperty -Name RebootTime -Value ""
$obj | Add-Member -MemberType NoteProperty -Name SessionCount -Value $Server.SessionCount
$RebootList += $obj
}




<#
Start-Sleep

PARAMETERS : 
    - Seconds
    
A function that can be used in debugging that will display the time leftwhen the script is "sleeping"
#>

function Start-Sleep($seconds) {
    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity "Sleeping" -Status "Sleeping..." -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "Sleeping" -Status "Sleeping..." -SecondsRemaining 0 -Completed
}



<#
Reboot

If the Server type is Virtual, the scrit zill reboot the server through the Controller

If the server is Physical, it will directly send the shutdowm instruction through the network
#>
Function Reboot
{
    If ($ServerType -eq "V")
    {
        New-BrokerHostingPowerAction -MachineName $Server.DNSName -Action Restart | out-null
    }
    ElseIf ($ServerType -eq "P")
    {
        Restart-Computer -ComputerName $Server.DNSName
    }
}


<#
If the server didn't restart properly, it will force reboot it

If the Server type is Virtual, the scrit will reset the server through the Controller

If the server is Physical, it will directly send the shutdowm instruction through the network

#>
Function ForceReboot
{
    If ($ServerType -eq "V")
    {
        New-BrokerHostingPowerAction -MachineName $Server.DNSName -Action Reset | out-null
    }
    ElseIf ($ServerType -eq "P")
    {
        Restart-Computer -ComputerName $Server.DNSName
    }
}

<#query current rebooted server 
Check registration Status and query uptime<
If uptime is superior to 0 (example: 1 Day or more)
Server is probably stuck in shutdown
Call the Power reset to force reboot
#>



#####################################
#RebootCheck: Check if the server rebooted properly and returns the result string
#
#Parameters: $RebootTimeInitiation : The time the Reboot function was called
#
#            $ServerName : Server to check
#
##############################
Function RebootCheck
{
   
    param([String]$RebootTimeInitiation, [String]$ServerName)
    
    Write-Output "Initiation du check reboot"
    Write-Output "Date initiation du reboot : $RebootTimeInitiation"

    do
    {
        #Getting the server uptime from itself
        $Booted = Get-WmiObject -Class Win32_OperatingSystem -Computer $ServerName
        $uptime = $Booted.ConvertToDateTime($Booted.LastBootUpTime)
        
        if($uptime -eq $null) 
        {
            Start-Sleep -s 20
        }
    }until ($uptime -ne $null)


    Write-Output "Dernier reboot du serveur (récupéré depuis le serveur en direct : $uptime"

    #Comparaison between the server uptime and the time the reboot was initiated.
    #The initiated reboot time is supposed to be earlier than the server uptime. If the comparaison is negative, it means the
    #server rebooted properly
    $Comparaison = New-TimeSpan -Start $uptime -End $RebootTimeInitiation
    

    Write-Output "$Comparaison"
    

    #If the Comparaison (see above) is negative...
    if($Comparaison -lt 0)
    {
        #The server rebooted properly, we are now going to check if it register to the delivery controller.
        Write-Output "Le serveur a bien redémarré"

        #We are going to check if it is registered 10 times (every 60 seconds)
        $NbCheck = 0
        Do
        {
            #Number of tries, if it isn't registered, it will come back here until it is or until the number of tries reach the maximum value
            $NbCheck ++

            #Waiting for 60 seconds
            Start-Sleep -s 120

            #Get the VDA informations
            $RegistrationState=Get-BrokerMachine -DesktopGroupName $DeliveryGroup -DNSName $Server.DNSName

        }Until ($RegistrationState.RegistrationState -eq "Registered" -or $NbCheck -ge 3)



        #If, after 10 tries, the server is not registered yet, something went wrong. This has to be checked by the VDI Team
        if($RegistrationState.RegistrationState -eq "Unregistered" -and $NbCheck -ge 3)
        {
            Write-Output "Serveur redémarré mais pas 'registered'"
            
            return "Unregistered"
        }
        else
        {
            return "Registered"
        }
    }
    #If the comparaison is not negative, the server didn't reboot properly
    else
    {
        Write-Output "Le serveur a pas redémarré correctement"
        return "Failed"
    }

    


}




<#
CheckProgress :

Will check if all the servers have been rebooted. If the timeout parameters expires, the script will be stopped by the script
#>


Function CheckProgress
{
    <#
    If (($RebootList | Where-Object {$_.RebootStatus -eq "Rebooted"} | Measure-Object).Count -eq $RebootList.Count)
    {
        Foreach ($Server in $RebootList)
        {
            Set-BrokerMachine $Server.MachineName -InMaintenanceMode $False
            $Server.InMaintenanceMode = $False
        }
        $RebootList | Export-CSV -NoTypeInformation ($OutFilePath + $logDate + "_" + $DeliveryGroup + "_RebootScriptReport.csv")
        Write-Host "SCRIPT FINISHED: Logs and reports have been saved to" $OutFilePath -BackgroundColor Yellow -ForeGroundColor DarkBlue
        Break
    }
    #>
    If ($ScriptStarted.AddHours($TimeOut) -lt $(Get-Date))
    {
        Foreach ($Server in $RebootList)
        {
            Set-BrokerMachine $Server.MachineName -InMaintenanceMode $False
            $Server.InMaintenanceMode = $False
        }
        $RebootList | Export-CSV -NoTypeInformation ($OutFilePath + $logDate + "_" + $DeliveryGroup + "_ebootScriptReport.csv")
        Write-Host "SCRIPT OVERRAN TIMEOUT AND WAS TERMINATED: Logs and reports have been saved to" $OutFilePath -BackgroundColor Yellow -ForeGroundColor DarkBlue
        Out-File -FilePath ($OutFilePath + $logDate + "_" + $DeliveryGroup + "_RebootScriptLog.Log") -InputObject $TimeOutError
        Break
    }
}
#>

<#
ReportProgress : 

Displays the reboot progress
#>
Function ReportProgress
{
    $d = Get-Date
    $Progress = "PROGRESS REPORT issued on " + $($d.ToShortDateString()) + " at " + $($d.ToShortTimeString()) + $($rebootlist |Select-Object MachineName,RebootStatus,RebootTime,InMaintenanceMode,SessionCount| Format-Table | Out-String)
    Write-Host $Progress -BackgroundColor Yellow -ForeGroundColor DarkBlue
    Add-Content -Path ($OutFilePath + $logDate + "_" + $DeliveryGroup + "_RebootScriptProgress.txt") -Value $Progress
  
}













#If all servers have active sessions, put X% of servers ($HoldPercent) in Hold status to prevent blocking all logons to the Delivery Group

$active=@()
[System.Collections.ArrayList]$Global:InHold = @()
$active = $RebootList | Where-Object {$_.SessionCount -gt 0}
$ToHold = [System.Math]::Round(($RebootList.Count) * $HoldPercent)


#Global index of the Rebootlist tab, Very important for the script to know what servers left has to be rebooted
$Global:x = 0



<#
MakeHold : THis Function will change the reboot statusof the VDA machines to "Hold" and will turn their maintenance mode

To do it well, it will only treats the VDAs machines that are included in the next wave of machines to reboot (See explanations about HoldPercent at the top of the script)
#>
function MakeHold 
{
    If ($RebootList.Count -eq ($active | Measure-Object).Count -and $ToHold -lt 1)
    {
        $LessThanOneError | Out-File ($OutFilePath + $logDate + "_" + $DeliveryGroup + "_RebootScriptLog.Log")
        Break
    }
    Else
    {
        $Done = $False
        $z = $Global:x
        Do
        {
            foreach($d in $Global:InHold)
            {
                if($d.MachineName -eq $RebootList[$Global:x].MachineName )
                {
                    $Done = $True
                    
                
                
                }
            }

            if($Done -eq $False)
            {
                $Global:InHold += $RebootList[$Global:x]
                $RebootList[$Global:x].RebootStatus = "Hold";
                Set-BrokerMachine $RebootList[$Global:x].MachineName -InMaintenanceMode $True
                $RebootList[$Global:x].InMaintenanceMode = $True
            }
            
            
            if ($Global:x -eq ($RebootList.Count -1))
            {
                return
            }
            $Global:x++

            
        
        }
        Until ($Global:x -eq ($ToHold + $z))

    }
}





#########################################
#
#
#
#              MAIN CODE
#
#
#
#########################################


#First Wave of Hold machines
MakeHold


#This loop will not end until all the machines have been treated
while($Global:x -le ($RebootList.Count -1))
{



    #Report the progress into a log file
    ReportProgress
    CheckProgress


    #Check if machines have been put into Hold status
    If (($RebootList | Where-Object {$_.RebootStatus -eq "Hold"} | Measure).Count -gt 0)
    {
        #If yes, it will not put other machines in hold until the machines already in hold are treated
        Do
        {
        <#
            #Updating the session count of all machines in the reboot list
            foreach ($s in $RebootList)
            {
                $s.SessionCount = (Get-BrokerMachine -DesktopGroupName $DeliveryGroup -DNSName $Server.DNSName).SessionCount
            }
            #>
            Foreach ($server in $RebootList)
            {

                If ($Server.RebootStatus -eq "Hold")
                {
                        #The machine will not be rebooted if there is at least one active session on it.
                        If (((Get-BrokerMachine -DesktopGroupName $DeliveryGroup -DNSName $Server.DNSName).SessionCount) -eq 0)
                        {

                            Reboot

                            #Set the date of the reboot
                            $Server.RebootTime = Get-Date
                            

                            #This part waits for a few minutes for the server to be rebooted.
                            Start-Sleep -s 540
                            #start-sleep(540)
                    

                            #Check if the server did reboot
                            $Rebooted = RebootCheck $Server.RebootTime $Server.DNSName
                           
                            #If the server rebooted and is Registrered to the Delivery COntroller,the rebootstatus will be set to "Registrered" and the maintenance mode will be turn off
                            if ($Rebooted -eq "Registered")
                            {
                                Set-BrokerMachine $Server.MachineName -InMaintenanceMode $False
                                $Server.InMaintenanceMode = $False
                                $Server.RebootStatus = "Rebooted"
                            }
                            #If the server rebooted but was not registrered to the delivery controller, the reboot status will be set to "Unregistrered" and the maintenance mode will not be turn off.
                            elseif ($Rebooted -eq "Unregistered")
                            {
    
                                $Server.InMaintenanceMode = $True
                                $Server.RebootStatus = "Unregistered"
                            }
                            else
                            {
                                #If the Returned value is in "Failed" state, the server didn't reboot properly, we have to force the reboot, the server stays in maintenance mode
                                $Server.InMaintenanceMode = $True
                                $Server.RebootStatus = "Failed force reboot sent"

                                #Calling the force reboot function
                                ForceReboot
                                #Setting the reboot initiation time
                                $Server.RebootTime = Get-Date
                                #Waiting for 120 seconds while the server is rebooting
                                Start-Sleep -s 240
                                #start-sleep(240)


                                # we call the RebootCheck function and get the returned value
                                $Rebooted = RebootCheck $Server.RebootTime $Server.DNSName
                                if ($Rebooted -eq "Registered")
                                {
                                    Set-BrokerMachine $Server.MachineName -InMaintenanceMode $False
                                    $Server.InMaintenanceMode = $False
                                    $Server.RebootStatus = "Rebooted"
                                }
                                elseif ($Rebooted -eq "Unregistered")
                                {
    
                                    $Server.InMaintenanceMode = $True
                                    $Server.RebootStatus = "Unregistered"
                                }
                                else
                                {
                                    #If the Returned value is in "Failed" state after the force reboot, something is not well, the VDI team has to check on the server
                                    $Server.InMaintenanceMode = $True
                                    $Server.RebootStatus = "Failed"
               
                                }
               
                            }



                        }
                        ReportProgress
                        CheckProgress
                        #start-sleep(180)
						start-sleep -s 180
            

                }
            }

        }Until (($RebootList | Where-Object {$_.RebootStatus -eq "Hold"} | Measure).Count -eq 0)
    }





    #If the global index of the RebootList is equel to the number of machines in the reboot list, that means all the servers have been rebooted.
    #If not, the script keeps turning the servers left into hold status and in maintenance mode
    if ($Global:x -lt ($RebootList.Count -1))
    {
        MakeHold
    }
    else
    {$Global:x++}



}





$attachement = ($OutFilePath + $logDate + "_" + $DeliveryGroup + "_RebootScriptprogress.txt")

$smtpServer = “acmail.aircanada.ca”
$msg = new-object Net.Mail.MailMessage
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$msg.From = “VDI_infrastructure@aircanada.ca”
$msg.To.Add("sebastien.arthaud@hotmail.fr")
$msg.Subject = "Server Reboot report $DeliveryGroup "
$msg.IsBodyHtml = {​​set;true}
$msg.Body = "Rolling reboot is terminated for Delivery Group $DeliveryGroup <br>
See detailed report in attachment
"
$msg.Attachments.Add($attachement)
$smtp.Send($msg)