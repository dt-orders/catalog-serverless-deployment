#!/bin/bash

createDB()
{
    
    dbservername="dtorders-db-$randomIdentifier"
    dbusername="dtordersdbadmin"
    dbpassword="Workshop123#"

    echo "create resource group"
    az group create --name $resourceGroup --location "$azlocation" 

    echo "Creating MYSQL database"
    dbcreate=$(create-db-instance )

    #get the connection string from dbcreate command to be used later 
    dbConnectionString=$(echo $dbcreate | jq '.connectionString')

    #get the hostname from the dbcreate command to be use later
    dbhostname=$(echo $dbcreate | jq '.host')

    #trimming quotes to  use with mysql command later
    dbhostname=$(echo $dbhostname | tr -d '"')
    
    #create catalog db using mysql commands
    dbcreate=$(mysql --host $dbhostname --user $dbusername --password=$dbpassword -e "create database Catalog; GRANT ALL PRIVILEGES ON new_db.* TO dtordersdbadmin@localhost IDENTIFIED BY '$dbpassword'" > /dev/null 2>&1)

    #populate the catalog db
    dbpopulate=$(mysql --host $dbhostname --user $dbusername --password=$dbpassword catalog < catalog.sql)

    #create db.json to use in createFunction to populate as environment variables
    createdbjson=$(jq -n --arg dbusername "$dbusername" --arg dbpassword "$dbpassword" --arg dbhostname "$dbhostname" '{USER_NAME: $dbusername, PASSWORD: $dbpassword, RDS_HOST: $dbhostname, DB_NAME: "catalog"}' > db.json)

    
}

createFunction()
{
    
    s3storage="dtordfunc$randomIdentifier"
    lambdafuncName=dt-orders-catalog-$randomIdentifier

    #create Storage Account for function
    creates3Storage=$(create-bucket)

    #create FunctionApp
    createAzFunction=$(create-function)

    #deploy the code to FunctionApp
    deployCodeToFunction=$(deploy-function-code )

    #check if function code deployment is complete
    deploymentStatus=$(echo $deployCodeToFunction | jq '.complete')


    #set CORS so that you can test function in AWS Portal?  (Might not be needed for AWS, but was needed for Azure)
    setCors=$(az functionapp cors add -g $resourceGroup  -n $azfuncName --allowed-origins https://portal.azure.com)

    #set Function Env Variables for DB Connection
    setAppConfigonAzFunc=$(set-environment-variables-lambda @db.json)
}



#main

let "randomIdentifier=$RANDOM*$RANDOM"
#resourceGroup="serverless-azfunc-$randomIdentifier"
awsregion="eastus"
awsdeploymentCodeZip="az-catalog-function-withOtel-v2.zip"
#aztest="1"
create_serverless_resource_group
createDB
createFunction