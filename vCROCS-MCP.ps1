#!/usr/bin/env pwsh
# mcp-server.ps1 - PowerShell MCP server over stdio
# pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1
# Run: pwsh -NoLogo -NonInteractive -File ./mcp-server.ps1
#
# ==== STDIO USAGE (Manual / Debug) ==========================================
# 1) Start the server (it reads JSON lines from stdin, writes JSON lines to stdout):
#      pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1
#
# 2) In another shell, you can pipe JSON into the process. Example with a heredoc:
#      pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1 <<'EOF'
#      {"method":"initialize","id":1,"jsonrpc":"2.0"}
#      {"method":"tools/list","id":2,"jsonrpc":"2.0"}
#      EOF
#
#    (Above exits after EOF; for interactive testing open a terminal multiplexer
#     or use a small wrapper script that keeps stdin open.)
#
# 3) Example tool call (replace VMName etc. as needed):
#      {"method":"tools/call","id":3,"jsonrpc":"2.0","params":{"name":"Get-vCenter-Host-Health","arguments":{}}}
#      {"method":"tools/call","id":4,"jsonrpc":"2.0","params":{"name":"Send-Email","arguments":{"ToEmail":"dale.hassinger@outlook.com","Subject":"Test","Body":"Hi"}}}
#
# 4) Using echo (single command):
#      echo '{"method":"initialize","id":10,"jsonrpc":"2.0"}' | pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1
#
# 5) Programmatic client outline (pseudo):
#      - spawn process: pwsh -NoLogo -NonInteractive -File MCP-Server-OpenAI.ps1
#      - write one JSON object per line to stdin
#      - read one JSON line per response from stdout
#
# 6) The server does NOT open a TCP port; all communication is line-delimited JSON over stdio.
# 
# cli Prompts tested by Hackathon Team
<#

pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1 <<'EOF'
{"method":"tools/call","id":3,"jsonrpc":"2.0","params":{"name":"Get-vCenter-Host-Health","arguments":{}}}
EOF


pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1 <<'EOF'
{"method":"tools/call","id":4,"jsonrpc":"2.0","params":{"name":"Send-Email","arguments":{"ToEmail":"dale.hassinger@outlook.com","Subject":"Test","Body":"Hi"}}}
EOF

pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1 <<'EOF'
{"method":"tools/call","id":3,"jsonrpc":"2.0","params":{"name":"Get-Network-Switch-Stats","arguments":{}}} 
EOF

echo '{"method":"tools/call","id":3,"jsonrpc":"2.0","params":{"name":"Get-Network-Switch-Stats","arguments":{}}}' | pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1

echo '{"method":"tools/call","id":4,"jsonrpc":"2.0","params":{"name":"Send-Email","arguments":{"ToEmail":"dale.hassinger@outlook.com","Subject":"MCP Email","Body":"Hi, welcome to the Hackathon!"}}}' | pwsh -NoLogo -NonInteractive -File /Users/dalehassinger/Documents/GitHub/PS-TAM-Lab/MCP/MCP-Server-OpenAI.ps1

#>
#
# ============================================================================

using namespace System.Text
using namespace System.IO
using namespace System.Collections.Generic


# Load YAML configuration file

$cfgFile = "config/mcp-config.yaml"
if (-not (Test-Path $cfgFile)) {
    Write-Host "Configuration file '$cfgFile' not found." -ForegroundColor Red
    exit 1
}
try {
    $cfg = Get-Content -Path $cfgFile -Raw | ConvertFrom-Yaml
    if (-not $cfg.vCenter -or -not $cfg.vCenter.server -or -not $cfg.vCenter.username -or -not $cfg.vCenter.password) {
        Write-Host "Invalid YAML configuration: Missing vCenter server, username, or password." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Failed to parse YAML configuration: $_" -ForegroundColor Red
    exit 1
}

# -------------------------------------------
# Dynamic Tool Loading from tools/ subfolder
# -------------------------------------------

function Import-ToolsFromFolder {
    param(
        [string]$ToolsFolderPath = "./tools"
    )
    
    $loadedFunctions = @()
    
    if (-not (Test-Path $ToolsFolderPath)) {
        #Write-Warning "Tools folder '$ToolsFolderPath' not found. Skipping dynamic tool loading."
        return $loadedFunctions
    }
    
    $toolFiles = Get-ChildItem -Path $ToolsFolderPath -Filter "*.ps1" -File
    
    foreach ($file in $toolFiles) {
        try {
            #Write-Verbose "Loading tool file: $($file.Name)"
            
            # Dot-source the PowerShell file to load its functions
            . $file.FullName
            
            # Parse the file to find function definitions
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $functions = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)
            
            foreach ($func in $functions) {
                $functionName = $func.Name
                
                # Verify the function was actually loaded into the current session
                if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                    $loadedFunctions += $functionName
                    #Write-Verbose "Successfully loaded function: $functionName from $($file.Name)"
                }
            }
            
        } catch {
            #Write-Warning "Failed to load tool file '$($file.Name)': $_"
        }
    }
    
    #Write-Host "Loaded $($loadedFunctions.Count) functions from $($toolFiles.Count) tool files"
    return $loadedFunctions
}

