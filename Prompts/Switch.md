# Example Prompts — Network Switch Reports

This document contains ready-to-use prompts for generating HTML reports of network switch health and performance. Each prompt clearly specifies style, layout, and content requirements.

> Tip: Replace placeholders like `{{SWITCH_NAME}}` or `{{REPORT_TIMEFRAME}}` as needed.

---

## Prompt 1 — Broadcom-Styled HTML Report (Email-Friendly)

**Goal:** Create an HTML report that can be sent via email and render cleanly in common email clients.

```text
Show all the stats for the Network Switch {{SWITCH_NAME}} for {{REPORT_TIMEFRAME}}.

Requirements:
- Include hardware status and overall health summary.
- Output must be pure HTML (email-safe) suitable for sending via email clients.
- Use Broadcom company colors for styling (headers, badges, accents).
- Use Tahoma as the primary font.
- Include CPU, Memory, and Port metrics.
- Create individual “Port cards” summarizing status and key metrics per port.
- Add color-coded Health Scores (e.g., green/yellow/red) with clear thresholds.
- Include a full ports table with color-coded status and metrics.
- Finish with a short executive summary and timestamp.

Delivery:
- Provide the complete HTML (inline CSS preferred for email compatibility).
- (Optional) Address the email to: dale.hassinger@outlook.com

---

Show all the stats for the Network Switch {{SWITCH_NAME}} for {{REPORT_TIMEFRAME}}.

Requirements:
- Include hardware status and overall health.
- Output as HTML with gauges styled in the spirit of VMware Aria Operations.
- Theme: VMware Operations Dark Mode look and feel.
- Use Tahoma as the primary font.
- Include CPU, Memory, and Port metrics.
- Create individual “Port cards” for each port.
- Use color-coded Health Scores (green/yellow/red) with clear thresholds.
- Include a complete ports table with color-coded metrics.
- Add a visual preview section at the top (mini dashboard snapshot).
- At the end, provide the generated HTML as a single string.

Persistence:
- Use the generated report code and save it via the tool: `Save-HTML-Report`.
  - Suggested filename pattern: `switch-{{SWITCH_NAME}}-{{YYYYMMDD-HHMM}}.html`


---

Show all the stats for the Network Switch {{SWITCH_NAME}} for {{REPORT_TIMEFRAME}}.

Requirements:
- Include hardware status and overall health.
- Output as HTML with gauges in the style of VMware Aria Operations.
- Theme: VMware Operations Dark Mode look and feel.
- Use Tahoma as the primary font.
- Include CPU, Memory, and Port metrics.
- Create individual “Port cards” per port.
- Use color-coded Health Scores (green/yellow/red) with clear thresholds.
- Include a full ports table with color-coded metrics.
- Append a Mermaid diagram section at the bottom of the report that visualizes:
  - The switch node
  - Uplink(s) / downlink(s)
  - Example connected devices (use placeholder names if unknown)

Mermaid:
- Provide a fenced code block with `mermaid` containing the diagram definition.
- Example diagram type: `flowchart` or `graph TD`, whichever best suits topology.

Delivery:
- Provide the complete HTML followed by the Mermaid code block.

---

Show all the stats for the Network Switch {{SWITCH_NAME}} for {{REPORT_TIMEFRAME}}.

Requirements:
- Include hardware status and overall health.
- Output as HTML with gauges in the style of VMware Aria Operations.
- Theme: VMware Operations Dark Mode look and feel.
- Use Tahoma as the primary font.
- Include CPU, Memory, and Port metrics.
- Create individual “Port cards” per port.
- Use color-coded Health Scores (green/yellow/red) with clear thresholds.
- Include a full ports table with color-coded metrics.

Delivery:
- Provide the complete HTML as a single code block.