# PowerShell-MCP

A PowerShell MCP Server to integrate with **Claude Desktop**.

---

## Overview

This project was originally created during the **2025 VMware Explore Hackathon**.  

Special thanks to **Don** and **Amos** for their collaboration—sharing ideas, writing code, and being great teammates. The past two years of Hackathons together have been as much about building friendships as building projects.  

---

## Getting Started

To connect this PowerShell MCP Server with Claude Desktop, include a configuration entry similar to the example below:

```json
// claude_desktop_config.json
{
  "mcpServers": {
    "powershell-mcp": {
      "command": "pwsh",
      "args": [
        "-File",
        "path/to/PowerShell-MCP.ps1"
      ]
    }
  }
}
```

## Project Structure

To keep the MCP Server script clean, all **Tools** (PowerShell functions) are stored in a dedicated `tools` subfolder.  
When the server runs, it automatically loads every tool defined in that folder.  

All **configuration details** required for the tools to connect to their respective products are stored in the `mcp-config.yaml` file, located in the `config` subfolder.

Sample **Prompts** will be located in the `prompts` subfolder.
