function Get-Network-Switch-Stats {
    <#
    .SYNOPSIS
    Collects system utilization and fan status from a TRENDnet TEG-7124WS and returns JSON.
    .REQUIREMENTS
    Install-Module Posh-SSH
    #>

    # --- Fixed connection details ---
    $Ip       = $cfg.Switch.SwitchIP
    $User     = $cfg.Switch.SwitchUser
    $Password = $cfg.Switch.SwitchPW

    # --- Prep credentials ---
    $sec  = ConvertTo-SecureString $Password -AsPlainText -Force
    $cred = [pscredential]::new($User, $sec)

    # --- Ensure Posh-SSH is available ---
    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw "Posh-SSH module not found. Install it with: Install-Module Posh-SSH"
    }

    Import-Module Posh-SSH -ErrorAction Stop

    # --- Helper: read until timeout ---
    function Invoke-TrendnetCommand {
        param(
            [Parameter()] [string]$Command = '',
            [Parameter(Mandatory)] [object]$Stream,
            [int]$TimeoutSec = 5
        )

        Start-Sleep -Milliseconds 300
        $null = $Stream.Read()

        if ($Command) {
            $Stream.WriteLine($Command)
        }

        $buffer = ''
        $deadline = (Get-Date).AddSeconds($TimeoutSec)

        do {
            Start-Sleep -Milliseconds 200
            $chunk = $Stream.Read()
            if ($chunk) { $buffer += $chunk }
        } while ((Get-Date) -lt $deadline)

        # Clean up
        $buffer = $buffer -replace "`r",""
        $buffer = $buffer -replace '\x1B\[[0-9;]*[A-Za-z]', ''  # strip ANSI escape codes
        $lines  = $buffer -split "`n" | ForEach-Object { $_.Trim() }

        # Remove echoed command and blank lines
        $lines = $lines | Where-Object { $_ -and ($_ -ne $Command) }

        ($lines -join "`n").Trim()
    }

    # --- Parse system utilization ---
    function Parse-Utilization {
        param([Parameter(Mandatory)][string]$Text)
        $lines = $Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

        $cpuData = @{}
        $cpuStart = ($lines | Select-String -Pattern '^CPU Utilization:').LineNumber
        if ($cpuStart) {
            for ($i = $cpuStart; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($i -gt $cpuStart -and ($line -match '^Memory Utilization:' -or $line -eq '')) { break }
                if ($line -match '^(?<k>\S+)\s*:\s*(?<v>[\d\.]+)') {
                    $cpuData[$matches.k] = [double]$matches.v
                }
            }
        }

        $memData = @{}
        $memStart = ($lines | Select-String -Pattern '^Memory Utilization:').LineNumber
        if ($memStart) {
            for ($i = $memStart; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($i -gt $memStart -and $line -eq '') { break }
                if ($line -match '^(?<k>\S+)\s*:\s*(?<n>\d+)\s*(?<unit>MB|KB|GB)?$') {
                    $n = [int]$matches.n
                    switch -Regex ($matches.unit) {
                        'GB' { $n *= 1024 }
                        'KB' { $n = [int][math]::Round($n / 1024.0) }
                    }
                    $memData[$matches.k] = $n
                }
            }
        }

        [pscustomobject]@{
            CPU    = $cpuData
            Memory = $memData
        }
    }

    # --- Parse fan status ---
    function Parse-FanStatus {
        param([Parameter(Mandatory)][string]$Text)
        $status = 'UNKNOWN'
        foreach ($line in ($Text -split "`n")) {
            if ($line -match '^System Fan Status:\s*(?<s>.+?)\s*$') {
                $status = $matches.s.Trim()
                break
            }
        }
        $status
    }

    # --- Parse interface status ---
    function Parse-InterfaceStatus {
        param([Parameter(Mandatory)][string]$Text)
        $lines = $Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $interfaces = @()
        
        $headerFound = $false
        foreach ($line in $lines) {
            if ($line -match '^Port\s+Status\s+Duplex\s+Speed\s+Negotiation\s+Capability') {
                $headerFound = $true
                continue
            }
            if ($line -match '^-+\s+-+\s+-+\s+-+\s+-+\s+-+') {
                continue
            }
            if ($headerFound -and $line -match '^\S+' -and $line -notmatch '--More--') {
                # Split and clean up the line
                $cleanParts = ($line -replace '\s+', ' ') -split ' '
                
                # Skip invalid entries and only include Gi0 ports
                if ($cleanParts[0] -eq '--More--' -or $cleanParts[0] -match '^-+$' -or $cleanParts[0] -notmatch '^Gi0') {
                    continue
                }
                
                $interface = [pscustomobject]@{
                    Port = $cleanParts[0]
                    Status = if ($cleanParts[1] -eq 'not') { 'not connected' } else { $cleanParts[1] }
                    Duplex = if ($cleanParts[1] -eq 'not') { $cleanParts[3] } else { $cleanParts[2] }
                    Speed = if ($cleanParts[1] -eq 'not') { 
                        if ($cleanParts[4] -eq '-') { '-' } else { $cleanParts[4] + ' ' + $cleanParts[5] }
                    } else { 
                        if ($cleanParts[3] -eq '-') { '-' } else { $cleanParts[3] + ' ' + $cleanParts[4] }
                    }
                    Negotiation = if ($cleanParts[1] -eq 'not') { 
                        if ($cleanParts.Count -gt 5) { $cleanParts[5] } else { '' }
                    } else { 
                        if ($cleanParts.Count -gt 4) { $cleanParts[4] } else { '' }
                    }
                    Capability = if ($cleanParts[1] -eq 'not') { 
                        if ($cleanParts.Count -gt 6) { ($cleanParts[6..($cleanParts.Count-1)] -join ' ') } else { '' }
                    } else { 
                        if ($cleanParts.Count -gt 5) { ($cleanParts[5..($cleanParts.Count-1)] -join ' ') } else { '' }
                    }
                }
                $interfaces += $interface
            }
        }
        
        return $interfaces
    }

    # --- Main ---
    $session = $null
    try {
        $session = New-SSHSession -ComputerName $Ip -Credential $cred -AcceptKey -ErrorAction Stop
        $stream  = New-SSHShellStream -SessionId $session.SessionId -TerminalName 'vt100'

        # Force prompt
        $null = Invoke-TrendnetCommand -Stream $stream -Command ''

        # Run commands
        $utilRaw = Invoke-TrendnetCommand -Stream $stream -Command 'show system utilization'
        $fanRaw  = Invoke-TrendnetCommand -Stream $stream -Command 'show system fan status'
        $intRaw  = Invoke-TrendnetCommand -Stream $stream -Command 'show interfaces status'

        # Debug
        # Write-Host "DEBUG Utilization:`n$utilRaw"
        # Write-Host "DEBUG Fan:`n$fanRaw"
        # Write-Host "DEBUG Interfaces:`n$intRaw"

        # Parse
        if (-not $utilRaw) { throw "No output from 'show system utilization'" }
        $util = Parse-Utilization -Text $utilRaw
        $fan  = Parse-FanStatus -Text $fanRaw
        $interfaces = Parse-InterfaceStatus -Text $intRaw

        # Output JSON
        $result = [pscustomobject]@{
            Device     = 'TEG-7124WS'
            Target     = $Ip
            CPU        = $util.CPU
            Memory     = $util.Memory
            Fan        = $fan
            Interfaces = $interfaces
        }

        #        Fetched    = (Get-Date).ToString('s')

        $result | ConvertTo-Json -Depth 5
    }
    finally {
        if ($session) { Remove-SSHSession -SessionId $session.SessionId | Out-Null }
    }    
} # End Function
