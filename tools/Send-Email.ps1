function Send-Email {
    <#
    .SYNOPSIS
      Sends an HTML email via Gmail SMTP and returns a JSON status.
    .DESCRIPTION
      Creates and sends an HTML email using the specified recipient, subject, and body.
      Returns a compact JSON string indicating Success or Error.
    .PARAMETER ToEmail
      Recipient email address or a list separated by comma/semicolon (e.g. "a@b.com;c@d.com").
    .PARAMETER Subject
      Subject line for the email.
    .PARAMETER Body
      HTML body content for the email. The message is sent with IsBodyHtml = $true.
    .OUTPUTS
      System.String (JSON)
    .EXAMPLE
      Send-Email -ToEmail "user@example.com" -Subject "Hello" -Body "<p>Hi there</p>"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ToEmail,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Subject,
        [Parameter()]
        [string]$Body
    )
    # Email details
    $fromEmail = "dale.hassinger@gmail.com"

    # Default HTML body if none provided
    if (-not $PSBoundParameters.ContainsKey('Body') -or [string]::IsNullOrWhiteSpace($Body)) {
        $Body = '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>vCROCS Automation</title>
        <style>
            body { background-color:#ffffff; color:#000000; font-family:Arial,sans-serif; font-size:14px; margin:0; padding:20px; }
        </style></head><body>
        <p>VCF Operations Diagnostic Data attached to this email as an Excel File.</p>
        <p>Created by: vCROCS Automation</p>
        </body></html>'
    }

    # Gmail SMTP server details
    $smtpServer  = "smtp.gmail.com"
    $smtpPort    = 587
    $appPassword = $cfg.gmail.appPassword

    # Create the email message
    $emailMessage = New-Object system.net.mail.mailmessage
    $emailMessage.From = $fromEmail

    # Normalize and add recipients (support comma/semicolon, trim blanks)
    $recipients = $ToEmail -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if (-not $recipients -or $recipients.Count -eq 0) {
        [PSCustomObject]@{ Status="Error"; Message="ToEmail is empty after normalization." } | ConvertTo-Json -Compress
        return
    }
    foreach ($addr in $recipients) { $emailMessage.To.Add($addr) }

    $emailMessage.Subject = $Subject
    $emailMessage.Body = $Body
    $emailMessage.IsBodyHtml = $true

    # Configure the SMTP client
    $smtpClient = New-Object system.net.mail.smtpclient($smtpServer, $smtpPort)
    $smtpClient.EnableSsl = $true
    $smtpClient.Credentials = New-Object System.Net.NetworkCredential($fromEmail, $appPassword)

    # Send the email
    try {
        $smtpClient.Send($emailMessage)
        [PSCustomObject]@{
            Status  = "Success"
            Message = "Email sent successfully."
        } | ConvertTo-Json -Compress
    } catch {
        [PSCustomObject]@{
            Status  = "Error"
            Message = "Failed to send email: $($_.Exception.Message)"
        } | ConvertTo-Json -Compress
    } finally {
        $smtpClient.Dispose()
    }
} # End function

