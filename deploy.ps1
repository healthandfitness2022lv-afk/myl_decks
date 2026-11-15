param(
  [switch]$HostingOnly,
  [switch]$SkipTests,
  [ValidateSet('Both', 'MyLMazos', 'NexusTCG')]
  [string]$Site = 'MyLMazos'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# NexusTCG (nexustcg.web.app) es ahora una app independiente que se publica
# desde NEXUS/app_marketplace. Desde aquí solo se publica MyL Mazos.
if ($Site -ne 'MyLMazos') {
  throw "NexusTCG se publica desde app_marketplace (app independiente). Usa -Site MyLMazos."
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Invoke-Step {
  param(
    [string]$Title,
    [scriptblock]$Action
  )

  Write-Host "`n==> $Title" -ForegroundColor Cyan
  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "Falló: $Title (código $LASTEXITCODE)"
  }
}

function Copy-WebBuild {
  param([string]$Destination)

  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
  }
  Copy-Item -LiteralPath (Join-Path $root 'build\web') -Destination $Destination -Recurse
}

if (-not $SkipTests) {
  Invoke-Step 'Ejecutando pruebas' { flutter test }
}

$dashboardSource = Join-Path $root 'dashboard\index.html'
$mylOutput = Join-Path $root 'build\web-mylmazos'
$nexusOutput = Join-Path $root 'build\web-nexustcg'

if ($Site -in @('Both', 'MyLMazos')) {
  Invoke-Step 'Compilando MyL Mazos' {
    flutter build web --release --dart-define=APP_VARIANT=mylmazos
  }
  Copy-WebBuild -Destination $mylOutput

  $dashboardTargetDirectory = Join-Path $mylOutput 'dashboard'
  $dashboardTarget = Join-Path $dashboardTargetDirectory 'index.html'
  if (-not (Test-Path -LiteralPath $dashboardSource)) {
    throw "No se encontró el dashboard: $dashboardSource"
  }
  New-Item -ItemType Directory -Force -Path $dashboardTargetDirectory | Out-Null
  Copy-Item -LiteralPath $dashboardSource -Destination $dashboardTarget -Force

  Invoke-Step 'Validando JavaScript del dashboard' {
    node -e "const fs=require('fs');const h=fs.readFileSync('build/web-mylmazos/dashboard/index.html','utf8');const start=h.indexOf('<script>',h.indexOf('firebase-firestore'));const end=h.lastIndexOf('</script>');if(start<0||end<0)throw new Error('No se encontró el script del dashboard');new Function(h.slice(start+8,end));console.log('Dashboard válido');"
  }
}

if ($Site -in @('Both', 'NexusTCG')) {
  Invoke-Step 'Compilando NexusTCG Marketplace' {
    flutter build web --release --dart-define=APP_VARIANT=nexustcg
  }
  Copy-WebBuild -Destination $nexusOutput

  $nexusIndex = Join-Path $nexusOutput 'index.html'
  $indexContent = Get-Content -LiteralPath $nexusIndex -Raw -Encoding utf8
  $indexContent = $indexContent.Replace(
    'MyL Mazos reúne mazos, colección, mercado y comunidad de Mitos y Leyendas.',
    'NexusTCG es el mercado para comprar y vender cartas de Mitos y Leyendas.'
  ).Replace(
    'Mazos, colección, mercado y comunidad en una sola aplicación.',
    'Compra y vende cartas de Mitos y Leyendas.'
  ).Replace('MyL Mazos', 'NexusTCG').Replace(
    'https://mylmazos.web.app/',
    'https://nexustcg.web.app/'
  )
  Set-Content -LiteralPath $nexusIndex -Value $indexContent -Encoding utf8

  $nexusManifest = Join-Path $nexusOutput 'manifest.json'
  $manifestContent = Get-Content -LiteralPath $nexusManifest -Raw -Encoding utf8
  $manifestContent = $manifestContent.Replace('MyL Mazos', 'NexusTCG').Replace(
    'Mazos, colección, mercado y comunidad de Mitos y Leyendas.',
    'Compra y vende cartas de Mitos y Leyendas.'
  )
  Set-Content -LiteralPath $nexusManifest -Value $manifestContent -Encoding utf8
}

$hostingTarget = switch ($Site) {
  'MyLMazos' { 'hosting:mylmazos' }
  'NexusTCG' { 'hosting:nexustcg' }
  default { 'hosting' }
}

$targets = if ($HostingOnly) {
  $hostingTarget
} else {
  "$hostingTarget,firestore:rules,firestore:indexes"
}

Invoke-Step "Desplegando $targets" {
  firebase deploy --only $targets --project mylmazos
}

Write-Host "`nDeploy completado" -ForegroundColor Green
if ($Site -in @('Both', 'MyLMazos')) {
  Write-Host 'MyL Mazos: https://mylmazos.web.app/'
  Write-Host 'Dashboard: https://mylmazos.web.app/dashboard/'
}
if ($Site -in @('Both', 'NexusTCG')) {
  Write-Host 'NexusTCG:  https://nexustcg.web.app/'
}
