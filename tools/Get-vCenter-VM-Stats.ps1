function Get-vCenter-VM-Stats {
    <#
    .SYNOPSIS
      Return vCenter VMs (all by default) and their properties as JSON

      Do not use if RVTools is in the Prompt
    .PARAMETER Name
      Optional name or pattern to filter VMs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName
    )

    # Suppress banners/warnings/verbose/progress for this function scope
    $prefBackup = @{
        Warning      = $WarningPreference
        Verbose      = $VerbosePreference
        Information  = $InformationPreference
        Progress     = $ProgressPreference
    }
    $WarningPreference     = 'SilentlyContinue'
    $VerbosePreference     = 'SilentlyContinue'
    $InformationPreference = 'SilentlyContinue'
    $ProgressPreference    = 'SilentlyContinue'

    try {
        if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
            throw "VMware.PowerCLI module not found. Install with: Install-Module VMware.PowerCLI -Scope CurrentUser"
        }
        Import-Module VMware.PowerCLI -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null

        # Avoid prompts/cert warnings
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null

        # Connect to vCenter
        $vCenter = Connect-VIServer -Server $cfg.vCenter.server -User $cfg.vCenter.username -Password $cfg.vCenter.password -Protocol https -ErrorAction Stop

        $vm = Get-VM -Name $VMName -ErrorAction Stop

        Get-Stat -Entity $vm `
                -Stat cpu.usage.average, cpu.usagemhz.average, mem.usage.average, disk.usage.average, net.usage.average, sys.uptime.latest `
                -Start (Get-Date).AddHours(-1) -MaxSamples 1 |
        Select-Object @{Name='VMName';Expression={$vm.Name}},
                    MetricId, Timestamp, Value, Unit, Instance |
        ConvertTo-Json -Depth 3

    }
    catch {
        @{ error = $_.Exception.Message } | ConvertTo-Json -Depth 5
    }
    finally {
        try { if ($si) { Disconnect-VIServer -Server $si -Confirm:$false | Out-Null } } catch {}
        # Restore preferences
        $WarningPreference     = $prefBackup.Warning
        $VerbosePreference     = $prefBackup.Verbose
        $InformationPreference = $prefBackup.Information
        $ProgressPreference    = $prefBackup.Progress
    }
} # End Function

