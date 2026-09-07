<#
.SYNOPSIS
    Shows SMS/Voice auth method policy scope and retirement guidance for your Entra tenant.
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
function Get-PolicyProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $value = $Object.$Name
    if ($null -ne $value) { return $value }
    if ($Object.AdditionalProperties -and $Object.AdditionalProperties.ContainsKey($Name)) {
        return $Object.AdditionalProperties[$Name]
    }
    return $null
}

function Get-PolicyScope($Policy) {
    $inc = @(Get-PolicyProperty $Policy 'includeTargets')
    $exc = @(Get-PolicyProperty $Policy 'excludeTargets')

    $result = @{ IsAllUsers = $false; IncludedGroups = @(); ExcludedGroups = @(); IncludedUsers = @(); ExcludedUsers = @() }

    foreach ($t in $inc) {
        $type = Get-PolicyProperty $t 'targetType'
        $id   = Get-PolicyProperty $t 'id'
        if ($type -eq "group") {
            if ($id -eq "all_users") { $result.IsAllUsers = $true }
            else {
                $name = try { (Get-MgGroup -GroupId $id -Property DisplayName).DisplayName } catch { $id }
                $result.IncludedGroups += [PSCustomObject]@{ Id = $id; DisplayName = $name }
            }
        } elseif ($type -eq "user") { $result.IncludedUsers += $id }
    }
    foreach ($t in $exc) {
        $type = Get-PolicyProperty $t 'targetType'
        $id   = Get-PolicyProperty $t 'id'
        if ($type -eq "group") {
            $name = try { (Get-MgGroup -GroupId $id -Property DisplayName).DisplayName } catch { $id }
            $result.ExcludedGroups += [PSCustomObject]@{ Id = $id; DisplayName = $name }
        } elseif ($type -eq "user") { $result.ExcludedUsers += $id }
    }
    return [PSCustomObject]$result
}

# Registration campaign
$authPolicy = Get-MgPolicyAuthenticationMethodPolicy
$migrationState = Get-PolicyProperty $authPolicy 'policyMigrationState'
if (-not $migrationState) { $migrationState = 'unknown' }
$regEnf = Get-PolicyProperty $authPolicy 'registrationEnforcement'
$campaign = Get-PolicyProperty $regEnf 'authenticationMethodsRegistrationCampaign'

$campaignState = Get-PolicyProperty $campaign 'state'
if (-not $campaignState) { $campaignState = 'unknown' }
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
function Test-ScopeHasTargets($Scope) {
    return ($null -ne $Scope -and ($Scope.IsAllUsers -or $Scope.IncludedGroups.Count -gt 0 -or $Scope.IncludedUsers.Count -gt 0))
}

$hasTargets = (Test-ScopeHasTargets $smsScope) -or (Test-ScopeHasTargets $voiceScope)
$migrationComplete = $migrationState -eq 'migrationComplete'
$policyStatesKnown = $smsPolicy.State -in @('enabled', 'disabled') -and $voicePolicy.State -in @('enabled', 'disabled')
Write-Host "`n===== IMPACT SUMMARY =====" -ForegroundColor Magenta
Write-Host "  Authentication methods migration state: $migrationState"
if (-not $migrationComplete) {
    Write-Host "  Assessment incomplete: legacy MFA/SSPR settings may still allow SMS/Voice and are not read by this script." -ForegroundColor Yellow
    Write-Host "  Verify legacy settings in the Entra admin center and complete authentication methods policy migration." -ForegroundColor Yellow
}
if (-not $policyStatesKnown) {
    Write-Host "  Assessment incomplete: SMS or Voice policy state is unknown." -ForegroundColor Yellow
}
if ($hasTargets) {
    Write-Host "  Enabled SMS/Voice policy targets found. Targets are not user counts or evidence of actual usage." -ForegroundColor Yellow
} elseif ($migrationComplete -and $policyStatesKnown) {
    Write-Host "  No enabled SMS/Voice targets detected in the Authentication Methods Policy." -ForegroundColor Green
}
if ($hasTargets -or -not $migrationComplete -or -not $policyStatesKnown) {
    Write-Host "  Public cloud retirement guidance (not a verification of tenant rollout or provider configuration):"
    Write-Host "  From Sep 1, 2026: SMS/Voice-enabled users in AMP or legacy MFA are auto-enabled for passkeys and nudged after MFA." -ForegroundColor Yellow
    Write-Host "  A temporary opt-out can delay automatic passkey and registration campaign enablement until Feb 1, 2027." -ForegroundColor Yellow
    Write-Host "  Feb 1, 2027: Microsoft-provided SMS/Voice delivery retires. There is no opt-out from retirement enforcement." -ForegroundColor Red
    Write-Host "  Users with only SMS/Voice available for MFA must register a passkey at sign-in unless migrated to a customer-managed provider." -ForegroundColor Yellow
    Write-Host "  Guide: https://aka.ms/passkeydeploymentguide" -ForegroundColor Cyan
    Write-Host "  Retirement and opt-out: https://learn.microsoft.com/entra/identity/authentication/concept-sms-voice-retirement" -ForegroundColor Cyan
}
Write-Host ""
