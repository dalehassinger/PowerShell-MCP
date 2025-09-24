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

