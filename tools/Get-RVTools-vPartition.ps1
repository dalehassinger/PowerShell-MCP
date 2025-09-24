function Get-RVTools-vPartition {

    <#
    .SYNOPSIS
    Parse RVTools Excel -> vPartition tab -> JSON
    .DESCRIPTION
    - Show vCenter VM vPartition when RVTools needs to be used
    - Only use this Function when RVTools is in the prompt
    - Returns a JSON string of the data
    #>

    # Ensure ImportExcel is available (no Excel app needed)
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        try {
            $null = Install-Module ImportExcel -Scope CurrentUser -Force -ErrorAction Stop
        } catch {
            Throw "Could not install ImportExcel: $($_.Exception.Message)"
        }
    }
    Import-Module ImportExcel -ErrorAction Stop

    # Import the vInfo worksheet
    try {
        $raw = Import-Excel -Path $rvtoolsPath -WorksheetName 'vPartition' -DataOnly -ErrorAction Stop
    } catch {
        Throw "Failed to read 'vPartition' sheet from '$rvtoolsPath': $($_.Exception.Message)"
    }

    if (-not $raw -or $raw.Count -eq 0) {
        Write-Error "No rows found on the 'vPartition' worksheet."
        exit 1
    }

    $rows =
        $raw |
        Where-Object { $_.'VM' } |
        ForEach-Object {
            # Return all columns as-is from the worksheet
            $_
        }

    # Optional: Filter for specific conditions if needed
    # $rows = $rows | Where-Object { $_.SomeColumn -eq 'SomeValue' }

    $rows | ConvertTo-Json -Depth 5

} # End Function

