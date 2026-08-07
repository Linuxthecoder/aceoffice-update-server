<#
Publishes a built AceOffice release to GitHub Releases and triggers a Vercel
deploy hook so the update server serves the new files.

Prereqs:
  - GitHub CLI (gh) installed and authenticated:  gh auth login
  - Built artifacts exist in apps/shell/release. Build with your update URL:

        $env:ACEOFFICE_UPDATE_URL = "https://aceoffice-updates.vercel.app"
        npm run dist:win          # from the genoffice repo root

Usage:
  .\scripts\publish.ps1 -Repo "your-username/aceoffice-releases"

  Optional:
    -Tag "0.5.0"                 defaults to the version from latest.yml
    -VercelDeployHook "https://..."  auto-trigger a Vercel rebuild after upload
                                     (get the URL from Vercel dashboard:
                                      Settings > Git > Deploy Hooks)
#>

param(
    [string]$ReleaseDir = "$PSScriptRoot\..\..\genoffice\apps\shell\release",
    [string]$Repo = "",
    [string]$Tag = "",
    [string]$VercelDeployHook = ""
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI not found. Install it from https://cli.github.com and run 'gh auth login'."
}
if (-not $Repo) { Write-Error "-Repo is required (format: owner/repo)." }

$Resolved = Resolve-Path -LiteralPath $ReleaseDir -ErrorAction SilentlyContinue
if (-not $Resolved) { Write-Error "Release dir not found: $ReleaseDir" }
$ReleaseDir = $Resolved.Path

$latestYml = Join-Path $ReleaseDir 'latest.yml'
if (-not (Test-Path -LiteralPath $latestYml)) {
    Write-Error "latest.yml not found in $ReleaseDir. Run 'npm run dist:win' first."
}

$yml = Get-Content -LiteralPath $latestYml

if (-not $Tag) {
    $versionLine = $yml | Where-Object { $_ -match '^version:' } | Select-Object -First 1
    if (-not $versionLine) { Write-Error "Cannot find 'version:' in latest.yml; pass -Tag explicitly." }
    $Tag = (($versionLine -split ':', 2)[1]).Trim()
}
$pathLine = $yml | Where-Object { $_ -match '^path:' } | Select-Object -First 1
if (-not $pathLine) { Write-Error "Cannot find 'path:' in latest.yml." }
$installerName = (($pathLine -split ':', 2)[1]).Trim().Trim('"')

$installer = Join-Path $ReleaseDir $installerName
if (-not (Test-Path -LiteralPath $installer)) {
    Write-Error "Installer not found: $installer (latest.yml says '$installerName')."
}

Write-Host "Publishing AceOffice $Tag from $ReleaseDir" -ForegroundColor Cyan

gh release view $Tag --repo $Repo --json tagName --jq .tagName | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Release $Tag exists - uploading files..."
    gh release upload $Tag $latestYml $installer --repo $Repo --clobber
}
else {
    Write-Host "Creating release $Tag ..."
    gh release create $Tag $latestYml $installer --repo $Repo --title "AceOffice $Tag" --latest
}
if ($LASTEXITCODE -ne 0) { Write-Error "GitHub release step failed." }

if ($VercelDeployHook) {
    Write-Host "Triggering Vercel deploy hook..."
    Invoke-RestMethod -Method Post -Uri $VercelDeployHook | Out-Null
    Write-Host "Vercel deploy triggered."
}

Write-Host "Done. The update feed is live once Vercel finishes building." -ForegroundColor Green
