# Entra SMS/Voice Policy Scanner

Checks your Entra ID tenant's SMS and Voice authentication method policy scope and shows the impact of the upcoming passkey retirement timeline.

## What it does

- Shows the **registration campaign** state (enabled / disabled / Microsoft managed)
- Reports SMS and Voice policy **state** and **scope** (included/excluded groups and users)
- Exports targeted groups/users to CSV
- Displays an **impact summary** based on the [SMS/Voice retirement timeline](#retirement-timeline)

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
  Sep 1, 2026:  Users in SMS/Voice scope auto-enabled for passkeys. Reg campaign set to Microsoft Managed.
                To prevent: move users out of SMS/Voice AMP scope before Sep 1.
  Jan 28, 2027: Microsoft SMS/Voice delivery RETIRED. Migrate to passkeys or configure customer-managed provider.
  Guide: https://aka.ms/passkey-deployment-guide
```

## Retirement timeline

| Date | Milestone |
|------|-----------|
| **Sep 1, 2026** | Users in SMS/Voice AMP scope auto-enabled for passkeys. Registration campaign set to Microsoft Managed. |
| **Jan 28, 2027** | Microsoft-provided SMS and Voice delivery fully retired. |

### What this means

- Users enabled for SMS or Voice in the Authentication Methods Policy will be **auto-enabled for passkeys** on Sep 1, 2026.
- The **registration campaign** will be set to Microsoft Managed, nudging users to register passkeys.
- To **prevent auto-enablement**, move users out of SMS/Voice scope before Sep 1.
- By Jan 28, 2027, customers still needing SMS/Voice must configure a **customer-managed telecom provider** via the Security Store.
- No change for users already on passkeys, Microsoft Authenticator, Windows Hello, or FIDO2.

## Resources

- [Passkey deployment guide](https://aka.ms/passkey-deployment-guide)
- [Microsoft Entra authentication methods policy](https://learn.microsoft.com/entra/identity/authentication/concept-authentication-methods-manage)
