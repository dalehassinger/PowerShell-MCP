function Get-vCenter-Host-Health {
    <#
    .SYNOPSIS
      Return the latest vROps 'badge|health' metric per vCenter ESXi host as JSON.
    .DESCRIPTION
      Connects to VCF Operations (vROps) at 192.168.6.99 using admin credentials, enumerates HostSystem
      resources, fetches the most recent 'badge|health' sample within the last 24 hours for each host,
      and emits an array of objects with Resource, Time, and Value as a JSON string.

      Do not use if RVTools is in the Prompt

    .OUTPUTS
      System.String (JSON)
    .EXAMPLE
      Get-Host-Health
      [
        { "Resource": "esxi01.lab.local", "Time": "2025-08-10T12:34:56Z", "Value": 100 }
      ]
    #>
    [CmdletBinding()]
    param()

    # Connect to VCF Operations (vROps)
    Connect-OMServer -Server $cfg.OPS.opsIP -User $cfg.OPS.opsUsername -Password $cfg.OPS.opsPassword -Force

    # Get HostSystem resources as a unique, sorted list of names
    $hostNames = Get-OMResource |
        Where-Object { $_.ResourceKind -like "*HostSystem*" } |
        Select-Object -ExpandProperty Name |
        Sort-Object -Unique

    # Collect host health into an array
    $results = @()

    foreach ($name in $hostNames) {
        $sample = Get-OMStat -Resource $name -Key 'badge|health' -From (Get-Date).AddDays(-1) |
                  Sort-Object Time -Descending |
                  Select-Object -First 1

        if ($null -ne $sample) {
            $results += [pscustomobject]@{
                Resource = $name
                Time     = $sample.Time
                Value    = $sample.Value
            }
        } else {
            $results += [pscustomobject]@{
                Resource = $name
                Time     = $null
                Value    = $null
            }
        }
    } # End foreach

    # Emit JSON
    $results | ConvertTo-Json -Depth 3

    Disconnect-OMServer -Confirm:$false

} # End Function

