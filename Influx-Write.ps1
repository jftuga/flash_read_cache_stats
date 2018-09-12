
#----------------------------------------------------------[Initialisations]----------------------------------------------------------

[CmdletBinding()]
PARAM(	
	[parameter(ValueFromPipeline=$true,
				ValueFromPipelineByPropertyName=$true,
				Mandatory=$true)]
	[string]$measurement,
	[parameter(ValueFromPipeline=$true,
				ValueFromPipelineByPropertyName=$true,
				Mandatory=$false)]
	[string]$tags,
	[parameter(ValueFromPipeline=$true,
				ValueFromPipelineByPropertyName=$true,
				Mandatory=$true)]
	[string]$values,
	[parameter(ValueFromPipeline=$true,
				ValueFromPipelineByPropertyName=$true,
				Mandatory=$false)]
    [string]$timestamp,
    [parameter(ValueFromPipeline=$true,
                ValueFromPipelineByPropertyName=$true,
                Mandatory=$false)]
    [switch]$addTimestamp=$false
)

#Get the config file
$config = Get-Content $PSScriptRoot"\influxdb_config.json" -Raw | ConvertFrom-Json

#---------------------------------------------------------[Execution]--------------------------------------------------------

# Get variables
$influxHost = $config.db.host
$influxHostPort = $config.db.port
$influxDbName = $config.db.name

# Build Uri
$uri = "http://$influxHost" + ":" + "$influxHostPort/write?&db=$influxDbName"

# Write data to Influx DB
Invoke-RestMethod -Uri $uri `
				-Method Post `
				-Body "$measurement,$tags $values $timestamp" `
				-TimeoutSec 30