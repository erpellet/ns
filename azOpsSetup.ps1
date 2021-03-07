### PowerShell script to bootstrap AzOps into GitHub - as part of Enterprise-Scale landing zone setup 
### This script is developed and maintained by a set of diverse architects and engineers, part of the Azure Customer Architecture & Engineering team

    [CmdletBinding()]
    param (
     [string]$PAToken,
     [string]$GitHubUserNameOrOrg,
     [string]$SpnObjectId,
     [string]$AzureSpnPwd,
     [string]$AzureTenantId,
     [string]$AzureSubscriptionId
    )

    Install-Module -Name PowerShellForGitHub -Confirm:$false -Force
    Import-Module -Name PowerShellForGitHub

    $SecureString = $PAToken | ConvertTo-SecureString -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential "ignore", $SecureString

    Write-Host "Authenticating to GitHub using PA token..."

    Set-GitHubAuthentication -Credential $Cred

    $ESLZGitHubOrg = "Azure"
    $ESLZRepository = "AzOps-Accelerator"
    $TestRepo = "fromScript"
    #$TestRepo = $ESLZRepository

    Write-Host "Creating Git repository from template.."
    # Creating GitHub repository based on Enterprise-Scale

    Get-GitHubRepository -OwnerName $ESLZGitHubOrg `
                         -RepositoryName $ESLZRepository | New-GitHubRepositoryFromTemplate `
                         -TargetRepositoryName $TestRepo `
                         -TargetOwnerName $GitHubUserNameOrOrg

    # Get ESLZ template repository
    $GetESLZRepoTemplate = @{
        Uri     = "https://api.github.com/repos/$($ESLZGitHubOrg)/$($ESLZRepository)"
        Headers = @{
            Authorization = "Token $($PAToken)"
        }
        Method  = "GET"
    }
    $ESLZRepo = Invoke-RestMethod @GetESLZRepoTemplate

    # Creating secret for the Service Principal into GitHub

    Write-Host "Creating required secrets for Azure authorization..."
    $servicePrincipal = New-AzADServicePrincipal -DisplayName "$($GitHubUserNameOrOrg)-ESLZ123"
    New-AzRoleAssignment -ApplicationId $servicePrincipal.ApplicationId -RoleDefinitionName Owner

    $ARMClient = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($servicePrincipal.applicationId))
    $ARMSecret = [System.Net.NetworkCredential]::new("",$servicePrincipal.Secret).Password
    $ARMClientSecret = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ARMSecret))
    $ARMTenant = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-AzContext).Tenant.Id))
    $ARMSubscription = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-AzContext).Subscription.Id))

    Write-host "Getting GitHub Public Key to create new secrets..."
    $GetPublicKey = @{
        Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($TestRepo)/actions/secrets/public-key"
        Headers = @{
            Authorization = "Token $($PAToken)"
        }
        Method = "GET"
    }
    $GitHubPublicKey = Invoke-RestMethod @GetPublicKey

    $ARMClientIdBody = @"
{
    "encrypted_value": "$($ARMClient)",
    "key_id": "$($GitHubPublicKey.Key_id)"
}
"@
    
    Write-Host "Creating secret for ARMClient"
    $CreateARMClientId = @{
        Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($TestRepo)/actions/secrets/ARM_CLIENT_ID"
        Headers = @{
            Authorization = "Token $($PAToken)"
            "Content-Type" = "application/json"
            Accept = "application/vnd.github.v3+json"
        }
        Body = $ARMClientIdBody
        Method = "PUT"
    }
    Invoke-RestMethod @CreateARMClientId

    $ARMClientSecretBody = @"
{
    "encrypted_value": "$($ARMClientSecret)",
    "key_id": "$($GitHubPublicKey.Key_id)"
}
"@
    Write-Host "Creating secret for ARM Service Principal"
    $CreateARMClientSecret = @{
        Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($TestRepo)/actions/secrets/ARM_CLIENT_SECRET"
        Headers = @{
            Authorization = "Token $($PAToken)"
            "Content-Type" = "application/json"
            Accept = "application/vnd.github.v3+json"
        }
        Body = $ARMClientSecretBody
        Method = "PUT"
    }
    Invoke-RestMethod @CreateARMClientSecret

        $ARMTenantBody = @"
{
    "encrypted_value": "$($ARMTenant)",
    "key_id": "$($GitHubPublicKey.Key_id)"
}
"@
    Write-Host "Creating secret for ARM tenant id"
    $CreateARMTenant = @{
        Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($TestRepo)/actions/secrets/ARM_TENANT_ID"
        Headers = @{
            Authorization = "Token $($PAToken)"
            "Content-Type" = "application/json"
            Accept = "application/vnd.github.v3+json"
        }
        Body = $ARMTenantBody
        Method = "PUT"
    }
    Invoke-RestMethod @CreateARMTenant

    $ARMSubscriptionBody = @"
{
    "encrypted_value": "$($ARMSubscription)",
    "key_id": "$($GitHubPublicKey.Key_id)"
}
"@
    Write-Host "Creating secret for ARM subscription id"    
    $CreateARMSubscription = @{
        Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($TestRepo)/actions/secrets/ARM_SUBSCRIPTION_ID"
        Headers = @{
            Authorization = "Token $($PAToken)"
            "Content-Type" = "application/json"
            Accept = "application/vnd.github.v3+json"
        }
        Body = $ARMSubscriptionBody
        Method = "PUT"
    }
    Invoke-RestMethod @CreateARMSubscription