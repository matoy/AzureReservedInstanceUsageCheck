using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

#####
#
# TT 20210406 AzureReservedInstanceUsageCheck
# This script is executed by an Azure Function App
# It checks the usage of all reserved instances
# It can be triggered by any monitoring system to get the results and status
#
# warning and critical threshold can be passed in the GET parameters
#
# stats usage are taken minus 1 day from the day the function is called
#
# used AAD credentials must have read permission on reservation order 
# (reservation ORDER, not just reservation itself)
#
# API References:
# https://docs.microsoft.com/en-us/rest/api/reserved-vm-instances/reservationorder/list
# https://docs.microsoft.com/en-us/rest/api/reserved-vm-instances/reservationorder/get
#
# Usage of powershell runspaces is required since having a lot of Azure RI will
# require to make many single http requests to the Azure API.
# Runspace jobs helps to do that in a multithreaded way with concurrent jobs
#
#####

$warning = [int] $Request.Query.Warning
if (-not $warning) {
    $warning = 99
}

$critical = [int] $Request.Query.Critical
if (-not $critical) {
    $critical = 98
}

# init variables
$out = ""
$warningCount = 0
$criticalCount = 0
$usageDate = (get-date).adddays(-1).ToString("yyyy-MM-dd")
$TenantId = $env:TenantId
$applicationId = $env:ReservationOrdersReaderApplicationID
$password = $env:ReservationOrdersReaderSecret
$securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
$Credential = new-object -typename System.Management.Automation.PSCredential -argumentlist $applicationId, $securePassword
Connect-AzAccount -Credential $Credential -Tenant $TenantId -ServicePrincipal

# get token
$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)

# create http headers
$Headers = @{}
$Headers.Add("Authorization", "bearer " + "$($Token.Accesstoken)")
$Headers.Add("contenttype", "application/json")

# get reservationOrders inventory (read permission required!) from Azure API
# and filtering on "succeeded" state
$uri = "https://management.azure.com/providers/Microsoft.Capacity/reservationOrders?api-version=2019-04-01"
$reservationOrders = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers
$reservationOrdersSucceeded = $reservationOrders.value.properties | where {$_.provisioningState -eq "Succeeded"}
while ($reservationOrders.nextLink) {
	$uri = $reservationOrders.nextLink
	$reservationOrders = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers
	$reservationOrdersSucceeded += $reservationOrders.value.properties | where {$_.provisioningState -eq "Succeeded"}
}

# get usage for each reservation based on previous inventory from Azure API
# too long execution of the function would cause an http timeout from the
# monitoring system calling the function
# multithreading is required to avoid long execution time if many reservations
$MaxRunspaces = [int] $env:MaxConcurrentJobs
$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxRunspaces)
$RunspacePool.Open()
$Jobs = New-Object System.Collections.ArrayList
foreach ($reservationOrder in $reservationOrdersSucceeded) {
	$id = $reservationOrder.reservations.id.split("/")[4]
	$uri = "https://management.azure.com/providers/Microsoft.Capacity/reservationorders/$id/providers/Microsoft.Consumption/reservationSummaries?api-version=2019-10-01&grain=daily&%24filter=properties/usageDate+ge+$usageDate+AND+properties/usageDate+le+$usageDate"
    $PowerShell = [powershell]::Create()
	$PowerShell.RunspacePool = $RunspacePool
	[void]$PowerShell.AddScript({
	    Param ($uri, $Headers)
		(Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers).value
	}).AddArgument($uri).AddArgument($Headers)
	
	$JobObj = New-Object -TypeName PSObject -Property @{
		Runspace = $PowerShell.BeginInvoke()
		PowerShell = $PowerShell  
    }
    $Jobs.Add($JobObj) | Out-Null
}
while ($Jobs.Runspace.IsCompleted -contains $false) {
	$running = ($Jobs.Runspace | where {$_.IsCompleted -eq $false}).count
    Write-Host (Get-date).Tostring() "Still $running jobs running..."
	Start-Sleep 1
}
foreach ($job in $jobs) {
	$consumptions += $job.PowerShell.EndInvoke($job.Runspace)
}

# browse reservations and cook output results
foreach ($consumption in $consumptions) {
    $used = $consumption.properties.avgUtilizationPercentage
	$reservationName = ""
	$reservationOrdersSucceeded | % {if ($_.reservations.id -match $consumption.properties.reservationId) { $reservationName = $_.displayName }}
    $diff = 0
    if ($used -lt $critical - $diff) {
        $criticalCount++
        $out = "CRITICAL: reservation " + $reservationName + " is used at " + $used  + "%`n" + $out
    }
    elseif ($used -lt $warning - $diff) {
        $warningCount++
        $out = "WARNING: reservation " + $reservationName + " is used at " + $used  + "%`n" + $out
    }
	else {
        $out += "OK: reservation " + $reservationName + " is used at " + $used  + "%`n"
	}
}

# add ending status and signature to results
Write-Host $out
$signature = $env:Signature
$body = $out + "`n$signature`n"
if ($criticalCount -ne 0) {
    $body = "Status CRITICAL - Usage alert on $criticalCount reserved instance(s)`n" + $body
}
elseif ($warningCount -ne 0) {
    $body = "Status WARNING - Usage alert on $warningCount reserved instance(s)`n" + $body
}
else {
    $body = "Status OK - No usage alert on any $($reservationOrdersSucceeded.count) reserved instance(s)`n" + $body
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
