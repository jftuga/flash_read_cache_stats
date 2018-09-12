
# flash_cache_stats.ps1
# John Taylor
# Sep-12-2018

# This script queries the Flash Read Cache statistics of each host managed by a vCenter server.
# These statistics are then saved to an InfluxDB database.
# PowerShell prerequisites: Install-Module -Name VMware.PowerCLI

<#
MIT License Copyright (c) 2018 John Taylor
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

"Import VMware Flash Cache stats into InfluxDB"
$env:PSModulePath = "$env:PSModulePath;C:\Program Files\WindowsPowerShell\Modules"
Import-Module VMware.PowerCLI

$vcenter_server = "vcenter.example.com"
$run_interval = 2
$influxdb_measurement = "esxcli_storage_vflash_cache_stats"

# this is a regular expression used to parse the FRC cache names
$guest_name_pattern = "vfc-[0-9]+-(.*?)(_|-|$)"

############################################################################

function get_host_caches($esx) {
    return $esx.storage.vflash.cache.list.Invoke()
}

############################################################################

# issue PowerCLI command to host to get statistics about the specified cache
function get_cache_stats($esx, $guest_name, $cache_name) {
    "guest name, cache name: " + $guest_name, $cache_name
    if( $cache_name.length -eq 0 ) {
        Write-Error "Invalid parameters: $guest_name $cache_name"
        return
    }
    $a = $esx.storage.vflash.cache.stats.get.CreateArgs()
    $a.cachename = $cache_name
    $results = $esx.storage.vflash.cache.stats.get.Invoke($a)
    return $results
}

############################################################################

# each entry will have tags: guest, esxHost, cacheName, and namespace
# namespace will be one of: Global, Read, or Evict
# esxHost is shortened to the hostname w/o domain name
function import_into_influxdb($guest_name, $esx_host, $cache_name, $stats, $timestamp) {
    
    # create a tag and values for the Global namespace
    $values = New-Object System.Collections.Generic.List[string]
    if( $stats.Cacheusagerateasapercentage.length ) {
        $values.Add("Cacheusagerateasapercentage=" + $stats.Cacheusagerateasapercentage)
    }
    if( $stats.Meannumberofcacheblocksinuse.length) {
        $values.Add("Meannumberofcacheblocksinuse=" + $stats.Meannumberofcacheblocksinuse)
    }
    if( $stats.TotalfailedSSDIOs.length ) {
        $values.Add("TotalfailedSSDIOs=" + $stats.TotalfailedSSDIOs)
    }
    if( $stats.TotalfaileddiskIOs.length) {
        $values.Add("TotalfaileddiskIOs=" + $stats.TotalfaileddiskIOs)
    }

    $values_global = $values -join ","
    $tags_global = "guest=" + $guest_name + ",esxHost=" + $esx_host.split(".")[0] + ",cacheName=" + $cache_name + ",namespace=Global"
    $tags_global
    $values_global

    # create a tag and values for the Read namespace
    $values.Clear()

    if ($stats.Read.Cachehitrateasapercentage.length) {
        $values.Add("Cachehitrateasapercentage=" + $stats.Read.Cachehitrateasapercentage)
    }
    if ($stats.Read.MaxobservedIOlatencyinmicroseconds.length) {
        $values.Add("MaxobservedIOlatencyinmicroseconds=" + $stats.Read.MaxobservedIOlatencyinmicroseconds)
    }
    if ($stats.Read.MaxobservedIOPS.length) {
        $values.Add("MaxobservedIOPS=" + $stats.Read.MaxobservedIOPS)
    }
    if ($stats.Read.MaxobservednumberofKBperIO.length) {
        $values.Add("MaxobservednumberofKBperIO=" + $stats.Read.MaxobservednumberofKBperIO)
    }
    if ($stats.Read.MeanIOlatencyinmicroseconds.length) {
        $values.Add("MeanIOlatencyinmicroseconds=" + $stats.Read.MeanIOlatencyinmicroseconds)
    }
    if ($stats.Read.MeanIOPS.length) {
        $values.Add("MeanIOPS=" + $stats.Read.MeanIOPS)
    }
    if ($stats.Read.MeancacheIOlatencyinmicroseconds.length) {
        $values.Add("MeancacheIOlatencyinmicroseconds=" + $stats.Read.MeancacheIOlatencyinmicroseconds)
    }
    if ($stats.Read.MeandiskIOlatencyinmicroseconds.length) {
        $values.Add("MeandiskIOlatencyinmicroseconds=" + $stats.Read.MeandiskIOlatencyinmicroseconds)
    }
    if ($stats.Read.MeannumberofKBperIO.length) {
        $values.Add("MeannumberofKBperIO=" + $stats.Read.MeannumberofKBperIO)
    }
    if ($stats.Read.TotalIOs.length) {
        $values.Add("TotalIOs=" + $stats.Read.TotalIOs)
    }
    if ($stats.Read.TotalcacheIOs.length) {
        $values.Add("TotalcacheIOs=" + $stats.Read.TotalcacheIOs)
    }
    if ($stats.Read.TotaldiskIOs.length) {
        $values.Add("TotaldiskIOs=" + $stats.Read.TotaldiskIOs)
    }
    
    $values_read = $values -join ","
    $tags_read = "guest=" + $guest_name + ",esxHost=" + $esx_host.split(".")[0] + ",cacheName=" + $cache_name + ",namespace=Read"

    # create a tag and values for the Evict namespace
    $values.Clear()

    if ($stats.Evict.LastIOoperationtimeinmicroseconds.length) {
        $values.Add("LastIOoperationtimeinmicroseconds=" + $stats.Evict.LastIOoperationtimeinmicroseconds)
    }
    if ($stats.Evict.MeanblocksperIOoperation.length) {
        $values.Add("MeanblocksperIOoperation=" + $stats.Evict.MeanblocksperIOoperation)
    }
    if ($stats.Evict.NumberofIOblocksinlastoperation.length) {
        $values.Add("NumberofIOblocksinlastoperation=" + $stats.Evict.NumberofIOblocksinlastoperation)
    }

    $values_evict = $values -join ","
    $tags_evict = "guest=" + $guest_name + ",esxHost=" + $esx_host.split(".")[0] + ",cacheName=" + $cache_name + ",namespace=Evict"

    # issue write commands to the influx database
    .\Influx-Write.ps1 -measurement $influxdb_measurement -tags $tags_global -values $values_global -timestamp $timestamp
    .\Influx-Write.ps1 -measurement $influxdb_measurement -tags $tags_read -values $values_read -timestamp $timestamp
    .\Influx-Write.ps1 -measurement $influxdb_measurement -tags $tags_evict -values $values_evict -timestamp $timestamp
}


