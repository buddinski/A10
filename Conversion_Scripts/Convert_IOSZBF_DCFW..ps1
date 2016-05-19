﻿#title           :Convert_IOSZBF_DCFW.ps1
#description     :This script will take an IOS configuration using ZBF and convert it to the appropriate A10 config
#author		     :Brandon Marlow
#date            :05/17/2016
#version         :.9
#usage		     :Convert_IOSZBF_DCFW.ps1 -file [IOS config] >> OUTPUTFILENAME.txt
#==============================================================================

#get the params


Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$file

)



function ConvertWCtoCIDR($WC){
    $octet = $WC -split "\."
    $a = 255 - $octet[0]
    $b = 255 - $octet[1]
    $c = 255 - $octet[2]
    $d = 255 - $octet[3]
    $SM = "" + $a + "." + $b + "." + $c + "." + $d + ""
    Convert-RvNetSubnetMaskClassesToCidr($SM)
    #Write-Host $subnetMaskCidr
    

}

###Here be dragons###

Function Convert-RvNetSubnetMaskClassesToCidr($SubnetMask){ 
   
    [int64]$subnetMaskInt64 = Convert-RvNetIpAddressToInt64 -IpAddress $SubnetMask 
 
    $subnetMaskCidr32Int = 2147483648 # 0x80000000 - Same as Convert-RvNetIpAddressToInt64 -IpAddress '255.255.255.255' 
 
    $subnetMaskCidr = 0 
    for ($i = 0; $i -lt 32; $i++) 
    { 
        if (!($subnetMaskInt64 -band $subnetMaskCidr32Int) -eq $subnetMaskCidr32Int) { break } # Bitwise and operator - Same as "&" in C# 
 
        $subnetMaskCidr++ 
        $subnetMaskCidr32Int = $subnetMaskCidr32Int -shr 1 # Bit shift to the right - Same as ">>" in C# 
    } 
 
    # Return 
    $subnetMaskCidr 
}


###Here be bigger dragons###

Function Convert-RvNetIpAddressToInt64($IpAddress) { 
  
    $ipAddressParts = $IpAddress.Split('.') # IP to it's octets 
 
    # Return 
    [int64]([int64]$ipAddressParts[0] * 16777216 + 
            [int64]$ipAddressParts[1] * 65536 + 
            [int64]$ipAddressParts[2] * 256 + 
            [int64]$ipAddressParts[3]) 
}


##Cisco auto converts ports to protocol names which makes things complicated
##Here we build a a dictionary with a port to protocol name mapping of the common IOS protocol conversions
$ports = Import-Csv -Path port-dictionary.csv
$portdictionary=@{}
foreach ($port in $ports){
    $portdictionary[$port.Description]=$port.port
}

#Simple function used to determine if a string value is numeric
function isNumeric ($x) {
    try {
        0 + $x | Out-Null
        return $true
    } catch {
        return $false
    }
}













#load the file with the ACL
$filecontents = Get-Content $file



#Get the zone pairs and their associated service-policy

    #create the hash table for the line numbers of the zone-pair and policy
    $zonepairandpolicylines = @{} 
    
    #create a hash table for the source+dest zone and service-policy pairs
    $zonepairandpolicy = @{}

    #create a hash table for the source+dest zone and the associated classmap
    $zonepairandclassmap = @{}

    #create a hash table for the source+dest zone and the associated ACL
    $zonepairandacl = @{}

    #create the zone pair index
    $zpindex = 1

#run through the policy and find any lines that use 'zone-pair' and store the line number in a hash table
Foreach ($line in $filecontents){

    If ($line.StartsWith("zone-pair") -eq "True"){
       $begin = $filecontents.IndexOf($line)
       $end = $begin + 1

       $zonepairandpolicylines.Add($zpindex,$begin)

       $zpindex = $zpindex + 1

       
        }

    }
#zonepairandpolicylines


#iterate through the hash table of lines to do stuff and determine the source and destination zone as well as the policy map associated, then put it in a new hash table
ForEach($value in $zonepairandpolicylines.Values){
 

    
    $numvalue = [int]$value
    $numnextvalue = $numvalue + 1

    $line1 = $filecontents[$numvalue]
    $line2 = $filecontents[$numnextvalue]

    $elements1 = $line1 -split " "
    
    ForEach($element in $elements1){
        
        If ($element -eq "source"){
            [int]$srcelement = $elements1.IndexOf($element)
            $srczoneelement = ($srcelement + 1)
            $srczone = $elements1[$srczoneelement]
            }
        
        If ($element -eq "destination"){
            [int]$dstelement = $elements1.IndexOf($element)
            $dstzoneelement = ($dstelement + 1)
            $dstzone = $elements1[$dstzoneelement]
            }   
        
            
        }
    $elements2 = $line2 -split " "
    $servicepolicy = $elements2[-1]



           $zonepairandpolicy.Add($srczone + "-->" +$dstzone,$servicepolicy)
           
    

    }
#$zonepairandpolicy


        
#iterate through the hash table of policy maps to get the corresponding classmaps, then put it in a new hash table
ForEach($name in $zonepairandpolicy.Keys){

    $policymap =  $zonepairandpolicy.Get_Item($name)
    ForEach($line in $filecontents){
    

        If ($line.StartsWith("policy-map type inspect " + $policymap) -eq "True"){
            $begin = $filecontents.IndexOf($line)
            
            $end = $begin + 1

            $classmapline = $filecontents[$end]

            $elements = $classmapline -split " "


            $classmap = $elements[-1]
            }
        }
    $zonepairandclassmap.Add($name,$classmap)
}
#$zonepairandclassmap


