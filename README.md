# AzureReservedInstanceUsageCheck
  
## Why this function app ?
Just figure this real life scenario: you manage many Azure resources and because you care about spendings, you use many "reserved instances".  
You manage to optimize has much as possible their usage but you can't be looking everyday on Azure RI's dashboard and you can't know everything being done in OPS (like VM resizing change or app decommissionning).  
Azure currently doesn't offer any effecient solution to address this day-to-day need.  
This function app automatically gathers and outputs usage for 'Reservations' it is allowed to by calling Azure API.  
Coupled with a common monitoring system (nagios, centreon, zabbix, or whatever you use), you'll will automatically get alerted as soon as reservation usage drops below desired threshold.  
</br>

## Requirements
An "app registration" account (client id, valid secret and tenant id).  
Reader RBAC role for this account on all reservation orders you want to monitor.  
You can find powershell cmdlets in 'set-permissions-example' folder ; reservation orders owner can execute them in a simple Azure cloudshell.  
Basically, that would be something like:  

    $orders = Get-AzureRmReservationOrder  
    $appPrincipal = Get-AzADServicePrincipal -DisplayName "my-app-account-name"  
    foreach ($order in $orders) {  
      New-AzRoleAssignment -ObjectId $appPrincipal.id -RoleDefinitionName "Reader" -Scope $order.id  
    }  
</br>

## Installation
Once you have all the requirements, you can deploy the Azure function with de "Deploy" button below:  
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmatoy%2FAzureReservedInstanceUsageCheck%2Fmain%2Farm-template%2FAzureReservedInstanceUsageCheck.json)
  
This will deploy an Azure app function with its storage account and app insights objects and a 'consumption' app plan.  
A keyvault will also be deployed to securely store the secret of your app principal.  
  
![alt text](https://github.com/matoy/AzureReservedInstanceUsageCheck/blob/main/img/screenshot1.png?raw=true)  
  
Choose you Azure subscription, region and create or select a resource group.  
  
App Name:  
You can customize a name for the resources that will be created.  
  
Tenant ID:  
If your subscription depends on the same tenant than the account used to retrieve Reservations information, then you can use the default value.  
Otherwise, enter the tenant ID of the account.  
  
Reservation Orders Reader Application ID:  
Client ID of the account used to retrieve reservations information.  
  
Reservation Orders Reader Secret:  
Secret of the account used to retrieve reservations information.  
  
Zip Release URL:  
For testing, you can leave it like it.  
For more serious use, I would advise you host your own release so that you wouldn't be subject to release changes done in this repository.  
  
Max Concurrent Jobs:  
An API call to Azure will have to be made for each reservation order.  
If you have many reservation orders, you might get an http timeout when calling the function from your monitoring system.  
This value allows to make <value> calls to Azure API in parallel.  
With the default value, it will take around 40 seconds for  ~100 reservations.  
  
Signature:  
When this function will be called by your monitoring system, you likely would forget about it.  
The signature output will act a reminder since you'll get in the result to your monitoring system.  
  
When deployment is done, you can get your Azure function's URL in the output variables.  
Trigger manually and in your favorite browser look and eventually at the logs in the function.  
It might need a couple of minutes before it works because the function has to install Az module the first time  
</br>

## Monitoring integration  
From there, you just have to call your function's URL from your monitoring system.  
You can find a script example in monitoring-script-example folder which makes a GET request, outputs the result and looks for "CRITICAL" or "WARNING" in the text and use the right exit code accordingly.  
Calling the function pnce a day should be enough since information given by the Azure API are in a daily basis.  
You can modify reservation usage 'warning' and 'critical' thresholds within the get paramaters of the URL (just add &warning=90&critical=80 for example).  
Default values are 99 and 98.  
  
This is an example of what i get in Centreon:  
![alt text](https://github.com/matoy/AzureReservedInstanceUsageCheck/blob/main/img/screenshot2.png?raw=true)  
