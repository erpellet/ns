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

Install-Module -Name PSSodium -Confirm:$false -Force
Import-Module -Name PSSodium

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

$Secrets = @{
    "ARM_TENANT_ID"       = "$AzureTenantId"
    "ARM_SUBSCRIPTION_ID" = "$AzureSubscriptionId"
    "ARM_CLIENT_ID"       = "$SpnObjectId"
    "ARM_CLIENT_SECRET"   = "$SPNSecret"
}

Write-Host "Creating secrets with sodium.."
$Secrets.keys | ForEach-Object {
    $encryptedString = ConvertTo-SodiumEncryptedString `
        -Text "$($Secrets.$_)" `
        -PublicKey $GitHubPublicKey.Key

    Invoke-RestMethod `
        -Method PUT `
        -Uri "https://api.github.com/repos/$($GitHubUserNameOrOrg)/$($NewESLZRepository)/actions/secrets/$_" `
        -Headers @{
            "Accept"        = "application/vnd.github.v3+json";
            "Authorization" = "Token $($PATSecret)"
        }
        -Body (@{
            "key_id" = "$($GitHubPublicKey.key_id)"
            "encrypted_value" = "$encryptedString"
        } | ConvertTo-Json)
}