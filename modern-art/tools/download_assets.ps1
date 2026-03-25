$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

function Download-File([string]$url, [string]$outPath) {
  Write-Host "Downloading: $url"
  Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing
}

$root = Split-Path -Parent $PSScriptRoot
$assetsDir = Join-Path $root "assets"
$downloadedDir = Join-Path $assetsDir "downloaded"
$tmpDir = Join-Path $assetsDir "_tmp"
$fontsDir = Join-Path $assetsDir "fonts"

Ensure-Dir $assetsDir
Ensure-Dir $downloadedDir
Ensure-Dir $tmpDir
Ensure-Dir $fontsDir

# CC0 packs (Kenney)
$pixelUiZip = Join-Path $tmpDir "kenney_pixel-ui-pack.zip"
$cardsZip   = Join-Path $tmpDir "kenney_playing-cards-pack.zip"

$pixelUiUrl = "https://www.kenney.nl/media/pages/assets/pixel-ui-pack/38633c7bb8-1677661508/kenney_pixel-ui-pack.zip"
$cardsUrl   = "https://www.kenney.nl/media/pages/assets/playing-cards-pack/08ea695cb6-1677495915/kenney_playing-cards-pack.zip"

if (-not (Test-Path $pixelUiZip)) { Download-File $pixelUiUrl $pixelUiZip }
if (-not (Test-Path $cardsZip))   { Download-File $cardsUrl $cardsZip }

$pixelUiExtract = Join-Path $tmpDir "pixel-ui-pack"
$cardsExtract   = Join-Path $tmpDir "playing-cards-pack"

if (-not (Test-Path $pixelUiExtract)) { Expand-Archive -Path $pixelUiZip -DestinationPath $pixelUiExtract -Force }
if (-not (Test-Path $cardsExtract))   { Expand-Archive -Path $cardsZip   -DestinationPath $cardsExtract   -Force }

# Copy a minimal subset into assets/downloaded/
Ensure-Dir (Join-Path $downloadedDir "ui")
Ensure-Dir (Join-Path $downloadedDir "cards")

# UI: copy PNGs (keep directory structure lightly)
Get-ChildItem -Path $pixelUiExtract -Recurse -Filter "*.png" | ForEach-Object {
  Copy-Item $_.FullName -Destination (Join-Path $downloadedDir "ui") -Force
}

# Cards: copy PNGs
Get-ChildItem -Path $cardsExtract -Recurse -Filter "*.png" | ForEach-Object {
  Copy-Item $_.FullName -Destination (Join-Path $downloadedDir "cards") -Force
}

# Chinese font (Noto Sans CJK SC)
$fontOut = Join-Path $fontsDir "NotoSansCJKsc-Regular.otf"
$fontUrl = "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
if (-not (Test-Path $fontOut)) { Download-File $fontUrl $fontOut }

Write-Host ""
Write-Host "Done."
Write-Host "Downloaded assets -> $downloadedDir"
Write-Host "Downloaded font   -> $fontOut"