# Load tools from the tools subfolder
$FunctionsToExpose = Import-ToolsFromFolder -ToolsFolderPath "./tools"
#$FunctionsToExpose

# ------------------------------------------------------------------------------------

# If you prefer module-based discovery:
# Import-Module ./YourModule.psm1 -Force

# --------------------------
# Utility: JSON-RPC I/O
# --------------------------
$stdin  = [Console]::OpenStandardInput()
$stdout = [Console]::OpenStandardOutput()
# Use UTF-8 without BOM to avoid sending U+FEFF
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$reader = New-Object IO.StreamReader($stdin, $utf8NoBom, $false, 4096, $true)
$writer = New-Object IO.StreamWriter($stdout, $utf8NoBom, 4096, $true)
$writer.AutoFlush = $true
$stderr = [Console]::Error

function Write-JsonRpc {
    param(
        [Parameter(Mandatory)] [hashtable]$Object
    )
    try {
        $json = ($Object | ConvertTo-Json -Depth 10 -Compress)
        $writer.WriteLine($json)
    } catch {
        $stderr.WriteLine("Write-JsonRpc error: $_")
    }
}

function Read-JsonLine {
    try {
        $line = $reader.ReadLine()
        if ($null -eq $line) { return $null }
        if ($line.Trim().Length -eq 0) { return @{} }
        return ($line | ConvertFrom-Json -Depth 20)
    } catch {
        $stderr.WriteLine("Read-JsonLine parse error: $_")
        return $null
    }
}

# --------------------------
# Discover tools (functions)
# --------------------------
function Get-ToolSchemaFromParam {
    param([Parameter(Mandatory)][System.Management.Automation.ParameterMetadata]$Param)
    $typeName = $Param.ParameterType.FullName
    switch ($typeName) {
        "System.String"     { return @{ type = "string" } }
        "System.Int32"      { return @{ type = "integer" } }
        "System.Int64"      { return @{ type = "integer" } }
        "System.Double"     { return @{ type = "number" } }
        "System.Boolean"    { return @{ type = "boolean" } }
        "System.Collections.Hashtable" { return @{ type = "object" } }
        default             { return @{ type = "string" } } # fallback
    }
}

function Get-ToolList {
    param(
        [string[]]$FunctionNames
    )
    $tools = @()
    foreach ($fn in $FunctionNames) {
        $cmd = Get-Command $fn -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $params = @{}
        $required = @()
        foreach ($kvp in $cmd.Parameters.GetEnumerator()) {
            $p = $kvp.Value
            # Filter out common/engine parameters so schemas stay concise
            if ($p.Name -in @(
                'Verbose','Debug','ErrorAction','WarningAction','InformationAction','OutVariable','OutBuffer','PipelineVariable',
                'InformationVariable','WarningVariable','ErrorVariable','ProgressAction','WhatIf','Confirm'
            )) { continue }
            $schema = Get-ToolSchemaFromParam -Param $p
            $params[$p.Name] = $schema
            if ($p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }) {
                $required += $p.Name
            }
        }
        $schemaObj = @{
            type       = "object"
            properties = $params
        }
        if ($required.Count -gt 0) { $schemaObj.required = $required }

        $help = (Get-Help $fn -ErrorAction SilentlyContinue)
        $desc = if ($help.Synopsis) { $help.Synopsis } else { "PowerShell function: $fn" }

        $tools += @{
            name        = $fn
            description = $desc
            inputSchema = $schemaObj
        }
    }
    return ,$tools
}

$ToolIndex = @{}
(Get-ToolList -FunctionNames $FunctionsToExpose) | ForEach-Object {
    $ToolIndex[$_.name] = $_
}

