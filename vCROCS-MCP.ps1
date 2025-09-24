#!/usr/bin/env pwsh

# ==============================================================================
# PowerShell MCP (Model Context Protocol) Server
# ==============================================================================
# 
# This script implements a Model Context Protocol server in PowerShell that 
# communicates over stdio using JSON-RPC 2.0. It dynamically loads PowerShell 
# functions from the tools/ directory and exposes them as MCP tools that can 
# be called by MCP clients (like Claude Desktop, OpenAI, etc.).
#
# Features:
# - Dynamic tool discovery from tools/ subfolder
# - YAML configuration support
# - JSON-RPC 2.0 protocol implementation
# - Proper error handling and logging
# - Cross-platform PowerShell support
#
# Author: Dale Hassinger
# Repository: https://github.com/dalehassinger/PowerShell-MCP
# License: MIT
# ==============================================================================

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

# Import required .NET namespaces for text encoding and I/O operations
using namespace System.Text
using namespace System.IO
using namespace System.Collections.Generic

# ==============================================================================
# CONFIGURATION LOADING
# ==============================================================================
# Load YAML configuration file containing vCenter credentials and other settings

$cfgFile = "config/mcp-config.yaml"
if (-not (Test-Path $cfgFile)) {
    Write-Host "Configuration file '$cfgFile' not found." -ForegroundColor Red
    exit 1
}
try {
    # Parse YAML configuration and validate required fields
    $cfg = Get-Content -Path $cfgFile -Raw | ConvertFrom-Yaml
    if (-not $cfg.vCenter -or -not $cfg.vCenter.server -or -not $cfg.vCenter.username -or -not $cfg.vCenter.password) {
        Write-Host "Invalid YAML configuration: Missing vCenter server, username, or password." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Failed to parse YAML configuration: $_" -ForegroundColor Red
    exit 1
}

# ==============================================================================
# DYNAMIC TOOL LOADING SYSTEM
# ==============================================================================
# This section handles automatic discovery and loading of PowerShell functions
# from the tools/ directory, making them available as MCP tools

function Import-ToolsFromFolder {
    <#
    .SYNOPSIS
        Dynamically loads PowerShell functions from a specified folder
    
    .DESCRIPTION
        Scans the specified folder for .ps1 files, dot-sources them to load 
        their functions into the current session, and returns a list of 
        successfully loaded function names. This enables modular tool 
        development where each tool can be a separate .ps1 file.
    
    .PARAMETER ToolsFolderPath
        Path to the folder containing PowerShell tool files (default: "./tools")
    
    .OUTPUTS
        String array of successfully loaded function names
    #>
    param(
        [string]$ToolsFolderPath = "./tools"
    )
    
    $loadedFunctions = @()
    
    # Check if tools folder exists
    if (-not (Test-Path $ToolsFolderPath)) {
        #Write-Warning "Tools folder '$ToolsFolderPath' not found. Skipping dynamic tool loading."
        return $loadedFunctions
    }
    
    # Get all PowerShell files in the tools directory
    $toolFiles = Get-ChildItem -Path $ToolsFolderPath -Filter "*.ps1" -File
    
    foreach ($file in $toolFiles) {
        try {
            #Write-Verbose "Loading tool file: $($file.Name)"
            
            # Dot-source the PowerShell file to load its functions into current session
            . $file.FullName
            
            # Parse the AST (Abstract Syntax Tree) to find function definitions
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $functions = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)
            
            # Verify each function was successfully loaded
            foreach ($func in $functions) {
                $functionName = $func.Name
                
                # Check if function is available in current session
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

# Load all tools from the tools subfolder and store function names
$FunctionsToExpose = Import-ToolsFromFolder -ToolsFolderPath "./tools"
#$FunctionsToExpose

# Alternative approach using PowerShell modules (commented out):
# If you prefer module-based discovery:
# Import-Module ./YourModule.psm1 -Force

# ==============================================================================
# JSON-RPC COMMUNICATION SETUP
# ==============================================================================
# Configure stdio streams for JSON-RPC communication with proper UTF-8 encoding

# Open standard input/output streams
$stdin  = [Console]::OpenStandardInput()
$stdout = [Console]::OpenStandardOutput()

# Use UTF-8 without BOM to avoid sending U+FEFF byte order mark
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# Create stream readers/writers with UTF-8 encoding
$reader = New-Object IO.StreamReader($stdin, $utf8NoBom, $false, 4096, $true)
$writer = New-Object IO.StreamWriter($stdout, $utf8NoBom, 4096, $true)
$writer.AutoFlush = $true  # Ensure immediate output for real-time communication
$stderr = [Console]::Error

# ==============================================================================
# JSON-RPC UTILITY FUNCTIONS
# ==============================================================================
# Helper functions for reading and writing JSON-RPC messages

function Write-JsonRpc {
    <#
    .SYNOPSIS
        Writes a JSON-RPC message to stdout
    
    .DESCRIPTION
        Converts a hashtable to JSON and writes it as a single line to stdout
        for JSON-RPC communication. Handles errors gracefully.
    #>
    param(
        [Parameter(Mandatory)] [hashtable]$Object
    )
    try {
        # Convert to compressed JSON (single line) for line-delimited protocol
        $json = ($Object | ConvertTo-Json -Depth 10 -Compress)
        $writer.WriteLine($json)
    } catch {
        $stderr.WriteLine("Write-JsonRpc error: $_")
    }
}

function Read-JsonLine {
    <#
    .SYNOPSIS
        Reads and parses a JSON line from stdin
    
    .DESCRIPTION
        Reads a single line from stdin and attempts to parse it as JSON.
        Returns null on EOF or parse errors, empty hashtable for empty lines.
    #>
    try {
        $line = $reader.ReadLine()
        if ($null -eq $line) { return $null }  # EOF condition
        if ($line.Trim().Length -eq 0) { return @{} }  # Empty line
        return ($line | ConvertFrom-Json -Depth 20)
    } catch {
        $stderr.WriteLine("Read-JsonLine parse error: $_")
        return $null
    }
}

# ==============================================================================
# TOOL SCHEMA GENERATION
# ==============================================================================
# Functions to automatically generate JSON schemas for PowerShell function parameters

function Get-ToolSchemaFromParam {
    <#
    .SYNOPSIS
        Generates JSON schema type information from PowerShell parameter metadata
    
    .DESCRIPTION
        Maps PowerShell parameter types to JSON schema types for MCP tool definitions.
        Supports common types like string, integer, number, boolean, and object.
    #>
    param([Parameter(Mandatory)][System.Management.Automation.ParameterMetadata]$Param)
    
    # Map PowerShell types to JSON schema types
    $typeName = $Param.ParameterType.FullName
    switch ($typeName) {
        "System.String"     { return @{ type = "string" } }
        "System.Int32"      { return @{ type = "integer" } }
        "System.Int64"      { return @{ type = "integer" } }
        "System.Double"     { return @{ type = "number" } }
        "System.Boolean"    { return @{ type = "boolean" } }
        "System.Collections.Hashtable" { return @{ type = "object" } }
        default             { return @{ type = "string" } } # fallback to string
    }
}

function Get-ToolList {
    <#
    .SYNOPSIS
        Generates MCP tool definitions from PowerShell function metadata
    
    .DESCRIPTION
        Examines PowerShell functions and creates MCP-compatible tool definitions
        including parameter schemas, required parameters, and descriptions from help.
    #>
    param(
        [string[]]$FunctionNames
    )
    $tools = @()
    
    foreach ($fn in $FunctionNames) {
        # Get function command information
        $cmd = Get-Command $fn -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        
        # Build parameter schema and identify required parameters
        $params = @{}
        $required = @()
        
        foreach ($kvp in $cmd.Parameters.GetEnumerator()) {
            $p = $kvp.Value
            
            # Filter out PowerShell common/engine parameters to keep schemas clean
            if ($p.Name -in @(
                'Verbose','Debug','ErrorAction','WarningAction','InformationAction','OutVariable','OutBuffer','PipelineVariable',
                'InformationVariable','WarningVariable','ErrorVariable','ProgressAction','WhatIf','Confirm'
            )) { continue }
            
            # Generate schema for this parameter
            $schema = Get-ToolSchemaFromParam -Param $p
            $params[$p.Name] = $schema
            
            # Check if parameter is mandatory
            if ($p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }) {
                $required += $p.Name
            }
        }
        
        # Build JSON schema object for function parameters
        $schemaObj = @{
            type       = "object"
            properties = $params
        }
        if ($required.Count -gt 0) { $schemaObj.required = $required }

        # Get function description from PowerShell help system
        $help = (Get-Help $fn -ErrorAction SilentlyContinue)
        $desc = if ($help.Synopsis) { $help.Synopsis } else { "PowerShell function: $fn" }

        # Create MCP tool definition
        $tools += @{
            name        = $fn
            description = $desc
            inputSchema = $schemaObj
        }
    }
    return ,$tools
}

# Build index of available tools for quick lookup during calls
$ToolIndex = @{}
(Get-ToolList -FunctionNames $FunctionsToExpose) | ForEach-Object {
    $ToolIndex[$_.name] = $_
}

# ==============================================================================
# JSON-RPC RESPONSE HANDLERS
# ==============================================================================
# Standardized functions for sending JSON-RPC responses and errors

function Send-Result {
    <#
    .SYNOPSIS
        Sends a successful JSON-RPC response
    
    .DESCRIPTION
        Formats and sends a JSON-RPC 2.0 success response with the specified result data
    #>
    param($id, $result)
    Write-JsonRpc @{
        jsonrpc = "2.0"
        id      = $id
        result  = $result
    }
}

function Send-Error {
    <#
    .SYNOPSIS
        Sends a JSON-RPC error response
    
    .DESCRIPTION
        Formats and sends a JSON-RPC 2.0 error response with error code, message, and optional data
    #>
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

# ==============================================================================
# DATA CONVERSION UTILITIES
# ==============================================================================
# Helper functions for converting JSON objects to PowerShell hashtables

function ConvertTo-HashtableDeep {
    <#
    .SYNOPSIS
        Recursively converts PSCustomObject (from ConvertFrom-Json) into Hashtable
    
    .DESCRIPTION
        PowerShell's ConvertFrom-Json creates PSCustomObject instances, but PowerShell
        function splatting works better with hashtables. This function recursively
        converts the entire object tree to hashtables for proper parameter passing.
    #>
    param([Parameter()]$InputObject)
    
    # Handle null values
    if ($null -eq $InputObject) { return @{} }
    
    # Already a hashtable/dictionary - convert to ensure proper type
    if ($InputObject -is [System.Collections.IDictionary]) {
        return @{} + $InputObject
    }
    
    # PSCustomObject - convert properties to hashtable
    if ($InputObject -is [psobject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-HashtableDeep -InputObject $p.Value
        }
        return $h
    }
    
    # Arrays/lists - recursively process each item
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ,(ConvertTo-HashtableDeep -InputObject $item)
        }
        return ,$list
    }
    
    # Primitive types - return as-is
    return $InputObject
}

# ==============================================================================
# MAIN MESSAGE PROCESSING LOOP
# ==============================================================================
# The main event loop that handles incoming JSON-RPC messages and routes them
# to appropriate handlers based on the method name

$stderr.WriteLine("PowerShell MCP Server starting...")

while ($true) {
    try {
        # Read next JSON-RPC message from stdin
        $msg = Read-JsonLine
        if ($null -eq $msg) { 
            $stderr.WriteLine("Exiting main loop - null message")
            break 
        } # EOF condition - client disconnected
        
        if (-not $msg.method) { 
            $stderr.WriteLine("Skipping message without method")
            continue 
        } # Invalid message format

        # Extract message components
        $id     = $msg.id      # Request ID (null for notifications)
        $method = $msg.method  # JSON-RPC method name
        $params = $msg.params  # Method parameters

        $stderr.WriteLine("Processing method: $method with id: $id")

        # Route message to appropriate handler based on method
        switch ($method) {

            'initialize' {
                # MCP initialization handshake - respond with server capabilities
                $result = @{
                    protocolVersion = "2024-11-05"  # MCP protocol version
                    serverInfo      = @{
                        name    = "powershell-mcp-server"
                        version = "0.1.0"
                    }
                    capabilities = @{
                        tools = @{}  # Indicates this server supports tools
                    }
                }
                Send-Result $id $result
            }

            'notifications/initialized' {
                # Initialization complete notification (no response required)
                continue
            }

            'tools/list' {
                # Return list of available tools (functions)
                $result = @{
                    tools = @($ToolIndex.Values)
                }
                Send-Result $id $result
            }

            'resources/list' {
                # MCP resources capability (not implemented - return empty list)
                Send-Result $id @{ resources = @() }
            }

            'prompts/list' {
                # MCP prompts capability (not implemented - return empty list)
                Send-Result $id @{ prompts = @() }
            }

            'tools/call' {
                # Execute a specific tool (PowerShell function)
                try {
                    # Extract tool name and arguments
                    $name = $params.name
                    $args = $params.arguments

                    # Validate tool exists
                    if (-not $ToolIndex.ContainsKey($name)) {
                        Send-Error $id -32601 "Unknown tool: $name"
                        continue
                    }

                    # Convert arguments to hashtable for PowerShell splatting
                    # Handle various input types from JSON-RPC
                    $splat = @{}
                    if ($args -is [hashtable]) {
                        $splat = $args
                    } elseif ($args -is [System.Collections.IDictionary]) {
                        $splat = @{} + $args
                    } elseif ($args -ne $null) {
                        $splat = ConvertTo-HashtableDeep -InputObject $args
                    }

                    # Suppress PowerShell's verbose output during tool execution
                    # to keep JSON-RPC communication clean
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

                    # Execute the PowerShell function with provided arguments
                    # *>&1 captures all output streams (stdout, stderr, verbose, etc.)
                    $output = & $name @splat *>&1

                    # Restore original preference settings
                    $WarningPreference     = $prefBackup.Warning
                    $VerbosePreference     = $prefBackup.Verbose
                    $InformationPreference = $prefBackup.Information
                    $ProgressPreference    = $prefBackup.Progress

                    # Normalize output to string and clean ANSI escape sequences
                    $outText = if ($output -is [string]) { $output } else { ($output | Out-String) }
                    $outText = [regex]::Replace($outText, "`e\[[\d;]*[A-Za-z]", '')

                    # Return successful tool execution result
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
                    # Return tool execution error
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
                # Unknown method - only send error for requests (with id), ignore notifications
                if ($null -ne $id) {
                    Send-Error $id -32601 "Method not implemented: $method"
                }
            }
        }
    } catch {
        # Handle unexpected errors in main loop
        $stderr.WriteLine("Error in main loop: $_")
        if ($id) {
            Send-Error $id -32603 "Internal error: $_"
        }
    }
}

$stderr.WriteLine("PowerShell MCP Server stopped")
