Function Create-DNS-ARecord {

    <#
    .SYNOPSIS
    Add or update an A record in a Microsoft DNS zone (SSH only).

    .DESCRIPTION
    Executes DNS Server cmdlets remotely via ssh/sshpass (PowerShell on the DNS host).
    Steps:
        1. Lookup existing A record.
        2. If IP matches requested: report Unchanged.
        3. Else remove (if exists) then add new record.
    Outputs object: Action, Status, Zone, RecordName, IPv4, TTL, Message.

    .REQUIREMENTS
    - DNS Server role + DnsServer module on remote Windows DNS server.
    - OpenSSH server enabled (password auth or acceptable method for sshpass).
    - sshpass installed locally.

    .EXAMPLE
    ./dns-a-record.ps1 -RecordName web01 -IPv4Address 192.168.6.50

    .EXAMPLE
    ./dns-a-record.ps1 -RecordName api01 -IPv4Address 192.168.6.60 -TTL (New-TimeSpan -Minutes 5)
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]+$')]
        [string]$RecordName,
        [Parameter(Mandatory)]
        [System.Net.IPAddress]$IPv4Address,
        [string]$ZoneName  = 'vcrocs.local',
        [string]$DnsServer = '192.168.6.2',
        [TimeSpan]$TTL     = ([TimeSpan]::FromHours(1)),
        [string]$Username  = 'administrator@vcrocs.local',
        [SecureString]$Password
    )

    # Default lab password
    if (-not $PSBoundParameters.ContainsKey('Password')) {
        $Password = ConvertTo-SecureString 'VMware1!' -AsPlainText -Force
    }

    # Require sshpass
    if (-not (Get-Command sshpass -ErrorAction SilentlyContinue)) {
        Write-Error "sshpass not found."
        exit 1
    }

    # Port 22 reachability
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $ar  = $tcp.BeginConnect($DnsServer,22,$null,$null)
        if (-not $ar.AsyncWaitHandle.WaitOne(3000)) { $tcp.Close(); throw "Timeout connecting to $DnsServer:22" }
        if (-not $tcp.Connected) { throw "Connection refused on $DnsServer:22" }
        $tcp.EndConnect($ar); $tcp.Close()
    } catch {
        [pscustomobject]@{
            Action='Query'; Status='Error'; Zone=$ZoneName; RecordName=$RecordName;
            IPv4=$IPv4Address.IPAddressToString; Message="SSH unreachable: $($_.Exception.Message)"
        } | ConvertTo-Json -Compress
        return
    }

    # Plain password (lab)
    $plainPw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    )

    function Invoke-Remote {
        param([Parameter(Mandatory)][string]$Script)
        $wrapper = @'
$ErrorActionPreference='Stop'
try {
Import-Module DnsServer -ErrorAction Stop
__PAYLOAD__
} catch {
  Write-Output ('ERR::' + $_.Exception.Message)
  exit 1
}
'@
        $payload = $wrapper -replace '__PAYLOAD__', $Script
        $bytes   = [Text.Encoding]::Unicode.GetBytes($payload)
        $b64     = [Convert]::ToBase64String($bytes)
        $sshArgs = @(
            "-p",$plainPw,"ssh",
            "-o","StrictHostKeyChecking=no",
            "-o","PreferredAuthentications=password",
            "-o","PubkeyAuthentication=no",
            "$Username@$DnsServer",
            "powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $b64"
        )
        (& sshpass @sshArgs 2>&1)
    }

    function Get-ARecord {
        Invoke-Remote -Script @"
`$r = Get-DnsServerResourceRecord -ZoneName '$ZoneName' -Name '$RecordName' -RRType A -ErrorAction SilentlyContinue
if (`$null -ne `$r) {
  `$ips = `$r.RecordData.IPv4Address.IPAddressToString
  Write-Output ('OK::' + (@(`$ips) -join ','))
} else {
  Write-Output 'MISS::'
}
"@
    }

    function Remove-ARecord {
        Invoke-Remote -Script "Remove-DnsServerResourceRecord -ZoneName '$ZoneName' -Name '$RecordName' -RRType A -Force -ErrorAction Stop; Write-Output 'OK::REMOVED'"
    }

    function Add-ARecord {
        $ttl = $TTL.ToString()
        Invoke-Remote -Script "Add-DnsServerResourceRecordA -ZoneName '$ZoneName' -Name '$RecordName' -IPv4Address '$($IPv4Address.IPAddressToString)' -TimeToLive ([TimeSpan]'$ttl') -ErrorAction Stop; Write-Output 'OK::ADDED'"
    }

    # Lookup
    $raw = Get-ARecord
    if ($raw -is [array]) { $raw = $raw[-1] }
    $hasRecord = $false
    $existingIPs = @()

    switch -regex ($raw) {
        '^OK::' {
            $d = $raw.Substring(4)
            if ($d) { $existingIPs = $d -split ','; $hasRecord = $true }
        }
        '^ERR::' {
            [pscustomobject]@{
                Action='Query'; Status='Error'; Zone=$ZoneName; RecordName=$RecordName;
                IPv4=$IPv4Address.IPAddressToString; Message="Lookup failed: $raw"
            } | ConvertTo-Json -Compress
            return
        }
    }

    $targetIP = $IPv4Address.IPAddressToString

    # Unchanged
    if ($hasRecord -and $existingIPs.Count -eq 1 -and $existingIPs[0] -eq $targetIP) {
        [pscustomobject]@{
            Action='None'; Status='Unchanged'; Zone=$ZoneName; RecordName=$RecordName;
            IPv4=$targetIP; Message='A record already present with matching IP'
        } | ConvertTo-Json -Compress
        return
    }

    $action = if ($hasRecord) { 'Update' } else { 'Create' }

    # Change
    try {
        if ($hasRecord) {
            if (-not $PSCmdlet.ShouldProcess("$RecordName.$ZoneName","Remove existing A record ($($existingIPs -join ','))")) { return }
            $del = Remove-ARecord
            if (-not ($del -match '^OK::')) { throw "Remove failed: $del" }
        } else {
            if (-not $PSCmdlet.ShouldProcess("$RecordName.$ZoneName","Create A record -> $targetIP")) { return }
        }

        $add = Add-ARecord
        if (-not ($add -match '^OK::')) { throw "Add failed: $add" }

        [pscustomobject]@{
            Action     = if ($hasRecord) { 'Updated' } else { 'Created' }
            Status     = 'Success'
            Zone       = $ZoneName
            RecordName = $RecordName
            IPv4       = $targetIP
            TTL        = $TTL.ToString()
            Message    = 'A record committed'
        } | ConvertTo-Json -Compress
    }
    catch {
        [pscustomobject]@{
            Action     = $action
            Status     = 'Error'
            Zone       = $ZoneName
            RecordName = $RecordName
            IPv4       = $targetIP
            Message    = $_.Exception.Message
        } | ConvertTo-Json -Compress
        return
    }
} # End Function
