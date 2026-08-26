<#
.SYNOPSIS
    Builds the AWS Elastic Beanstalk deployment bundle for the LexDocs backend.

.DESCRIPTION
    Produces dist/lexdocs-backend-eb.zip, ready to upload in the Elastic
    Beanstalk console ("Upload your code" -> Local file) or via
    `eb deploy`/`aws elasticbeanstalk create-application-version`.

    Elastic Beanstalk requires the Dockerfile and Dockerrun.aws.json at the
    ROOT of the archive — not inside a backend/ folder — so the zip is built
    from the contents of backend/, not from the repo root.

    Secrets are never packed: backend/.env is excluded. Set environment
    properties on the EB environment instead (see DEPLOY-EB.md).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-eb-bundle.ps1
#>

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$SourceDir = Join-Path $RepoRoot 'backend'
$DistDir   = Join-Path $RepoRoot 'dist'
$ZipPath   = Join-Path $DistDir 'lexdocs-backend-eb.zip'

if (-not (Test-Path $SourceDir)) { throw "backend/ not found at $SourceDir" }

# Paths excluded from the bundle. Kept in sync with backend/.ebignore, which is
# what the EB CLI reads; this script is the no-EB-CLI path and must match it.
$ExcludeDirs = @(
    '.git', '.claude', '.idea', '.vscode',
    'storage', 'logs', 'bin', 'tmp', 'vendor',
    'cmd/gentestpdf'
)
$ExcludeFilePatterns = @(
    '*.env', '.env', '.env.*',
    '*.pdf', '*.docx',
    '*.exe', '*.dll', '*.so', '*.dylib',
    '*.swp', '*.swo', '.DS_Store', 'Thumbs.db',
    # Compiled server binaries built for manual deploys. Extensionless, so the
    # patterns above miss them; `backend/myapp` (63 MB) reached the bundle this
    # way. EB compiles from source via the Dockerfile and ignores these.
    'myapp', 'docassist', 'server', 'main'
)

# Nothing in a source bundle should be large. This is a backstop for build
# artifacts that dodge the name patterns above — the failure mode it catches is
# a stray binary silently bloating the upload.
$MaxFileSizeMB = 5

function Should-Exclude([string]$RelPath) {
    $normalized = $RelPath.Replace('\', '/')

    foreach ($dir in $ExcludeDirs) {
        if ($normalized -eq $dir -or $normalized.StartsWith("$dir/")) { return $true }
    }

    $leaf = Split-Path $normalized -Leaf
    foreach ($pattern in $ExcludeFilePatterns) {
        if ($leaf -like $pattern) { return $true }
    }

    return $false
}

Write-Host "Collecting files from $SourceDir ..." -ForegroundColor Cyan

$files = Get-ChildItem -Path $SourceDir -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($SourceDir.Length + 1)
    if (-not (Should-Exclude $rel)) {
        [pscustomobject]@{ FullName = $_.FullName; RelPath = $rel.Replace('\', '/') }
    }
}

# The deployment is meaningless without these two at the archive root.
foreach ($required in @('Dockerfile', 'Dockerrun.aws.json')) {
    if (-not ($files | Where-Object { $_.RelPath -eq $required })) {
        throw "Required file missing from bundle root: $required"
    }
}

# Fail loudly on anything oversized rather than silently shipping it.
$oversized = $files | Where-Object { (Get-Item $_.FullName).Length -gt ($MaxFileSizeMB * 1MB) }
if ($oversized) {
    Write-Host "Unexpectedly large files staged for the bundle:" -ForegroundColor Red
    foreach ($f in $oversized) {
        $mb = [math]::Round((Get-Item $f.FullName).Length / 1MB, 1)
        Write-Host "  $($f.RelPath)  ${mb} MB" -ForegroundColor Red
    }
    throw "Files exceed $MaxFileSizeMB MB. These are almost certainly build artifacts: add them to ExcludeFilePatterns or delete them."
}

if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Built entry-by-entry rather than with Compress-Archive: entry names must use
# forward slashes for the Linux-side EB agent to read them correctly.
$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $f.FullName, $f.RelPath,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally {
    $zip.Dispose()
}

$sizeMB = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)

Write-Host ""
Write-Host "Bundle: $ZipPath" -ForegroundColor Green
Write-Host "Files : $($files.Count)"
Write-Host "Size  : $sizeMB MB"
Write-Host ""
Write-Host "Root entries:" -ForegroundColor Cyan
$files | Where-Object { $_.RelPath -notmatch '/' } | ForEach-Object { Write-Host "  $($_.RelPath)" }
$files | Where-Object { $_.RelPath -match '^\.(ebextensions|platform)/' } | ForEach-Object { Write-Host "  $($_.RelPath)" }
Write-Host ""
Write-Host "Next: upload to Elastic Beanstalk. See DEPLOY-EB.md." -ForegroundColor Yellow
