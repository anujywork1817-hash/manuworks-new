<#
.SYNOPSIS
    Deploys the LexDocs Flutter web app to S3 + CloudFront using the AWS CLI.

.DESCRIPTION
    Creates (idempotently) a private S3 bucket and a CloudFront distribution with
    TWO origins:

      /api/*  -> the Elastic Beanstalk backend  (no caching, all methods)
      /*      -> the S3 bucket (Flutter web build)

    Routing the API through the same distribution is what makes the web build
    work at all: CloudFront serves the page over HTTPS, and a browser refuses to
    let an HTTPS page call the backend's plain http:// endpoint (mixed content).
    Same-origin also means CORS never enters the picture.

    The S3 bucket stays private; CloudFront reaches it through an Origin Access
    Control (OAC), so the bucket is not publicly readable.

.PARAMETER ApiOrigin
    Backend origin DOMAIN NAME. Must be a hostname -- CloudFront rejects raw IP
    addresses as origins.

.PARAMETER CreateInfra
    Create the bucket/OAC/distribution if absent. Without it the script only
    builds, uploads and invalidates against existing infrastructure.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\deploy-web.ps1 -CreateInfra

.EXAMPLE
    # Routine redeploy of just the frontend
    powershell -ExecutionPolicy Bypass -File scripts\deploy-web.ps1
#>

[CmdletBinding()]
param(
    [string] $BucketName,
    [string] $ApiOrigin = 'Lexdocs-api-env.eba-bjjysxvm.ap-south-1.elasticbeanstalk.com',
    [string] $Region    = 'ap-south-1',
    [string] $Comment   = 'LexDocs web app',
    [switch] $CreateInfra,
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

$RepoRoot    = Split-Path -Parent $PSScriptRoot
$FlutterDir  = Join-Path $RepoRoot 'flutter\docassist_app'
$BuildDir    = Join-Path $FlutterDir 'build\web'

# Managed CloudFront policies (same IDs in every account/region).
$CACHE_OPTIMIZED   = '658327ea-f89d-4fab-a63d-7e88639e58f6'  # caches, honours origin Cache-Control
$CACHE_DISABLED    = '4135ea2d-6df8-44a3-9df3-4b5a84be39ad'  # never cache -- for /api/*
$ORIGIN_REQ_ALLVIEWER_NO_HOST = 'b689b0a8-53d0-40ab-baf2-68738e2966ac'

function Invoke-Aws {
    param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Args)
    $out = & aws @Args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "aws $($Args -join ' ')`n$out" }
    return $out
}

# ── Preflight ────────────────────────────────────────────────────────────────
Write-Host "Checking AWS identity..." -ForegroundColor Cyan
$account = (Invoke-Aws sts get-caller-identity --query Account --output text).Trim()
Write-Host "  account: $account"

if (-not $BucketName) { $BucketName = "lexdocs-web-$account" }
Write-Host "  bucket : $BucketName"
Write-Host "  region : $Region"
Write-Host "  api    : $ApiOrigin"

if ($ApiOrigin -match '^\d{1,3}(\.\d{1,3}){3}$') {
    throw "ApiOrigin '$ApiOrigin' is an IP address. CloudFront origins must be domain names. Use the Elastic Beanstalk CNAME instead."
}

# ── 1. Build ─────────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host "`nBuilding Flutter web (release)..." -ForegroundColor Cyan
    Push-Location $FlutterDir
    try {
        # No --dart-define: the app derives its API base URL from the page
        # origin on web, so it targets whatever domain serves it.
        & flutter build web --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }
    } finally { Pop-Location }
}
if (-not (Test-Path (Join-Path $BuildDir 'index.html'))) {
    throw "No build output at $BuildDir. Run without -SkipBuild."
}

# ── 2. Bucket ────────────────────────────────────────────────────────────────
$bucketExists = $true
try { Invoke-Aws s3api head-bucket --bucket $BucketName | Out-Null }
catch { $bucketExists = $false }

if (-not $bucketExists) {
    if (-not $CreateInfra) { throw "Bucket $BucketName does not exist. Re-run with -CreateInfra." }
    Write-Host "`nCreating bucket $BucketName..." -ForegroundColor Cyan
    Invoke-Aws s3api create-bucket --bucket $BucketName --region $Region `
        --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
    # Private bucket: CloudFront reads it via OAC, nobody reads it directly.
    Invoke-Aws s3api put-public-access-block --bucket $BucketName `
        --public-access-block-configuration `
        'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true' | Out-Null
    Write-Host "  created (private)"
} else {
    Write-Host "`nBucket exists: $BucketName"
}

# ── 3. Find or create the distribution ───────────────────────────────────────
$s3Domain = "$BucketName.s3.$Region.amazonaws.com"

$distId = ''
$dists = Invoke-Aws cloudfront list-distributions --output json | ConvertFrom-Json
if ($dists.DistributionList.Items) {
    foreach ($d in $dists.DistributionList.Items) {
        if ($d.Origins.Items | Where-Object { $_.DomainName -eq $s3Domain }) {
            $distId = $d.Id; break
        }
    }
}

if (-not $distId) {
    if (-not $CreateInfra) { throw "No distribution found for origin $s3Domain. Re-run with -CreateInfra." }

    Write-Host "`nCreating Origin Access Control..." -ForegroundColor Cyan
    $oacName = "$BucketName-oac"
    $oacId = ''
    $oacs = Invoke-Aws cloudfront list-origin-access-controls --output json | ConvertFrom-Json
    if ($oacs.OriginAccessControlList.Items) {
        $found = $oacs.OriginAccessControlList.Items | Where-Object { $_.Name -eq $oacName }
        if ($found) { $oacId = $found.Id }
    }
    if (-not $oacId) {
        $oacCfg = @{
            Name                             = $oacName
            Description                      = 'OAC for LexDocs web bucket'
            SigningProtocol                  = 'sigv4'
            SigningBehavior                  = 'always'
            OriginAccessControlOriginType    = 's3'
        } | ConvertTo-Json -Compress
        $oacFile = Join-Path $env:TEMP 'lexdocs-oac.json'
        [System.IO.File]::WriteAllText($oacFile, $oacCfg, (New-Object System.Text.UTF8Encoding($false)))
        $oacId = (Invoke-Aws cloudfront create-origin-access-control `
            --origin-access-control-config "file://$oacFile" `
            --query 'OriginAccessControl.Id' --output text).Trim()
    }
    Write-Host "  OAC: $oacId"

    Write-Host "`nCreating CloudFront distribution..." -ForegroundColor Cyan

    $distConfig = @{
        CallerReference      = "lexdocs-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Comment              = $Comment
        Enabled              = $true
        DefaultRootObject    = 'index.html'
        HttpVersion          = 'http2and3'
        PriceClass           = 'PriceClass_All'
        Origins = @{
            Quantity = 2
            Items = @(
                @{
                    Id                    = 's3-web'
                    DomainName            = $s3Domain
                    OriginPath            = ''
                    OriginAccessControlId = $oacId
                    S3OriginConfig        = @{ OriginAccessIdentity = '' }
                    CustomHeaders         = @{ Quantity = 0 }
                    ConnectionAttempts    = 3
                    ConnectionTimeout     = 10
                },
                @{
                    Id                 = 'eb-api'
                    DomainName         = $ApiOrigin
                    OriginPath         = ''
                    CustomHeaders      = @{ Quantity = 0 }
                    ConnectionAttempts = 3
                    ConnectionTimeout  = 10
                    CustomOriginConfig = @{
                        # EB single-instance serves plain HTTP; CloudFront
                        # terminates TLS for the viewer and talks HTTP to it.
                        HTTPPort               = 80
                        HTTPSPort              = 443
                        OriginProtocolPolicy   = 'http-only'
                        OriginSslProtocols     = @{ Quantity = 1; Items = @('TLSv1.2') }
                        # 60s is CloudFront's maximum without a quota increase
                        # ("Response timeout per origin"; hard ceiling 180s).
                        # Long AI/OCR calls can exceed this -- see DEPLOY-WEB.md.
                        OriginReadTimeout      = 60
                        OriginKeepaliveTimeout = 5
                    }
                }
            )
        }
        DefaultCacheBehavior = @{
            TargetOriginId       = 's3-web'
            ViewerProtocolPolicy = 'redirect-to-https'
            CachePolicyId        = $CACHE_OPTIMIZED
            Compress             = $true
            AllowedMethods       = @{
                Quantity      = 2
                Items         = @('GET', 'HEAD')
                CachedMethods = @{ Quantity = 2; Items = @('GET', 'HEAD') }
            }
        }
        CacheBehaviors = @{
            Quantity = 1
            Items = @(
                @{
                    PathPattern            = '/api/*'
                    TargetOriginId         = 'eb-api'
                    ViewerProtocolPolicy   = 'https-only'
                    CachePolicyId          = $CACHE_DISABLED
                    OriginRequestPolicyId  = $ORIGIN_REQ_ALLVIEWER_NO_HOST
                    Compress               = $true
                    AllowedMethods         = @{
                        Quantity      = 7
                        Items         = @('GET','HEAD','OPTIONS','PUT','POST','PATCH','DELETE')
                        CachedMethods = @{ Quantity = 2; Items = @('GET','HEAD') }
                    }
                }
            )
        }
        # Flutter uses client-side routing: a deep link like /documents/123 is
        # not an S3 object, so S3 returns 403/404. Rewrite both to index.html
        # with a 200 and let the app router resolve the path.
        CustomErrorResponses = @{
            Quantity = 2
            Items = @(
                @{ ErrorCode = 403; ResponseCode = '200'; ResponsePagePath = '/index.html'; ErrorCachingMinTTL = 10 },
                @{ ErrorCode = 404; ResponseCode = '200'; ResponsePagePath = '/index.html'; ErrorCachingMinTTL = 10 }
            )
        }
    } | ConvertTo-Json -Depth 12

    $cfgFile = Join-Path $env:TEMP 'lexdocs-dist.json'
    [System.IO.File]::WriteAllText($cfgFile, $distConfig, (New-Object System.Text.UTF8Encoding($false)))

    $created = Invoke-Aws cloudfront create-distribution --distribution-config "file://$cfgFile" --output json | ConvertFrom-Json
    $distId = $created.Distribution.Id
    Write-Host "  distribution: $distId"

    # Let this distribution -- and only it -- read the bucket.
    Write-Host "`nAttaching bucket policy for OAC..." -ForegroundColor Cyan
    $policy = @{
        Version = '2012-10-17'
        Statement = @(
            @{
                Sid       = 'AllowCloudFrontServicePrincipalReadOnly'
                Effect    = 'Allow'
                Principal = @{ Service = 'cloudfront.amazonaws.com' }
                Action    = 's3:GetObject'
                Resource  = "arn:aws:s3:::$BucketName/*"
                Condition = @{
                    StringEquals = @{
                        'AWS:SourceArn' = "arn:aws:cloudfront::${account}:distribution/$distId"
                    }
                }
            }
        )
    } | ConvertTo-Json -Depth 10
    $polFile = Join-Path $env:TEMP 'lexdocs-bucket-policy.json'
    [System.IO.File]::WriteAllText($polFile, $policy, (New-Object System.Text.UTF8Encoding($false)))
    Invoke-Aws s3api put-bucket-policy --bucket $BucketName --policy "file://$polFile" | Out-Null
    Write-Host "  attached"
} else {
    Write-Host "`nDistribution exists: $distId"
}

# ── 4. Upload ────────────────────────────────────────────────────────────────
# Flutter's web output is NOT content-hashed: main.dart.js keeps its name across
# builds. Caching it long in the *browser* would strand users on stale code that
# a CloudFront invalidation cannot reach. So the app shell revalidates on every
# load (cheap 304s), and only canvaskit/ -- versioned by the Flutter SDK -- gets
# a long TTL.
Write-Host "`nUploading to s3://$BucketName ..." -ForegroundColor Cyan

Invoke-Aws s3 sync $BuildDir "s3://$BucketName" --delete `
    --exclude 'canvaskit/*' `
    --cache-control 'public, max-age=0, must-revalidate' | Out-Null

if (Test-Path (Join-Path $BuildDir 'canvaskit')) {
    Invoke-Aws s3 sync (Join-Path $BuildDir 'canvaskit') "s3://$BucketName/canvaskit" `
        --cache-control 'public, max-age=31536000, immutable' | Out-Null
}
Write-Host "  uploaded"

# ── 5. Invalidate ────────────────────────────────────────────────────────────
Write-Host "`nInvalidating CloudFront cache..." -ForegroundColor Cyan
$inv = Invoke-Aws cloudfront create-invalidation --distribution-id $distId --paths '/*' --output json | ConvertFrom-Json
Write-Host "  invalidation: $($inv.Invalidation.Id)"

$domain = (Invoke-Aws cloudfront get-distribution --id $distId --query 'Distribution.DomainName' --output text).Trim()

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  URL   : https://$domain"
Write-Host "  API   : https://$domain/api/v1  ->  $ApiOrigin"
Write-Host ""
Write-Host "A new distribution takes ~10-15 min to finish deploying." -ForegroundColor Yellow
Write-Host "Check with: aws cloudfront get-distribution --id $distId --query 'Distribution.Status' --output text"
