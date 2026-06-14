# Сборка виджета + запуск симулятора + загрузка. Запуск: правый клик -> "Run with PowerShell"
# или из терминала:  powershell -ExecutionPolicy Bypass -File watch\run-sim.ps1
$ErrorActionPreference = "Stop"
$DEVICE = "instinct3solar45mm"

# JDK: JAVA_HOME или встроенный в Android Studio
$jbr = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { "C:\Program Files\Android\Android Studio\jbr" }
$env:JAVA_HOME = $jbr
$env:Path = "$jbr\bin;" + $env:Path

# последний установленный CIQ SDK
$sdk = (Get-ChildItem "$env:APPDATA\Garmin\ConnectIQ\Sdks" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$w = $PSScriptRoot

Write-Host "Сборка..." -ForegroundColor Cyan
Push-Location $w
& "$sdk\bin\monkeyc.bat" -d $DEVICE -f monkey.jungle -o bin\my_routecast.prg -y developer_key.der
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED" -ForegroundColor Red; Pop-Location; Read-Host "Enter для выхода"; exit 1 }

Write-Host "Запуск симулятора..." -ForegroundColor Cyan
Get-Process -Name simulator -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process -FilePath "$sdk\bin\connectiq.bat"
Start-Sleep 12

Write-Host "Загрузка виджета. START x2 -> навигация, ещё START -> демо-движение." -ForegroundColor Green
& "$sdk\bin\monkeydo.bat" bin\my_routecast.prg $DEVICE
Pop-Location
