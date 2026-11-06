$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$wixDir = Join-Path $rootDir "tool\wix314"
$candleExe = Join-Path $wixDir "candle.exe"

if (-not (Test-Path $candleExe)) {
    Write-Host "Baixando WiX Toolset portátil v3.14..." -ForegroundColor Cyan
    $zipPath = Join-Path $rootDir "tool\wix314.zip"
    $url = "https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip"
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    
    Write-Host "Extraindo WiX Toolset..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $wixDir -Force
    Remove-Item $zipPath -Force
    Write-Host "WiX Toolset portátil pronto em: $wixDir" -ForegroundColor Green
} else {
    Write-Host "WiX Toolset portátil já está presente em: $wixDir" -ForegroundColor Green
}
