### PowerShell script to bootstrap AzOps into GitHub - as part of Enterprise-Scale landing zone setup 
### This script is developed and maintained by a set of diverse architects and engineers, part of the Azure Customer Architecture & Engineering team

[CmdletBinding()]
param (
 [string]$KeyVault,
 [string]$GitHubUserNameOrOrg,
 [string]$PATSecretName,
 [string]$SPNSecretName,
 [string]$SpnObjectId,
 [string]$AzureTenantId,
 [string]$AzureSubscriptionId,
 [string]$EnterpriseScalePrefix
)

$DeploymentScriptOutputs = @{}
Write-Host "Starting...."

$ErrorActionPreference = "Continue"
Install-Module -Name PowerShellForGitHub -Confirm:$false -Force
Import-Module -Name PowerShellForGitHub

Try {
    Write-Host "Getting secrets from KeyVault"

    Write-Host "Getting $($PATSecretName)"
    $DeploymentScriptOutputs['PATSecretName'] = $PATSecretName

    $PATSecret = Get-AzKeyVaultSecret -VaultName $KeyVault -Name $PATSecretName -AsPlainText
    
    Write-Host "Converting $($PATSecretName)"
    $SecureString = $PATSecret | ConvertTo-SecureString -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential "ignore", $SecureString

    $DeploymentScriptOutputs['Credentials'] = $Cred
}
Catch {
    $ErrorMessage = "Failed to retrieve the secret from $($KeyVault)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
}
Try {
    Write-Host "Getting secrets from KeyVault"
    
    Write-Host "Getting $($SPNSecretName)"
    $DeploymentScriptOutputs['PATSecretName'] = $SPNSecretName

    $SPNSecret = Get-AzKeyVaultSecret -VaultName $KeyVault -Name $SPNSecretName -AsPlainText
}
Catch {
    $ErrorMessage = "Failed to retrieve the secret from $($KeyVault)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
}

$ESLZGitHubOrg = "Azure"
$ESLZRepository = "AzOps-Accelerator"
$NewESLZRepository = $EnterpriseScalePrefix + '-' + $ESLZRepository
$DeploymentScriptOutputs['Repository'] = $NewESLZRepository
Try {
    Write-Host "Authenticating to GitHub using PA token..."

    Set-GitHubAuthentication -Credential $Cred
}
Catch {
    $ErrorMessage = "Failed to authenticate to Git. Ensure you provided the correct PA Token for $($GitHubUserNameOrOrg)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
}
Try {
    Write-Host "Creating Git repository from template..."
    Write-Host "Checking if repository already exists..."
    # Creating GitHub repository based on Enterprise-Scale
    $CheckIfRepoExists = @{
        Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($NewESLZRepository)"
        Headers = @{
            Authorization = "Token $($PATSecret)"
            "Content-Type" = "application/json"
            Accept = "application/vnd.github.v3+json"
        }
        Method = "GET"
    }
    $CheckExistence = Invoke-RestMethod @CheckIfRepoExists -ErrorAction Continue
}
Catch {
    Write-Host "Repository doesn't exist, hence throwing a $($_.Exception.Response.StatusCode.Value__)"
}
if ([string]::IsNullOrEmpty($CheckExistence)){
Try{
    Write-Host "Repository does not exist in target organization/user - script will continue"

    Get-GitHubRepository -OwnerName $ESLZGitHubOrg `
                     -RepositoryName $ESLZRepository | New-GitHubRepositoryFromTemplate `
                     -TargetRepositoryName $NewESLZRepository `
                     -TargetOwnerName $GitHubUserNameOrOrg
}
Catch {
    $ErrorMessage = "Failed to create Git repository for $($GitHubUserNameOrOrg)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
}
# Creating secret for the Service Principal into GitHub

$ARMClient = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($SpnObjectId))
$ARMSecret = [System.Net.NetworkCredential]::new("",$SPNSecret).Password
$ARMClientSecret = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ARMSecret))
$ARMTenant = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($AzureTenantId))
$ARMSubscription = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($AzureSubscriptionId))

Try {
Write-host "Getting GitHub Public Key to create new secrets..."
$GetPublicKey = @{
    Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($NewESLZRepository)/actions/secrets/public-key"
    Headers = @{
        Authorization = "Token $($PATSecret)"
    }
    Method = "GET"
}
$GitHubPublicKey = Invoke-RestMethod @GetPublicKey
}
Catch {
    $ErrorMessage = "Failed to retrieve Public Key for $($GitHubUserNameOrOrg)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
}
Try {
$ARMClientIdBody = @"
{
"encrypted_value": "$($ARMClient)",
"key_id": "$($GitHubPublicKey.Key_id)"
}
"@

Write-Host "Creating secret for ARMClient"
$CreateARMClientId = @{
    Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($NewESLZRepository)/actions/secrets/ARM_CLIENT_ID"
    Headers = @{
        Authorization = "Token $($PATSecret)"
        "Content-Type" = "application/json"
        Accept = "application/vnd.github.v3+json"
    }
    Body = $ARMClientIdBody
    Method = "PUT"
}
Invoke-RestMethod @CreateARMClientId
}
Catch {
    $ErrorMessage = "Failed to create secret for $($GitHubUserNameOrOrg)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
}
Try {
$ARMClientSecretBody = @"
{
"encrypted_value": "$($ARMClientSecret)",
"key_id": "$($GitHubPublicKey.Key_id)"
}
"@
Write-Host "Creating secret for ARM Service Principal"
$CreateARMClientSecret = @{
    Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($NewESLZRepository)/actions/secrets/ARM_CLIENT_SECRET"
    Headers = @{
        Authorization = "Token $($PATSecret)"
        "Content-Type" = "application/json"
        Accept = "application/vnd.github.v3+json"
    }
    Body = $ARMClientSecretBody
    Method = "PUT"
}
Invoke-RestMethod @CreateARMClientSecret
}
Catch {
    $ErrorMessage = "Failed to create secret for $($GitHubUserNameOrOrg)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
}
Try {
    $ARMTenantBody = @"
{
"encrypted_value": "$($ARMTenant)",
"key_id": "$($GitHubPublicKey.Key_id)"
}
"@
Write-Host "Creating secret for ARM tenant id"
$CreateARMTenant = @{
    Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($NewESLZRepository)/actions/secrets/ARM_TENANT_ID"
    Headers = @{
        Authorization = "Token $($PATSecret)"
        "Content-Type" = "application/json"
        Accept = "application/vnd.github.v3+json"
    }
    Body = $ARMTenantBody
    Method = "PUT"
}
Invoke-RestMethod @CreateARMTenant
}
Catch {
    $ErrorMessage = "Failed to create Secret for $($GitHubUserNameOrOrg)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
}
Try {
$ARMSubscriptionBody = @"
{
"encrypted_value": "$($ARMSubscription)",
"key_id": "$($GitHubPublicKey.Key_id)"
}
"@
Write-Host "Creating secret for ARM subscription id"    
$CreateARMSubscription = @{
    Uri     = "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($NewESLZRepository)/actions/secrets/ARM_SUBSCRIPTION_ID"
    Headers = @{
        Authorization = "Token $($PATSecret)"
        "Content-Type" = "application/json"
        Accept = "application/vnd.github.v3+json"
    }
    Body = $ARMSubscriptionBody
    Method = "PUT"
}
Invoke-RestMethod @CreateARMSubscription
}
Catch {
    $ErrorMessage = "Failed to create Git repository for $($GitHubUserNameOrOrg)."
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
                -ErrorAction Stop
    }
}
{
    Write-Host "Repo already exists!"
}

