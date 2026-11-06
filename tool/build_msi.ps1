# Script de automação para geração do instalador MSI (Windows Installer) via WiX Toolset
# Uso: powershell -ExecutionPolicy Bypass -File tool\build_msi.ps1

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $rootDir

# 1. Garante que o WiX Toolset está presente
$wixDir = Join-Path $rootDir "tool\wix314"
if (-not (Test-Path (Join-Path $wixDir "candle.exe"))) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $rootDir "tool\fetch_wix.ps1")
}

$heatExe = Join-Path $wixDir "heat.exe"
$candleExe = Join-Path $wixDir "candle.exe"
$lightExe = Join-Path $wixDir "light.exe"

# 2. Verifica se a pasta de Release existe
$releaseDir = Join-Path $rootDir "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $releaseDir "bemybench.exe"))) {
    throw "Pasta Release não encontrada ou incompleta. Execute 'flutter build windows --release' primeiro."
}

# 3. Prepara pastas temporárias
$msiBuildDir = Join-Path $rootDir "build\msi"
if (Test-Path $msiBuildDir) { Remove-Item $msiBuildDir -Recurse -Force }
New-Item -ItemType Directory -Path $msiBuildDir -Force | Out-Null

$outputMsi = Join-Path $releaseDir "bemybench-windows-x64.msi"
if (Test-Path $outputMsi) { Remove-Item $outputMsi -Force }

Write-Host "[1/4] Coletando arquivos da aplicação com Heat..." -ForegroundColor Cyan
$appFilesWxs = Join-Path $msiBuildDir "AppFiles.wxs"
& $heatExe dir $releaseDir `
    -cg AppFiles `
    -gg `
    -scom `
    -sreg `
    -sfrag `
    -srd `
    -dr INSTALLFOLDER `
    -var "var.SourceDir" `
    -out $appFilesWxs

if ($LASTEXITCODE -ne 0) { throw "Heat falhou ao colher arquivos." }

Write-Host "[2/4] Compilando arquivos WiX com Candle..." -ForegroundColor Cyan
$productWxs = Join-Path $rootDir "windows\packaging\msi\Product.wxs"
& $candleExe `
    -arch x64 `
    "-dSourceDir=$releaseDir" `
    "-dProjectDir=$rootDir" `
    -out "$msiBuildDir\" `
    $productWxs `
    $appFilesWxs

if ($LASTEXITCODE -ne 0) { throw "Candle falhou ao compilar WXS." }

Write-Host "[3/4] Gerando pacote MSI com Light..." -ForegroundColor Cyan
$productWixObj = Join-Path $msiBuildDir "Product.wixobj"
$appFilesWixObj = Join-Path $msiBuildDir "AppFiles.wixobj"
& $lightExe `
    -sval `
    -out $outputMsi `
    $productWixObj `
    $appFilesWixObj

if ($LASTEXITCODE -ne 0) { throw "Light falhou ao gerar MSI." }

Write-Host "`nMSI gerado com sucesso em:" -ForegroundColor Green
Write-Host "  $outputMsi"

# 4. Assina o instalador MSI gerado
Write-Host "[4/4] Assinando instalador MSI..." -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File (Join-Path $rootDir "tool\sign_windows.ps1")

Write-Host "`nProcesso concluído! O instalador MSI assinado está pronto para distribuição." -ForegroundColor Green
