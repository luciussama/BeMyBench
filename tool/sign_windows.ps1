# Script de automação de assinatura de código no Windows (Code Signing)
# Uso: powershell -ExecutionPolicy Bypass -File tool\sign_windows.ps1

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$certDir = Join-Path $rootDir "certificates"
if (-not (Test-Path $certDir)) {
    New-Item -ItemType Directory -Path $certDir -Force | Out-Null
}

$pfxPath = Join-Path $certDir "bemybench_dev.pfx"
$cerPath = Join-Path $certDir "bemybench_dev.cer"
$pfxPasswordStr = "BMyBenchDev2026!"
$pfxPassword = ConvertTo-SecureString -String $pfxPasswordStr -Force -AsPlainText

# 1. Cria o certificado auto-assinado se não existir
if (-not (Test-Path $pfxPath)) {
    Write-Host "[1/3] Gerando certificado auto-assinado de Code Signing..." -ForegroundColor Cyan
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=BMyBench" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -HashAlgorithm "SHA256" `
        -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears(5)

    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pfxPassword | Out-Null
    Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null
    Write-Host "Certificado gerado com sucesso em:" -ForegroundColor Green
    Write-Host "  PFX: $pfxPath"
    Write-Host "  CER: $cerPath"
} else {
    Write-Host "[1/3] Certificado existente localizado: $pfxPath" -ForegroundColor Cyan
}

# 2. Localiza signtool.exe
$signtool = $null
$signtoolCmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
if ($signtoolCmd) {
    $signtool = $signtoolCmd.Source
} else {
    $signtoolPaths = @(
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\signtool.exe"
    )
    foreach ($p in $signtoolPaths) {
        $found = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $signtool = $found.FullName; break }
    }
}

if (-not $signtool) {
    throw "signtool.exe não encontrado no Windows SDK."
}

Write-Host "[2/3] Utilizando SignTool: $signtool" -ForegroundColor Cyan

# 3. Assina os arquivos
$releaseDir = Join-Path $rootDir "build\windows\x64\runner\Release"
$filesToSign = @(
    (Join-Path $releaseDir "bemybench.exe"),
    (Join-Path $releaseDir "bemybench_core.dll"),
    (Join-Path $releaseDir "flutter_windows.dll")
)

# Adiciona MSIs se existirem
$msiFiles = Get-ChildItem -Path $releaseDir -Filter "*.msi" -ErrorAction SilentlyContinue
foreach ($m in $msiFiles) {
    $filesToSign += $m.FullName
}

Write-Host "[3/3] Assinando binários..." -ForegroundColor Cyan
foreach ($f in $filesToSign) {
    if (Test-Path $f) {
        Write-Host "  -> Assinando: $(Split-Path -Leaf $f)..." -NoNewline
        & $signtool sign `
            /f $pfxPath `
            /p $pfxPasswordStr `
            /fd SHA256 `
            /tr http://timestamp.digicert.com `
            /td SHA256 `
            $f | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host " [OK]" -ForegroundColor Green
        } else {
            # Se o servidor de timestamp falhar, tenta sem timestamp
            & $signtool sign /f $pfxPath /p $pfxPasswordStr /fd SHA256 $f | Out-Null
            Write-Host " [OK (sem timestamp)]" -ForegroundColor Yellow
        }
    }
}

Write-Host "`nAssinatura concluída com sucesso!" -ForegroundColor Green