############################################################################

# create a list of caches for the given host, $guest_caches
# get the stats about each cache
# import this info into influxdb
function process_single_host($host_name, $timestamp) {
    $esxcli = Get-EsxCli -VMHost $host_name -V2
    $cache_list = get_host_caches $esxcli

    # create a hashtable: key=vm guest name, val=a list of caches beloinging to that vm
    $guest_caches = @{}
    foreach($cache_obj in $cache_list) {
        $cache_name = $cache_obj.Name.trim()
        if( $cache_name -match $guest_name_pattern) {
            $guest_name = $matches[1].trim().tolower()
        } else {
            "no 'guest_name_pattern' match for: " + $cache_name
            continue
        }

        # if the $guest_name key does not exist, then create the initial value containing an empty list
        # this occcurs the first time $guest_name is encountered
        if( -not $guest_caches.ContainsKey( $guest_name ) ) {
            $guest_caches[$guest_name] = New-Object System.Collections.Generic.List[System.Object]
        }

        # append the cache name to the end of the list
        $guest_caches[$guest_name].Add($cache_obj.Name.trim())
    }

    # iterate through each VM in the hash table, then iterate through each cache in that VM's hash table's value
    # import these stats into influxdb
    foreach($guest_name in $guest_caches.keys) {
        foreach( $cache_name in $guest_caches[$guest_name]) {
            "guest, cache: " + $guest_name, $cache_name
            $stats = get_cache_stats $esxcli $guest_name $cache_name
            import_into_influxdb $guest_name $host_name $cache_name $stats $timestamp
        }
    }
}

############################################################################

# sleep until every even numbered minute at the beginning of that minute
# example: 08:16:00 (ok)   08:16:01 (nope)   08:15:00 (nope)
# influxdb requires (1) universal time, (2) nanosecond resolution, (3) number of nanoseconds since the epoch
function wait_for_start_of_minute() {
    Write-Host "Waiting for next run time interval, will occur in less than $run_interval minutes"
    Write-Host $(Get-Date)
    while( $true ) {
        Start-Sleep -m 200
        $secs = Get-Date -Format %s
        $mins = [int](Get-Date -Format %m)
        if( "0" -eq $secs -and ($mins % $run_interval) -eq 0 ) {
            # https://www.reddit.com/r/PowerShell/comments/9ezuaj/how_can_i_get_universal_time_with_nanosecond/e5sqjv5/
            return "$(([DateTimeOffset](Get-Date)).ToUniversalTime().ToUnixTimeMilliseconds())000000"
        }
    }
}

############################################################################
function main() {
    $server = ""
    try {
        $result = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
        $server = Connect-VIServer -Server $vcenter_server -Protocol https
    } catch {
        Write-Error "Error: can not connect to vCenter server"
        Write-Error $_.Exception.Message 
        return
    }
    if( $server.length -eq 0) {
        return
    }

    # to gracefully stop this script, create a file called "abort"
    # if this file exists, the script stops after the processing of a host
    if( Test-Path "abort" ) {
        Remove-Item ".\abort"
    }

    $timestamp = wait_for_start_of_minute

    # iterate through all hosts within the given vCenter server
    $all_host_objs = get-vmhost | sort Name
    while( $true ) {
        "=" * 77
        Get-Date
        foreach ($host_obj in $all_host_objs) {
            if( Test-Path ".\abort" ) {
                "Abort detected, ending program"
                return
            }
            process_single_host $host_obj.Name $timestamp
        }
        $timestamp = wait_for_start_of_minute
    }
}

############################################################################

main

# end of script
