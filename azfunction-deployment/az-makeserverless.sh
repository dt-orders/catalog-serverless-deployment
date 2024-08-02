#!/bin/bash

create_serverless_resource_group()
{
    resourceGroup="serverless-azfunc-$randomIdentifier"
    if [ "$(does_rsgroup_exist)" == "true" ]; then
            echo "Skipping, resource group $resourceGroup exists"
            echo ""
        else
            echo ""
            echo "Provisioning resource group: $resourceGroup"
            echo "--------"
             az group create \
              --location "$azlocation" \
              --name "$resourceGroup"
            echo "-------"
        fi
 
}

does_rsgroup_exist()
{
  resourceGroup="serverless-azfunc-$randomIdentifier"
  GROUPCHECK=$(az group show -g $resourceGroup --output tsv --query id 2>&1 | grep "NotFound")
  if [ -z "$GROUPCHECK" ]; then
    echo true
  else
    echo false
  fi
}

createDB()
{
    #let "randomIdentifier=$RANDOM*$RANDOM"
    #vNet="dt-ordersdb-$randomIdentifier"
    #resourceGroup="serverless-azfunc-$randomIdentifier"
    #vNetAddressPrefix="10.0.0.0/16"
    #azlocation="eastus"
    #subnet="subnet-$randomIdentifier"
    #subnetAddressPrefix="10.0.1.0/24"
    #rule="rule-$randomIdentifier"

    dbservername="dtorders-db-$randomIdentifier"
    dbusername="dtordersdbadmin"
    dbpassword="Workshop123#"

    #echo "create resource group"
    #az group create --name $resourceGroup --location "$azlocation" 

    echo "Creating MYSQL database"
    dbcreate=$(az mysql flexible-server create --resource-group $resourceGroup --name $dbservername --location $azlocation --admin-user $dbusername --admin-password $dbpassword --sku-name Standard_B1ms --tier Burstable --public-access 0.0.0.0 --yes)

    dbConnectionString=$(echo $dbcreate | jq '.connectionString')
    dbhostname=$(echo $dbcreate | jq '.host')

    #trimming quotes to  use with mysql command later
    dbhostname=$(echo $dbhostname | tr -d '"')
    
    #create catalog db
    dbcreate=$(mysql --host $dbhostname --user $dbusername --password=$dbpassword -e "create database Catalog; GRANT ALL PRIVILEGES ON new_db.* TO dtordersdbadmin@localhost IDENTIFIED BY '$dbpassword'" > /dev/null 2>&1)

    #populate the db
    dbpopulate=$(mysql --host $dbhostname --user $dbusername --password=$dbpassword catalog < catalog.sql)

    #create db.json
    createdbjson=$(jq -n --arg dbusername "$dbusername" --arg dbpassword "$dbpassword" --arg dbhostname "$dbhostname" '{USER_NAME: $dbusername, PASSWORD: $dbpassword, RDS_HOST: $dbhostname, DB_NAME: "catalog"}' > db1.json)

    
}