#iterate through the hash table of policy maps to get the corresponding classmaps, then put it in a new hash table
ForEach($name in $zonepairandclassmap.Keys){
    
    $classmap =  $zonepairandclassmap.Get_Item($name)
    ForEach($line in $filecontents){

        If ($line.StartsWith("class-map type inspect match-all " + $classmap) -eq "True"){
            $begin = $filecontents.IndexOf($line)

            $end = $begin + 1

            $aclline = $filecontents[$end]

            $elements = $aclline -split " "


            $acl = $elements[-1]
            }
        }
    $zonepairandacl.Add($name,$acl)
}#
$zonepairandacl
pause

#iterate through the hash table of acls to get the entries for each ACL

$num = 1
ForEach($name in $zonepairandacl.Keys){
    
    $acl =  $zonepairandacl.Get_Item($name)

    ForEach($line in $filecontents){

        If ($line.Equals("ip access-list extended " + $acl) -eq "True"){
            $aclarray = @()
            $acldef = $filecontents.IndexOf($line)
            $acldef = $acldef + 1

            $aclstart = $filecontents | select -Skip $acldef
            
            $zonepairandaclentry = $zonepairandacl.GetEnumerator() | Where-Object -Match -Property "value" -value $acl
            
            $zonepair = $zonepairandaclentry.key
            $srczone,$dstzone = $zonepair.split('-->')
            
            ForEach($aclline in $aclstart){
                
                If ($aclline.StartsWith(" ") -eq "True"){
                    $aclline = $aclline.Trim()
                    $aclarray = $aclarray += $aclline
                    }
                Else{
                    
                    #split each line into an array
                    Foreach ($acl in $aclarray){
                        $element = $acl -split " "

                        ###Start writing the rule
        
                            ##Write your rule number        
                            Write-Output $("Rule " + $num + "")
                            Write-Output $(" action " + $element[0] + "")

                            ##Source address block
        
                            ##If format is permit udp host
                            If ($element[2] -eq "host"){
                                Write-Output $(" source ipv4-address " + $element[3] + "")
                                }
        
                            ##If format is permit udp any
                            ElseIf ($element[2] -eq "any"){
                                Write-Output " source ipv4-address any"
                                }
        
                            ##If we don't match the first two 
                            Else {
                                Write-Output $(" source ipv4-address " + $element[2] + "/" + $(ConvertWCtoCIDR($element[3])))
                                }
        
                            ##Putting in the source zone
                            Write-Output $(" source zone " + $srczone + "")
        
        
                            ###Destination Address Block

                            ##If format is permit udp 1.1.1.1 0.0.0.0 host 2.2.2.2 eq 53
                            If ($element[4] -eq "host"){
                                Write-Output $(" dest ipv4-address " + $element[5] + "")
                                }
        
                            ##If format is permit udp 1.1.1.1 0.0.0.0 any eq 53
                            ##Or if format is permit udp any any eq 53
                            ElseIf ($element[3] -eq "any" -Or $element[4] -eq "any"){
                                Write-Output " dest ipv4-address any"
                                }

                            ##If format is permit udp any 1.1.1.1 0.0.0.0 eq 53
                            ElseIf ($element[2] -eq "any"){
                                Write-Output $(" dest ipv4-address " + $element[3] + "/" + $(ConvertWCtoCIDR($element[4])))
                                }
        
                            ##If format is permit udp 1.1.1.1 0.0.0.0 2.2.2.2 0.0.0.0 eq 53
                            Else {
                                Write-Output $(" dest ipv4-address " + $element[4] + "/" + $(ConvertWCtoCIDR($element[5])))
                                }
        

                            ##Putting in the destination zone
                            Write-Output $(" dest zone " + $dstzone + "")
             
                            If ($element[-3] -eq "range"){

                            $port1 = isnumeric($element[-2])
                            $port2 = isnumeric($element[-1])

                                If ($port1-eq $true -And $port2 -eq $true){
                                    Write-Output $(" service " + $element[1] + " dst range " + $element[-2] + " " + $element[-1] + "")
                                    }
                

                                ElseIf ($port1 -eq $true -And $port2 -eq $false){
                                    $portnum = $portdictionary.Item($element[-1])
                                    Write-Output $(" service " + $element[1] + " dst range " + $element[-2] + " " + $portnum + "")
                                    }
           
                                ElseIf ($port1-eq $false -And $port2 -eq $true){
                                    $portnum = $portdictionary.Item($element[-2])
                                    Write-Output $(" service " + $element[1] + " dst range " + $portnum + " " + $element[-1] + "")
                                    }
           
                                ElseIf ($port1 -eq $false -And $port2 -eq $false){
                                    $portnum1 = $portdictionary.Item($element[-2])
                                    $portnum2 = $portdictionary.Item($element[-1])
                                    Write-Output $(" service " + $element[1] + " dst range " + $portnum1 + " " + $portnum2 + "")
                                    }
                                Else {
                                    Write-Output "You didn't match any"
                                    }


                                }
        
                            Else {
                                If (isNumeric($element[-1]) -eq $true){
                                    Write-Output $(" service " + $element[1] + " dst " + $element[-2] + " " + $element[-1] + "")
                                }
                                Else {
                                    $portnum = $portdictionary.Item($element[-1])
                                    Write-Output $(" service " + $element[1] + " dst " + $element[-2] + " " + $portnum + "")
                                    }
                            }

                            
                       $num = $num + 1
                        }

                    Break
                    }
                }
            }
        }
    }




#######################################



