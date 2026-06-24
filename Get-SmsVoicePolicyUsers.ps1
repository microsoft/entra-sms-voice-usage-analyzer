<#
.SYNOPSIS
    Shows SMS/Voice auth method policy scope and passkey retirement impact for your Entra tenant.
.PARAMETER TenantId
    Your Entra ID tenant ID. Optional if already connected.
#>
param([string]$TenantId)

$ErrorActionPreference = "Stop"

# Connect
$connectParams = @{ Scopes = @("Policy.Read.All", "Group.Read.All") }
if ($TenantId) { $connectParams.TenantId = $TenantId }
Connect-MgGraph @connectParams -NoWelcome

# Helper: resolve policy targets
function Get-PolicyScope($Policy) {
    $inc = if ($Policy.AdditionalProperties.ContainsKey('includeTargets')) { $Policy.AdditionalProperties.includeTargets } else { @() }
    $exc = if ($Policy.AdditionalProperties.ContainsKey('excludeTargets')) { $Policy.AdditionalProperties.excludeTargets } else { @() }

    $result = @{ IsAllUsers = $false; IncludedGroups = @(); ExcludedGroups = @(); IncludedUsers = @(); ExcludedUsers = @() }

    foreach ($t in $inc) {
        $type = if ($t.targetType) { $t.targetType } else { $t.AdditionalProperties.targetType }
        $id   = if ($t.id) { $t.id } else { $t.AdditionalProperties.id }
        if ($type -eq "group") {
            if ($id -eq "all_users") { $result.IsAllUsers = $true }
            else {
                $name = try { (Get-MgGroup -GroupId $id -Property DisplayName).DisplayName } catch { $id }
                $result.IncludedGroups += [PSCustomObject]@{ Id = $id; DisplayName = $name }
            }
        } elseif ($type -eq "user") { $result.IncludedUsers += $id }
    }
    foreach ($t in $exc) {
        $type = if ($t.targetType) { $t.targetType } else { $t.AdditionalProperties.targetType }
        $id   = if ($t.id) { $t.id } else { $t.AdditionalProperties.id }
        if ($type -eq "group") {
            $name = try { (Get-MgGroup -GroupId $id -Property DisplayName).DisplayName } catch { $id }
            $result.ExcludedGroups += [PSCustomObject]@{ Id = $id; DisplayName = $name }
        } elseif ($type -eq "user") { $result.ExcludedUsers += $id }
    }
    return [PSCustomObject]$result
}

# Registration campaign
$authPolicy = Get-MgPolicyAuthenticationMethodPolicy
$regEnf = if ($authPolicy.RegistrationEnforcement) { $authPolicy.RegistrationEnforcement }
          elseif ($authPolicy.AdditionalProperties.ContainsKey('registrationEnforcement')) { $authPolicy.AdditionalProperties.registrationEnforcement }
          else { $null }
$campaign = if ($regEnf) {
    if ($regEnf.AuthenticationMethodsRegistrationCampaign) { $regEnf.AuthenticationMethodsRegistrationCampaign }
    else { $regEnf.authenticationMethodsRegistrationCampaign }
} else { $null }

$campaignState = if ($campaign) { if ($campaign.State) { $campaign.State } else { $campaign.state } } else { "unknown" }
$displayCampaign = if ($campaignState -eq 'default') { 'Microsoft managed' } else { $campaignState }
Write-Host "`nRegistration campaign: $displayCampaign" -ForegroundColor $(if ($campaignState -eq 'default') { 'Yellow' } elseif ($campaignState -eq 'enabled') { 'Green' } else { 'Red' })

# Fetch policies
$smsPolicy = Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId "sms"
$voicePolicy = Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId "voice"

Write-Host "`nSMS state: $($smsPolicy.State)" -ForegroundColor $(if ($smsPolicy.State -eq 'enabled') { 'Yellow' } else { 'Green' })
Write-Host "Voice state: $($voicePolicy.State)" -ForegroundColor $(if ($voicePolicy.State -eq 'enabled') { 'Yellow' } else { 'Green' })

$smsScope = if ($smsPolicy.State -eq "enabled") { Get-PolicyScope $smsPolicy } else { $null }
$voiceScope = if ($voicePolicy.State -eq "enabled") { Get-PolicyScope $voicePolicy } else { $null }

# Display scope
function Show-Scope($Name, $Scope) {
    if (-not $Scope) { return }
    Write-Host "`n  $Name scope:" -ForegroundColor Cyan
    if ($Scope.IsAllUsers) { Write-Host "    Include: ALL USERS" -ForegroundColor Yellow }
    foreach ($g in $Scope.IncludedGroups) { Write-Host "    Include group: $($g.DisplayName) ($($g.Id))" }
    foreach ($u in $Scope.IncludedUsers) { Write-Host "    Include user: $u" }
    foreach ($g in $Scope.ExcludedGroups) { Write-Host "    Exclude group: $($g.DisplayName) ($($g.Id))" -ForegroundColor Red }
    foreach ($u in $Scope.ExcludedUsers) { Write-Host "    Exclude user: $u" -ForegroundColor Red }
}

Show-Scope "SMS" $smsScope
Show-Scope "Voice" $voiceScope

# Export CSV
$export = @()
foreach ($p in @(@{N="SMS";S=$smsScope}, @{N="Voice";S=$voiceScope})) {
    $s = $p.S; if (-not $s) { continue }
    if ($s.IsAllUsers) { $export += [PSCustomObject]@{ Policy=$p.N; Type="Include"; TargetType="AllUsers"; Id="all_users"; DisplayName="All Users" } }
    foreach ($g in $s.IncludedGroups) { $export += [PSCustomObject]@{ Policy=$p.N; Type="Include"; TargetType="Group"; Id=$g.Id; DisplayName=$g.DisplayName } }
    foreach ($u in $s.IncludedUsers)  { $export += [PSCustomObject]@{ Policy=$p.N; Type="Include"; TargetType="User"; Id=$u; DisplayName="" } }
    foreach ($g in $s.ExcludedGroups) { $export += [PSCustomObject]@{ Policy=$p.N; Type="Exclude"; TargetType="Group"; Id=$g.Id; DisplayName=$g.DisplayName } }
    foreach ($u in $s.ExcludedUsers)  { $export += [PSCustomObject]@{ Policy=$p.N; Type="Exclude"; TargetType="User"; Id=$u; DisplayName="" } }
}
if ($export.Count -gt 0) {
    $path = Join-Path $PSScriptRoot "SmsVoicePolicyTargets_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $export | Export-Csv -Path $path -NoTypeInformation
    Write-Host "`nExported to: $path" -ForegroundColor Green
}

# Impact summary
$hasUsers = ($smsScope -or $voiceScope)
Write-Host "`n===== IMPACT SUMMARY =====" -ForegroundColor Magenta
if ($hasUsers) {
    Write-Host "  Sep 1, 2026:  Users in SMS/Voice scope auto-enabled for passkeys. Reg campaign set to Microsoft Managed." -ForegroundColor Yellow
    Write-Host "                To prevent: move users out of SMS/Voice AMP scope before Sep 1." -ForegroundColor Yellow
    Write-Host "  Jan 28, 2027: Microsoft SMS/Voice delivery RETIRED. Migrate to passkeys or configure customer-managed provider." -ForegroundColor Red
    Write-Host "  Guide: https://aka.ms/passkey-deployment-guide" -ForegroundColor Cyan
} else {
    Write-Host "  SMS/Voice disabled - no action required." -ForegroundColor Green
}
Write-Host ""
