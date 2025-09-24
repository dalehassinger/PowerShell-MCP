function Save-HTML-Report {
    <#
    .SYNOPSIS
      Saves an HTML report to the web server directory.
    .DESCRIPTION
      Saves the provided HTML content to the configured web path with the specified
      web page name for viewing through a web browser.
    .PARAMETER Report
      The HTML content to save to the file.
    .PARAMETER WebPageName
      The name of the HTML file (without .html extension).
    .OUTPUTS
      System.String (JSON status)
    .EXAMPLE
      Save-HTML-Report -Report "<html><body>Test</body></html>" -WebPageName "system-report"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Report,
        [Parameter(Mandatory)]
        [string]$WebPageName
    )
    
    $webPath = '/Library/WebServer/Documents'

    # Write HTML file to web path
    $htmlFilePath = Join-Path $webPath "$WebPageName.html"
    $Report | Out-File -FilePath $htmlFilePath -Encoding UTF8

    [PSCustomObject]@{
        Status = "Success"
        Message = "HTML file written to: $htmlFilePath"
        FilePath = $htmlFilePath
    } | ConvertTo-Json -Compress
}