# --------------------------
# JSON-RPC Handlers
# --------------------------
function Send-Result {
    param($id, $result)
    Write-JsonRpc @{
        jsonrpc = "2.0"
        id      = $id
        result  = $result
    }
}

function Send-Error {
    param($id, [int]$code, [string]$message, $data=$null)
    $err = @{
        code    = $code
        message = $message
    }
    if ($null -ne $data) { $err.data = $data }
    Write-JsonRpc @{
        jsonrpc = "2.0"
        id      = $id
        error   = $err
    }
}

# Utility: Convert PSCustomObject (from ConvertFrom-Json) into Hashtable for splatting
function ConvertTo-HashtableDeep {
    param([Parameter()]$InputObject)
    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [System.Collections.IDictionary]) {
        return @{} + $InputObject
    }
    if ($InputObject -is [psobject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-HashtableDeep -InputObject $p.Value
        }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ,(ConvertTo-HashtableDeep -InputObject $item)
        }
        return ,$list
    }
    return $InputObject
}

# Main loop
$stderr.WriteLine("PowerShell MCP Server starting...")
while ($true) {
    try {
        $msg = Read-JsonLine
        if ($null -eq $msg) { 
            $stderr.WriteLine("Exiting main loop - null message")
            break 
        } # EOF
        if (-not $msg.method) { 
            $stderr.WriteLine("Skipping message without method")
            continue 
        }

        $id     = $msg.id
        $method = $msg.method
        $params = $msg.params

        $stderr.WriteLine("Processing method: $method with id: $id")

        switch ($method) {

            'initialize' {
                # Respond with MCP capabilities
                $result = @{
                    protocolVersion = "2024-11-05"  # nominal MCP version label; adjust if needed
                    serverInfo      = @{
                        name    = "powershell-mcp-server"
                        version = "0.1.0"
                    }
                    capabilities = @{
                        tools = @{}
                    }
                }
                Send-Result $id $result
            }

            'notifications/initialized' {
                # Notification (no id) — do not send a response
                continue
            }

            'tools/list' {
                $result = @{
                    tools = @($ToolIndex.Values)
                }
                Send-Result $id $result
            }

            'resources/list' {
                # Minimal implementation: no resources
                Send-Result $id @{ resources = @() }
            }

            'prompts/list' {
                # Minimal implementation: no prompts
                Send-Result $id @{ prompts = @() }
            }

            'tools/call' {
                try {
                    $name = $params.name
                    $args = $params.arguments

                    if (-not $ToolIndex.ContainsKey($name)) {
                        Send-Error $id -32601 "Unknown tool: $name"
                        continue
                    }

                    # Build splat: handle Hashtable, IDictionary, and PSCustomObject from JSON
                    $splat = @{}
                    if ($args -is [hashtable]) {
                        $splat = $args
                    } elseif ($args -is [System.Collections.IDictionary]) {
                        $splat = @{} + $args
                    } elseif ($args -ne $null) {
                        $splat = ConvertTo-HashtableDeep -InputObject $args
                    }

                    # Temporarily silence noisy preferences during tool run
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

                    $output = & $name @splat *>&1

                    # Restore preferences
                    $WarningPreference     = $prefBackup.Warning
                    $VerbosePreference     = $prefBackup.Verbose
                    $InformationPreference = $prefBackup.Information
                    $ProgressPreference    = $prefBackup.Progress

                    # Normalize and strip ANSI color codes
                    $outText = if ($output -is [string]) { $output } else { ($output | Out-String) }
                    $outText = [regex]::Replace($outText, "`e\[[\d;]*[A-Za-z]", '')

                    $result = @{
                        content = @(
                            @{
                                type = "text"
                                text = $outText
                            }
                        )
                        isError = $false
                    }
                    Send-Result $id $result
                } catch {
                    $result = @{
                        content = @(
                            @{
                                type = "text"
                                text = $_ | Out-String
                            }
                        )
                        isError = $true
                    }
                    Send-Result $id $result
                }
            }

            default {
                # Only reply with an error for real requests (id present), ignore notifications
                if ($null -ne $id) {
                    Send-Error $id -32601 "Method not implemented: $method"
                }
            }
        }
    } catch {
        $stderr.WriteLine("Error in main loop: $_")
        if ($id) {
            Send-Error $id -32603 "Internal error: $_"
        }
    }
}

$stderr.WriteLine("PowerShell MCP Server stopped")
