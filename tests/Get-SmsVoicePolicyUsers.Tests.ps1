Describe 'SMS/Voice policy scanner' {
    BeforeEach {
        $scannerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Get-SmsVoicePolicyUsers.ps1'
        $authPolicy = [PSCustomObject]@{ PolicyMigrationState = 'migrationComplete' }
        $disabledPolicy = [PSCustomObject]@{
            State = 'disabled'
            IncludeTargets = @([PSCustomObject]@{ TargetType = 'group'; Id = 'all_users' })
        }

        function Invoke-ScannerFixture($AuthenticationPolicy, $SmsPolicy, $VoicePolicy) {
            $messages = New-Object 'System.Collections.Generic.List[string]'
            $connections = New-Object 'System.Collections.Generic.List[string]'
            $fixtureDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -Path $fixtureDirectory -ItemType Directory | Out-Null
            $fixtureScript = Join-Path $fixtureDirectory 'Get-SmsVoicePolicyUsers.ps1'
            Copy-Item -Path $scannerPath -Destination $fixtureScript

            function Connect-MgGraph {
                param($Scopes, $TenantId, [switch]$NoWelcome)
                $connections.Add($TenantId)
            }
            function Get-MgPolicyAuthenticationMethodPolicy { $AuthenticationPolicy }
            function Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration {
                param($AuthenticationMethodConfigurationId)
                if ($AuthenticationMethodConfigurationId -eq 'sms') { $SmsPolicy }
                else { $VoicePolicy }
            }
            function Get-MgGroup {
                param($GroupId, $Property)
                if ($GroupId -eq 'missing-group') { throw 'Group unavailable' }
                [PSCustomObject]@{ DisplayName = "Group $GroupId" }
            }
            function Write-Host {
                param($Object, $ForegroundColor)
                $messages.Add([string]$Object)
            }

            & $fixtureScript -TenantId 'test-tenant'
            $rows = @(Get-ChildItem -Path $fixtureDirectory -Filter '*.csv' | Import-Csv)
            [PSCustomObject]@{ Text = $messages -join "`n"; Rows = $rows; Connections = $connections }
        }
    }

    It 'exports first-class exclusions alongside AdditionalProperties includes' {
        $smsPolicy = [PSCustomObject]@{
            State = 'enabled'
            AdditionalProperties = @{ includeTargets = @(@{ targetType = 'group'; id = 'all_users' }) }
            ExcludeTargets = @([PSCustomObject]@{ TargetType = 'group'; Id = 'excluded-group' })
        }
        $result = Invoke-ScannerFixture $authPolicy $smsPolicy $disabledPolicy
        $result.Rows.Count | Should Be 2
        $result.Rows[1].Type | Should Be 'Exclude'
        $result.Rows[1].Id | Should Be 'excluded-group'
        $result.Text | Should Match 'Exclude group: Group excluded-group'
        $result.Connections.Count | Should Be 1
        $result.Connections[0] | Should Be 'test-tenant'
    }

    It 'supports first-class includes and excludes without AdditionalProperties' {
        $voicePolicy = [PSCustomObject]@{
            State = 'enabled'
            IncludeTargets = @([PSCustomObject]@{ TargetType = 'group'; Id = 'included-group' })
            ExcludeTargets = @([PSCustomObject]@{ TargetType = 'group'; Id = 'excluded-group' })
        }
        $result = Invoke-ScannerFixture $authPolicy $disabledPolicy $voicePolicy
        $result.Rows.Count | Should Be 2
        $result.Rows[0].Policy | Should Be 'Voice'
        $result.Rows[0].Id | Should Be 'included-group'
        $result.Rows[1].Id | Should Be 'excluded-group'
    }

    It 'supports AdditionalProperties on policies and individual targets' {
        $smsPolicy = [PSCustomObject]@{
            State = 'enabled'
            AdditionalProperties = @{
                includeTargets = @([PSCustomObject]@{ AdditionalProperties = @{ targetType = 'user'; id = 'included-user' } })
                excludeTargets = @([PSCustomObject]@{ AdditionalProperties = @{ targetType = 'user'; id = 'excluded-user' } })
            }
        }
        $result = Invoke-ScannerFixture $authPolicy $smsPolicy $disabledPolicy
        $result.Rows.Count | Should Be 2
        $result.Rows[0].Id | Should Be 'included-user'
        $result.Rows[1].Id | Should Be 'excluded-user'
    }

    It 'falls back when first-class target properties are null' {
        $smsPolicy = [PSCustomObject]@{
            State = 'enabled'
            IncludeTargets = $null
            ExcludeTargets = $null
            AdditionalProperties = @{
                includeTargets = @(@{ targetType = 'group'; id = 'all_users' })
                excludeTargets = @(@{ targetType = 'group'; id = 'excluded-group' })
            }
        }
        $result = Invoke-ScannerFixture $authPolicy $smsPolicy $disabledPolicy
        $result.Rows.Count | Should Be 2
    }

    It 'preserves explicitly empty first-class collections over fallback targets' {
        $smsPolicy = [PSCustomObject]@{
            State = 'enabled'
            IncludeTargets = @()
            ExcludeTargets = @()
            AdditionalProperties = @{ includeTargets = @(@{ targetType = 'group'; id = 'all_users' }) }
        }
        $result = Invoke-ScannerFixture $authPolicy $smsPolicy $disabledPolicy
        $result.Rows.Count | Should Be 0
        $result.Text | Should Match 'No enabled SMS/Voice targets detected'
        $result.Text | Should Not Match 'Enabled SMS/Voice policy targets found'
    }

    It 'handles missing target collections without null-reference failures' {
        $result = Invoke-ScannerFixture $authPolicy ([PSCustomObject]@{ State = 'enabled' }) $disabledPolicy
        $result.Rows.Count | Should Be 0
        $result.Text | Should Match 'No enabled SMS/Voice targets detected'
    }

    It 'retains the group ID when display-name lookup fails' {
        $smsPolicy = [PSCustomObject]@{
            State = 'enabled'
            IncludeTargets = @([PSCustomObject]@{ TargetType = 'group'; Id = 'missing-group' })
        }
        $result = Invoke-ScannerFixture $authPolicy $smsPolicy $disabledPolicy
        $result.Rows[0].DisplayName | Should Be 'missing-group'
    }

    It 'warns for every incomplete or unknown migration state without claiming legacy users' {
        foreach ($migrationState in @('premigration', 'migrationInProgress', 'unknownFutureValue', $null)) {
            $policy = [PSCustomObject]@{ PolicyMigrationState = $migrationState }
            $result = Invoke-ScannerFixture $policy $disabledPolicy $disabledPolicy
            $result.Text | Should Match 'Assessment incomplete: legacy MFA/SSPR'
            $result.Text | Should Not Match 'no action required|No enabled SMS/Voice targets detected|Enabled SMS/Voice policy targets found'
            $result.Rows.Count | Should Be 0
        }
    }

    It 'reads migration and campaign state from AdditionalProperties' {
        $policy = [PSCustomObject]@{
            AdditionalProperties = @{
                policyMigrationState = 'migrationInProgress'
                registrationEnforcement = @{
                    authenticationMethodsRegistrationCampaign = @{ state = 'default' }
                }
            }
        }
        $result = Invoke-ScannerFixture $policy $disabledPolicy $disabledPolicy
        $result.Text | Should Match 'migration state: migrationInProgress'
        $result.Text | Should Match 'Registration campaign: Microsoft managed'
        $result.Text | Should Match 'Assessment incomplete: legacy MFA/SSPR'
    }

    It 'does not treat retained disabled-policy targets as enabled after migration' {
        $result = Invoke-ScannerFixture $authPolicy $disabledPolicy $disabledPolicy
        $result.Rows.Count | Should Be 0
        $result.Text | Should Match 'No enabled SMS/Voice targets detected in the Authentication Methods Policy'
        $result.Text | Should Not Match 'Assessment incomplete|no action required|Enabled SMS/Voice policy targets found'
    }

    It 'warns about legacy coverage even when enabled AMP targets are found' {
        $policy = [PSCustomObject]@{ PolicyMigrationState = 'premigration' }
        $smsPolicy = [PSCustomObject]@{
            State = 'enabled'
            IncludeTargets = @([PSCustomObject]@{ TargetType = 'group'; Id = 'all_users' })
        }
        $result = Invoke-ScannerFixture $policy $smsPolicy $disabledPolicy
        $result.Text | Should Match 'Assessment incomplete: legacy MFA/SSPR'
        $result.Text | Should Match 'Enabled SMS/Voice policy targets found'
    }

    It 'does not issue a negative assessment for an unknown method state' {
        $result = Invoke-ScannerFixture $authPolicy ([PSCustomObject]@{ State = 'unknownFutureValue' }) $disabledPolicy
        $result.Text | Should Match 'Assessment incomplete: SMS or Voice policy state is unknown'
        $result.Text | Should Not Match 'No enabled SMS/Voice targets detected|no action required'
    }

    It 'reports the current retirement date, opt-out limit, and working guide URL' {
        $smsPolicy = [PSCustomObject]@{
            State = 'enabled'
            IncludeTargets = @([PSCustomObject]@{ TargetType = 'group'; Id = 'all_users' })
        }
        $result = Invoke-ScannerFixture $authPolicy $smsPolicy $disabledPolicy
        $result.Text | Should Match 'Feb 1, 2027: Microsoft-provided SMS/Voice delivery retires'
        $result.Text | Should Match 'temporary opt-out'
        $result.Text | Should Match 'no opt-out from retirement enforcement'
        $result.Text | Should Match 'must register a passkey at sign-in'
        $result.Text | Should Match 'https://aka.ms/passkeydeploymentguide'
        $result.Text | Should Not Match 'Jan 28|passkey-deployment-guide|before Sep 1'
    }

    It 'keeps README dates and deployment links aligned with script guidance' {
        $readmePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'README.md'
        $readme = Get-Content -Path $readmePath -Raw
        $readme | Should Match 'Feb 1, 2027'
        $readme | Should Match 'https://aka.ms/passkeydeploymentguide'
        $readme | Should Match 'optOutSettings.passkeyDynamicMigration'
        $readme | Should Not Match 'Jan 28|January 28|passkey-deployment-guide|No change for users already'
    }
}