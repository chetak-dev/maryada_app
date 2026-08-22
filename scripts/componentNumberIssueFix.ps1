# Fires componentNumberIssueFix for each objectNumber, one request per number.
# Endpoint accepts a single { "objectNumber": "..." } body (no bulk support).

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = "https://windchillqa.dx.deere.com/Windchill/deere/rest/tir/componentNumberIssueFix"

$headers = @{
  "Content-Type" = "application/json"
  "Accept"       = "application/json"   # ask for JSON so an HTML login page stands out
}

# --- Auth (pick ONE) ----------------------------------------------------------
# Your Insomnia call worked because it carried an authenticated session cookie.
# PowerShell has none, so Deere SSO returns an HTML login page (HTTP 200) and the
# fix never runs. Enable one of the options below to actually authenticate.
#
# Option A - HTTP Basic auth (prompted securely; nothing stored in this file):
# $cred  = Get-Credential -Message "Windchill QA credentials"
# $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($cred.UserName):$($cred.GetNetworkCredential().Password)"))
# $headers["Authorization"] = "Basic $basic"
#
# Option B - Reuse the session cookie from Insomnia/your browser:
# In Insomnia open the Cookies manager, copy the cookie(s) for
# windchillqa.dx.deere.com, and paste the full "name=value; name2=value2" string:
# $headers["Cookie"] = "PASTE_COOKIE_STRING_HERE"
# -----------------------------------------------------------------------------

# Shared session so any auth cookie returned on the first call is reused after.
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

$objectNumbers = @(
  "09001FAA869C285C","09001FAA86AC8B50","09001FAA8682C95D","09001FAA86A06196",
  "09001FAA85C2C654","09001FAA867A7E12","09001FAA869F9DF3","09001FAA860C8D09",
  "09001FAA867E44CF","09001FAA869F8231","09001FAA864BDCC1","09001FAA8449E150",
  "09001FAA8518C613","09001FAA846CEC60","09001FAA86AA6781"
)

$savedLoginPage = $false
$results = foreach ($num in $objectNumbers) {
  $body = @{ objectNumber = $num } | ConvertTo-Json
  try {
    $resp    = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -WebSession $session -UseBasicParsing
    $status  = [int]$resp.StatusCode
    $ctype   = "$($resp.Headers['Content-Type'])"
    $content = "$($resp.Content)"
    $isHtml  = ($ctype -match 'html') -or ($content -match '(?i)<!doctype html|<html')

    if ($isHtml) {
      if (-not $savedLoginPage) {
        $content | Out-File -FilePath "$PSScriptRoot\_login_response.html" -Encoding utf8
        $savedLoginPage = $true
      }
      Write-Host "$num -> NOT DONE: got HTML (auth required), HTTP $status" -ForegroundColor Yellow
      [pscustomobject]@{ objectNumber = $num; result = "AUTH-REQUIRED"; http = $status; response = "HTML login/SSO page (see _login_response.html)" }
    }
    else {
      Write-Host "$num -> OK (HTTP $status)" -ForegroundColor Green
      [pscustomobject]@{ objectNumber = $num; result = "OK"; http = $status; response = (($content -replace '\s+',' ').Trim()) }
    }
  }
  catch {
    $status = try { [int]$_.Exception.Response.StatusCode.value__ } catch { $null }
    Write-Host "$num -> FAILED (HTTP $status): $($_.Exception.Message)" -ForegroundColor Red
    [pscustomobject]@{ objectNumber = $num; result = "FAILED"; http = $status; response = $_.Exception.Message }
  }
}

Write-Host "`nSummary:" -ForegroundColor Cyan
$results | Format-Table objectNumber, result, http -AutoSize

$results | Export-Csv -Path "$PSScriptRoot\componentNumberIssueFix_results.csv" -NoTypeInformation -Encoding utf8
Write-Host "Full results written to scripts\componentNumberIssueFix_results.csv" -ForegroundColor DarkGray
