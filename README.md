# PowerShell-MCP:

A PowerShell MCP Server to integrate with **Claude Desktop**.  

All the code is 100% PowerShell.  


## Overview:

This project was originally created during the **2025 VMware Explore Hackathon**.  

Special thanks to **Don Horrox** and **Amos Clerizier** for their collaboration—sharing ideas, writing code, and being great teammates. The past two years of Hackathons together have been as much about building friendships as building projects.  

Thanks as well to **Cosmin** and **Willie**, who joined the team on Hackathon night and contributed valuable feedback and ideas.  


## Goals:

- **100% PowerShell** implementation — no external runtimes.
- **High reusability** of existing **PowerCLI** scripts with minimal changes (ideally just imports/parameter tweaks/return results as json).
- **First-class prompting** for **VMware Cloud Foundation (VCF)** products (e.g., vCenter, NSX, vSAN, Aria Operations).
- **On the fly** reports without generating any code to create the results  


## Getting Started:

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

Example json file in the code.  


## Project Structure:

To keep the MCP Server script clean, all **Tools** (PowerShell functions) are stored in a dedicated `tools` subfolder.  
When the server runs, it automatically loads every tool (*.ps1 file) defined in that folder.  

All **configuration details** required for the tools to connect to their respective products are stored in the `mcp-config.yaml` file, located in the `config` subfolder.

Sample **Prompts** will be located in the `prompts` subfolder.  

Example **Prompt Results** will be located in the `Prompt-Results` subfolder.  


## Feedback:

If you use this project as a starting point or adapt ideas for your own environment, I’d love to hear about it.  
Please consider sharing your feedback, suggestions, or improvements.  
Your input helps make this project better for everyone.  


## PowerShell Modules used with the MCP code and Tools:  

* PowerCLI  
* ImportExcel  
* powershell-yaml  
* Posh-SSH  


## Tools:

In the `tools` folder are functions that I used in my Lab to prompt against the following:

* VMware vCenter
* VCF Operations
* Network Switch
* Create DNS Records
* Send email
* Create MD Tables
* Create html reports in the style of VCF Operations
* If you can script it, you can prompt it!  

