# AzureReservedInstanceUsageCheck
  
## Why this function app ?
Just figure out this real life scenario: you manage many Azure resources and because you care about spendings, you use many "reserved instances".  
  
You manage to optimize has much as possible their usage but you can't be looking everyday on Azure RI's dashboard and you can't know everything what's being done by all OPS teams (like VM resizing change or app decommissionning).  
  
Azure currently doesn't offer any effecient solution to address this day-to-day need.  
  
This function app automatically gathers and outputs usage for "Reservations" it is allowed to by calling Azure API.  
  
Coupled with a common monitoring system (nagios, centreon, zabbix, or whatever you use), you'll automatically get alerted as soon as reservation usage drops below desired threshold.  
</br>
</br>

## Requirements
* An "app registration" account (client id, valid secret and tenant id).  
* Reader RBAC role for this account on all reservation orders you want to monitor ("reservation order" is not to be confused with "reservation"; a "reservation order" is an Azure container for "reservations").  
You can find powershell cmdlets in "set-permissions-example" folder ; reservation orders owner can execute them in a simple Azure cloudshell.  
Basically, that would be something like:  
</br>

    $orders = Get-AzReservationOrder  
    $appPrincipal = Get-AzADServicePrincipal -DisplayName "my-app-account-name"  
    foreach ($order in $orders) {  
      New-AzRoleAssignment -ObjectId $appPrincipal.id -RoleDefinitionName "Reader" -Scope $order.id  
    }  
</br>

## Installation
Once you have all the requirements, you can deploy the Azure function with de "Deploy" button below:  
  
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmatoy%2FAzureReservedInstanceUsageCheck%2Fmain%2Farm-template%2FAzureReservedInstanceUsageCheck.json) [![alt text](http://armviz.io/visualizebutton.png)](http://armviz.io/#/?load=https://raw.githubusercontent.com/matoy/AzureReservedInstanceUsageCheck/main/arm-template/AzureReservedInstanceUsageCheck.json)  
  
</br>
This will deploy an Azure app function with its storage account, app insights and "consumption" app plan.  
A keyvault will also be deployed to securely store the secret of your app principal.  
  
![alt text](https://github.com/matoy/AzureReservedInstanceUsageCheck/blob/main/img/screenshot1.png?raw=true)  
  
Choose you Azure subscription, region and create or select a resource group.  
  
* App Name:  
You can customize a name for resources that will be created.  
  
* Tenant ID:  
If your subscription depends on the same tenant than the account used to retrieve Reservations information, then you can use the default value.  
Otherwise, enter the tenant ID of the account.  
  
* Reservation Orders Reader Application ID:  
Client ID of the account used to retrieve reservations information.  
  
* Reservation Orders Reader Secret:  
Secret of the account used to retrieve reservations information.  
  
* Zip Release URL:  
For testing, you can leave it like it.  
For more serious use, I would advise you host your own zip file so that you wouldn't be subject to release changes done in this repository.  
See below for more details.  
  
* Max Concurrent Jobs:  
An API call to Azure will be made for each reservation order.  
If you have many reservation orders, you might get an http timeout when calling the function from your monitoring system.  
This value allows to make <value> calls to Azure API in parallel.  
With the default value, it will take around 40 seconds for ~100 reservations.  
  
* Signature:  
When this function will be called by your monitoring system, you likely might forget about it.  
The signature output will act a reminder since you'll get it in the results to your monitoring system.  
  
</br>
When deployment is done, you can get your Azure function's URL in the output variables.  
  
Trigger it manually in your favorite browser and eventually look at the logs in the function.  
  
After you execute the function for the first time, it might (will) need 5-10 minutes before it works because it has to install Az module. You even might get an HTTP 500 error. Give the function some time to initialize, re-execute it again if necessary and be patient, it will work.  
  
Even after that, you might experience issue if Azure takes time to resolve your newly created keyvault:  
![alt text](https://github.com/matoy/AzureReservedInstanceUsageCheck/blob/main/img/kv-down.png?raw=true)  
Wait a short time and then restart your Azure function, your should have something like:  
![alt text](https://github.com/matoy/AzureReservedInstanceUsageCheck/blob/main/img/kv-up.png?raw=true)  
</br>
</br>

## Monitoring integration  
From there, you just have to call your function's URL from your monitoring system.  
  
You can find a script example in "monitoring-script-example" folder which makes a GET request, outputs the result, looks for "CRITICAL" or "WARNING" in the text and use the right exit code accordingly.  
  
Calling the function once a day should be enough since data provided by the Azure API is usage rate on a daily basis.  
  
You can modify reservation usage "warning" and "critical" thresholds within the GET parameters of the URL (just add &warning=90&critical=80 for example).  
  
Default values are 99 and 98 percent.  
  
Be sure to have an appropriate timeout (60s or more) because if you have many reservations, the function will need some time to execute.  
  
This is an example of what you'd get in Centreon:  
![alt text](https://github.com/matoy/AzureReservedInstanceUsageCheck/blob/main/img/screenshot2.png?raw=true)  
</br>
</br>

## How to stop relying on this repository's zip  
To make your function to stop relying on this repo's zip and become independant, follow these steps:  
* remove zipReleaseURL app setting and restart app  
* in "App files" section, edit "requirements.psd1" and uncomment the line: 'Az' = '7.*'  
* in "Functions" section, add a new function called "AzureReservedInstanceUsageCheck" and paste in it the content of the file release/AzureReservedInstanceUsageCheck/run.ps1 in this repository  
