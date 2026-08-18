# Create RAM users and OSS prefix policies for Alibaba Cloud OSS Windows mounts.
# Prerequisite: Alibaba Cloud CLI is installed and configured with an admin account.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Usernames,

    [string]$Bucket = "our-workspace",
    [string]$PrefixRoot = "users",
    [string]$RamUserPrefix = "oss-",
    [string]$PolicyNamePrefix = "oss-prefix-",

    [ValidateSet("Prefix", "FullBucket")]
    [string]$PolicyMode = "Prefix",

    [switch]$CreateAccessKey
)

$ErrorActionPreference = "Stop"

function Assert-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found. Install and configure Alibaba Cloud CLI first."
    }
}

function Invoke-AliyunJson {
    param([Parameter(Mandatory = $true)][string[]]$Args)

    $output = & aliyun @Args 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if ($exitCode -ne 0) {
        throw "aliyun $($Args -join ' ') failed: $text"
    }

    if (-not $text) {
        return $null
    }

    try {
        return $text | ConvertFrom-Json
    }
    catch {
        return $text
    }
}

function Test-RamUserExists {
    param([Parameter(Mandatory = $true)][string]$UserName)
    try {
        Invoke-AliyunJson -Args @("ram", "GetUser", "--UserName", $UserName) | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-PolicyExists {
    param([Parameter(Mandatory = $true)][string]$PolicyName)
    try {
        Invoke-AliyunJson -Args @("ram", "GetPolicy", "--PolicyType", "Custom", "--PolicyName", $PolicyName) | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function New-PrefixPolicyDocument {
    param(
        [Parameter(Mandatory = $true)][string]$BucketName,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    return [ordered]@{
        Version = "1"
        Statement = @(
            [ordered]@{
                Effect = "Allow"
                Action = @(
                    "oss:GetBucketLocation",
                    "oss:ListObjects",
                    "oss:ListObjectsV2"
                )
                Resource = "acs:oss:*:*:$BucketName"
                Condition = [ordered]@{
                    StringLike = [ordered]@{
                        "oss:Prefix" = @(
                            "$Prefix/",
                            "$Prefix/*"
                        )
                    }
                }
            },
            [ordered]@{
                Effect = "Allow"
                Action = @(
                    "oss:GetObject",
                    "oss:PutObject",
                    "oss:DeleteObject",
                    "oss:AbortMultipartUpload",
                    "oss:ListParts",
                    "oss:RestoreObject"
                )
                Resource = "acs:oss:*:*:$BucketName/$Prefix/*"
            }
        )
    }
}

function New-FullBucketPolicyDocument {
    param([Parameter(Mandatory = $true)][string]$BucketName)

    return [ordered]@{
        Version = "1"
        Statement = @(
            [ordered]@{
                Effect = "Allow"
                Action = @(
                    "oss:GetBucketLocation",
                    "oss:GetBucketInfo",
                    "oss:GetBucketStat",
                    "oss:ListObjects",
                    "oss:ListObjectsV2",
                    "oss:ListObjectVersions"
                )
                Resource = @("acs:oss:*:*:$BucketName")
            },
            [ordered]@{
                Effect = "Allow"
                Action = @(
                    "oss:GetObject",
                    "oss:PutObject",
                    "oss:DeleteObject",
                    "oss:DeleteObjectVersion",
                    "oss:AbortMultipartUpload",
                    "oss:ListParts",
                    "oss:RestoreObject"
                )
                Resource = @("acs:oss:*:*:$BucketName/*")
            }
        )
    }
}

function ConvertTo-PolicyJson {
    param([Parameter(Mandatory = $true)]$PolicyDocument)
    return ($PolicyDocument | ConvertTo-Json -Depth 20 -Compress)
}

Assert-Command aliyun

Write-Host "== Create OSS RAM users ==" -ForegroundColor Cyan
Write-Host "Bucket     : $Bucket"
Write-Host "PolicyMode : $PolicyMode"
Write-Host "Users      : $($Usernames -join ', ')"
Write-Host ""

$results = @()

foreach ($usernameRaw in $Usernames) {
    $username = $usernameRaw.Trim().Trim("/")
    if (-not $username) {
        continue
    }

    $ramUserName = "$RamUserPrefix$username"
    $safePolicySuffix = ($username -replace "[^A-Za-z0-9+=,.@_-]", "-")

    if ($PolicyMode -eq "FullBucket") {
        $ossPath = ""
        $policyName = "$PolicyNamePrefix$Bucket-full"
        $policyDoc = New-FullBucketPolicyDocument -BucketName $Bucket
    }
    else {
        $ossPath = "$PrefixRoot/$username"
        $policyName = "$PolicyNamePrefix$safePolicySuffix"
        $policyDoc = New-PrefixPolicyDocument -BucketName $Bucket -Prefix $ossPath
    }

    Write-Host "Processing $username -> RAM user $ramUserName" -ForegroundColor Cyan

    if (Test-RamUserExists -UserName $ramUserName) {
        Write-Host "  RAM user exists: $ramUserName"
    }
    else {
        Invoke-AliyunJson -Args @("ram", "CreateUser", "--UserName", $ramUserName, "--DisplayName", $username) | Out-Null
        Write-Host "  Created RAM user: $ramUserName" -ForegroundColor Green
    }

    if (Test-PolicyExists -PolicyName $policyName) {
        Write-Host "  Policy exists: $policyName"
    }
    else {
        $policyJson = ConvertTo-PolicyJson -PolicyDocument $policyDoc
        Invoke-AliyunJson -Args @("ram", "CreatePolicy", "--PolicyName", $policyName, "--PolicyDocument", $policyJson, "--Description", "OSS mount policy for $ramUserName") | Out-Null
        Write-Host "  Created policy: $policyName" -ForegroundColor Green
    }

    Invoke-AliyunJson -Args @("ram", "AttachPolicyToUser", "--PolicyType", "Custom", "--PolicyName", $policyName, "--UserName", $ramUserName) | Out-Null
    Write-Host "  Attached policy: $policyName"

    $accessKeyId = ""
    $accessKeySecret = ""

    if ($CreateAccessKey) {
        $keyResult = Invoke-AliyunJson -Args @("ram", "CreateAccessKey", "--UserName", $ramUserName)
        $accessKeyId = $keyResult.AccessKey.AccessKeyId
        $accessKeySecret = $keyResult.AccessKey.AccessKeySecret
        Write-Host "  Created AccessKey. Save it now; the secret is shown only once." -ForegroundColor Yellow
    }

    $results += [pscustomobject]@{
        Username = $username
        RamUserName = $ramUserName
        PolicyName = $policyName
        OssPath = $ossPath
        MountCommand = "把该用户的 AccessKey 私发给同事；同事使用统一安装包（CloudObjectStorageDrive.cmd）填写 Bucket/AK 即可"
        AccessKeyId = $accessKeyId
        AccessKeySecret = $accessKeySecret
    }

    Write-Host ""
}

Write-Host "== Result ==" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($CreateAccessKey) {
    $csvPath = Join-Path (Get-Location) "oss-ram-users-accesskeys.csv"
    $results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Warning "AccessKey secrets were saved to: $csvPath"
    Write-Warning "Keep this CSV private. Delete it after configuring the users' Cloud PCs."
}

