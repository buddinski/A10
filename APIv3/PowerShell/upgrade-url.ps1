﻿#title           :upgrade-url.ps1
#description     :This script will upgrade the A10 device using a URL
#author		     :Brandon Marlow
#date            :07/11/17
#version         :2.10
#usage		     :upgrade-url.ps1 -device [device] -detailed -reboot
#==============================================================================

#get the params



Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$device,

   [Parameter(Mandatory=$True)]
   [string[]]$image,

   [Parameter(Mandatory=$True)]
   [string[]]$url,

   [Parameter(Mandatory=$False)]
   [switch]$detailed,

   [Parameter(Mandatory=$False)]
   [switch]$reboot
)


Add-Type @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public class ServerCertificateValidationCallback
    {
        public static void Ignore()
        {
            ServicePointManager.ServerCertificateValidationCallback += 
                delegate
                (
                    Object obj, 
                    X509Certificate certificate, 
                    X509Chain chain, 
                    SslPolicyErrors errors
                )
                {
                    return true;
                };
        }
    }
"@
 
[ServerCertificateValidationCallback]::Ignore();

#force TLS1.2 (necessary for the management interface)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;



if ($detailed -eq $True){
    $detaileduri = "detailed-resp=true"
    }

if ($reboot -eq $True){
    $rebooturi = "reboot=true"
    }

if (($detailed -ne $True) -and ($reboot -ne $True)){
    $apipath = "/axapi/v3/upgrade/hd"
    }

else{
    $apipath = "/axapi/v3/upgrade/hd?$detaileduri&$rebooturi"
    }

#authenticate
. ".\auth.ps1" $device
#build the json body
#the url format needs to be user:password@host/path/to/the/file
$body = @"
{"hd":{"image":"$image","use-mgmt-port":1,"file-url":"$url"}}
"@

Write-Host $body

#send the request to create the real server
try
    {
        $output = Invoke-WebRequest -Uri https://$adc$apipath -ContentType application/json -Headers $headers -Method Post -Body $body -TimeoutSec 10000000
    }

catch
    {
        Write-Output $_.Exception
    }

#write the result of the commands to the console

Write-host "writing output"

Write-Host $output

write-host "writing status code"

Write-Host $output.StatusCode  

#lets go ahead and log off
. ".\logoff.ps1" $adc