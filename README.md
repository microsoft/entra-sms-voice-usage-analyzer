# Entra SMS/Voice Policy Scanner

Checks your Entra ID tenant's SMS and Voice authentication method policy scope and shows guidance for the retirement of Microsoft-provided SMS and Voice delivery. The [Microsoft Learn retirement guidance](https://learn.microsoft.com/entra/identity/authentication/concept-sms-voice-retirement) is the source of truth for the timeline.

## What it does

- Shows the **registration campaign** state (enabled / disabled / Microsoft managed)
- Reports SMS and Voice policy **state** and enabled **scope** (included/excluded groups and explicit user targets)
- Exports policy targets to CSV, including exclusions
- Shows **authentication methods migration state** and warns when legacy MFA/SSPR coverage is unverified
- Displays an **impact summary** based on the [SMS/Voice retirement timeline](#retirement-timeline)

### Coverage and limitations

- This is a read-only **policy scope scanner**, not a user inventory or usage report. It does not expand group membership, calculate effective user counts after exclusions, inspect registered methods, or read sign-in activity. An `AllUsers` CSV row is a policy target, not an enumerated list of users.
- Targets retained on a **disabled** method configuration are not reported as enabled scope. They do not establish which users can use SMS/Voice through legacy policies.
- Only `policyMigrationState = migrationComplete` establishes that legacy MFA/SSPR policies are ignored. For incomplete, missing, or unknown migration states, the scanner warns that its assessment is incomplete. Verify legacy settings in the Entra admin center and follow the [authentication methods migration guide](https://learn.microsoft.com/entra/identity/authentication/how-to-authentication-methods-manage).
- A result of "No enabled SMS/Voice targets detected in the Authentication Methods Policy" is limited to that policy. It is not a general certification of migration readiness.
- The scanner does not inspect the temporary opt-out setting, customer-managed telecom provider configuration, or whether automatic passkey rollout has occurred in your tenant.
- The published timeline applies to **public cloud** environments. Azure AD B2C and External ID external tenants are outside this announcement; B2B and internal guest users are included. See the [retirement FAQ](https://learn.microsoft.com/entra/identity/authentication/concept-sms-voice-retirement-faq) for scope details, including SSPR.

## Prerequisites

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
```

## Usage

```powershell
.\Get-SmsVoicePolicyUsers.ps1 -TenantId "contoso.onmicrosoft.com"
```

Or if you're already connected to Graph:

```powershell
.\Get-SmsVoicePolicyUsers.ps1
```

## Required permissions

| Scope | Purpose |
|-------|---------|
| `Policy.Read.All` | Read authentication method policies |
| `Group.Read.All` | Resolve group display names |

**Minimum Entra role:** Global Reader, Authentication Policy Administrator, or Security Reader.

## Example output

```
Registration campaign: Microsoft managed

SMS state: disabled
Voice state: enabled

  Voice scope:
    Include: ALL USERS
    Exclude group: Service Accounts (abc-123-def)

Exported to: .\SmsVoicePolicyTargets_20260624_100000.csv

===== IMPACT SUMMARY =====
  Authentication methods migration state: migrationComplete
  Enabled SMS/Voice policy targets found. Targets are not user counts or evidence of actual usage.
  Public cloud retirement guidance (not a verification of tenant rollout or provider configuration):
  From Sep 1, 2026: SMS/Voice-enabled users in AMP or legacy MFA are auto-enabled for passkeys and nudged after MFA.
  A temporary opt-out can delay automatic passkey and registration campaign enablement until Feb 1, 2027.
  Feb 1, 2027: Microsoft-provided SMS/Voice delivery retires. There is no opt-out from retirement enforcement.
  Users with only SMS/Voice available for MFA must register a passkey at sign-in unless migrated to a customer-managed provider.
  Guide: https://aka.ms/passkeydeploymentguide
  Retirement and opt-out: https://learn.microsoft.com/entra/identity/authentication/concept-sms-voice-retirement
```

## Retirement timeline

| Date | Milestone |
|------|-----------|
| **Sep 1, 2026** | Automatic passkey enablement and registration campaign rollout begins for users enabled for SMS/Voice in AMP or legacy MFA, subject to the temporary opt-out. |
| **Sep 18, 2026** | Telecom provider information becomes available through the Microsoft Security Store. |
| **Oct 30, 2026** | Customers can begin selecting and configuring a telecom provider through the Microsoft Security Store. |
| **Feb 1, 2027** | Microsoft-provided SMS and Voice delivery fully retired; temporary opt-out no longer applies. |

### What this means

- From Sep 1, 2026, users enabled for SMS or Voice in AMP or legacy MFA are automatically enabled for a passkey profile allowing all passkey types, subject to the temporary opt-out.
- The **registration campaign** is set to Microsoft Managed targeting passkeys. In-scope users are nudged after completing MFA, with unlimited snoozes by default.
- A **temporary opt-out** can delay automatic passkey and campaign enablement until Feb 1, 2027. The [documented procedure](https://learn.microsoft.com/entra/identity/authentication/concept-sms-voice-retirement#temporarily-opt-out-of-the-automatic-passkey-enablement) sets `optOutSettings.passkeyDynamicMigration` to `true` using Microsoft Graph beta and requires `Policy.ReadWrite.AuthenticationMethod`. This scanner neither requests that write permission nor changes the setting. The opt-out does not exempt a tenant from February enforcement.
- By Feb 1, 2027, migrate users to phishing-resistant methods. Where SMS/Voice remains necessary, configure a **customer-managed telecom provider** through the Security Store and migrate the affected users before retirement.
- After retirement, users whose only available MFA method is SMS/Voice must complete **blocking passkey registration** at sign-in unless migrated to a customer-managed provider. This prompt cannot be snoozed.
- Existing phishing-resistant methods remain usable, but users still enabled for SMS/Voice may receive passkey registration prompts even if they already use another method.

## Validation

### Offline regression tests

The tests run the scanner with synthetic policy responses and local substitutes for Graph commands. They do not authenticate or change a tenant, and CSV output is confined to Pester's temporary test directory. The suite is tested with Pester 3.4.0.

```powershell
Import-Module Pester -RequiredVersion 3.4.0
Invoke-Pester -Script .\tests\Get-SmsVoicePolicyUsers.Tests.ps1
```

Coverage includes first-class SDK properties and `AdditionalProperties`, exclusions in console and CSV output, null and empty collections, disabled policies with retained targets, incomplete and unknown migration states, and retirement guidance consistency.

### Read-only tenant validation

1. Run the scanner with your test tenant ID or domain and the documented reader permissions.
2. Compare SMS/Voice state and all included/excluded targets with **Entra ID > Authentication methods > Policies**. Check both console output and the exported CSV. If your tenant has no exclusions, that live case remains unverified; the offline fixtures cover it.
3. Confirm that the reported migration state and registration campaign state match the portal.
4. For a migrated tenant with both methods disabled, expect no enabled targets, no CSV, and no legacy-coverage warning. If a method is enabled with targets, expect those targets and retirement guidance instead.

Do **not** attempt to reverse a completed migration to test legacy behavior. The regression suite simulates `premigration`, `migrationInProgress`, and unknown states, including disabled policies retaining `all_users`, and checks that none produces a false clean assessment. End-to-end validation of an actual legacy tenant still requires an existing unmigrated tenant; these tests do not establish actual legacy user coverage.

Exports contain tenant identifiers and group names. Keep them local and redact them before sharing in issues.

## Resources

- [Passkey deployment guide](https://aka.ms/passkeydeploymentguide)
- [SMS and Voice retirement guidance](https://learn.microsoft.com/entra/identity/authentication/concept-sms-voice-retirement)
- [Microsoft Entra authentication methods policy](https://learn.microsoft.com/entra/identity/authentication/concept-authentication-methods-manage)