createFunction()
{
    #let "randomIdentifier=$RANDOM*$RANDOM"
    #resourceGroup="gurbani-serverless-azfunc"

    azstorage="dtordfunc$randomIdentifier"
    azfuncName=dt-orders-catalog-$randomIdentifier

    #create Storage Account for function
    createAzStorage=$(az storage account create --name $azstorage --location $azlocation --resource-group $resourceGroup --sku Standard_LRS --only-show-errors)

    #create FunctionApp
    createAzFunction=$(az functionapp create --resource-group $resourceGroup --consumption-plan-location $azlocation --runtime python --runtime-version 3.10 --functions-version 4 --name $azfuncName --os-type linux --storage-account $azstorage --disable-app-insights)

    #deploy the code to FunctionApp
    deployCodeToFunction=$(az functionapp deployment source config-zip --resource-group $resourceGroup  --name $azfuncName --src $AzdeploymentCodeZip --build-remote true )
    deploymentStatus=$(echo $deployCodeToFunction | jq '.complete')

    setCors=$(az functionapp cors add -g $resourceGroup  -n $azfuncName --allowed-origins https://portal.azure.com)

    #set Function Env Variables for DB Connection
    setAppConfigonAzFunc=$(az functionapp config appsettings set -g $resourceGroup -n $azfuncName --settings @db1.json)
    
    #get FunctionURL to store and use for later
    AZ_FUNCTION_URL_findByNameContains=$(az functionapp function show --function-name findbyNameContains --resource-group $resourceGroup --query "invokeUrlTemplate" --output tsv --name $azfuncName)
    AZ_FUNCTION_URL_findByNameContains=$(echo $AZ_FUNCTION_URL_findByNameContains|tr -d '\r\n') #Remove breaklines from result

    AZ_FUNCTION_URL_ServerlessDBActions=$(az functionapp function show --function-name ServerlessDBActions --resource-group $resourceGroup --query "invokeUrlTemplate" --output tsv --name $azfuncName)
    AZ_FUNCTION_URL_ServerlessDBActions=$(echo $AZ_FUNCTION_URL_ServerlessDBActions|tr -d '\r\n') #Remove breaklines from result
}

createAPIGW()
{
    APIM_SKU="Basic"
    APIM_PUBLISHER_EMAIL="jay.gurbani@dynatrace.com"
    APIM_PUBLISHER_NAME='JayGurbani'
    azfuncName=dt-orders-catalog-$randomIdentifier
    APIMname=$azfuncName-apim
    #dispName="Name value for Azure function $azfuncName"

    apiMCreate=$(az apim create --resource-group $resourceGroup --name $APIMname --location $azlocation --sku-name $APIM_SKU --enable-managed-identity true --publisher-email $APIM_PUBLISHER_EMAIL --publisher-name $APIM_PUBLISHER_NAME)
    replaceUrl=$(sed -i 's/dt-orders-catalog1-apim.azure-api.net/test-apim.azure-api.net/g' apim.json)
    replaceFunc=$(sed -i "s/dt-orders-catalog1/$azfuncName/g" apim.json)
    importAzFunctionAPI=$(az apim api import -g $resourceGroup --service-name dt-orders-catalog-96319179-apim --path MyApi --specification-path apim.json --specification-format OpenApiJson)

    #create  an AppKey in Azurefunction for API Mgmt
    createAPIKey=$(az functionapp keys set -g $resourceGroup  -n $azfuncName --key-type functionKeys --key-name apim-$APIMname)
    apimAPIKey=$(echo $createAPIKey | jq '.value')

    #trim quotes from APiKey variable
    apimAPIKey=$(echo $apimAPIKey | tr -d '"')
    setNameVal=$(az apim nv create --service-name $APIMname -g $resourceGroup --named-value-id $azfuncName-key --display-name name --value $apimAPIKey)

    #set Azure Function as backend to APIM with Powershell scripts

    #apimContext=$(pwsh -c New-AzApiManagementContext -ResourceGroupName $resourceGroup -ServiceName $APIMname)
    #apimCredential=$(pwsh -c New-AzApiManagementBackendCredential -AuthorizationHeaderScheme basic -Header @{\"x-functions-key\" = @("{{$azfuncName-key}}")} ) 

    replaceRGinPS=$(sed -i "s/RESOURCE_GROUP_CHANGEME/$resourceGroup/g" setbacked.ps1)
    replaceRandomIDinPS=$(sed -i "s/RANDOM_CHAGEME/$randomIdentifier/g" setbacked.ps1)
}

updateK8AndDockerWithFuncURL()
{
  pathToK8Manifest=""
  pathToDockerYML=""

  replaceFuncFindbyName=$(sed -i "s/CHANGEME_FINDBYNAME/$AZ_FUNCTION_URL_findByNameContains/g" $pathToK8Manifest/catalog-service-serverless.yml)
  replaceFuncDBActions=$(sed -i "s/CHANGEME_SERVERLESS_DB_ACTIONS/$AZ_FUNCTION_URL_ServerlessDBActions/g" $pathToK8Manifest/catalog-service-serverless.yml)

  replaceFuncFindbyName=$(sed -i "s/CHANGEME_FINDBYNAME/$AZ_FUNCTION_URL_findByNameContains/g" $pathToDockerYML/docker-compose-services-serverless.yml)
  replaceFuncDBActions=$(sed -i "s/CHANGEME_SERVERLESS_DB_ACTIONS/$AZ_FUNCTION_URL_ServerlessDBActions/g" $pathToDockerYML/docker-compose-services-serverless.yml)
}

#main

let "randomIdentifier=$RANDOM*$RANDOM"
resourceGroup="serverless-azfunc-$randomIdentifier"
azlocation="eastus"
AzdeploymentCodeZip="az-catalog-function-withOtel-v2.zip"
#aztest="1"
create_serverless_resource_group 
createDB 
createFunction
#updateK8AndDockerWithFuncURL