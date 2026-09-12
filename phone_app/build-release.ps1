<#
.SYNOPSIS
    Builds the release APK with the home server address baked in.

.DESCRIPTION
    The server address is not in source — it is read at build time from
    dart_defines.json, which is gitignored. A plain `flutter build apk` still
    succeeds without it, but produces an app pointed at localhost: saved
    phrases work, and live speech and sync fail on the phone. That is an easy
    mistake to ship to someone who depends on the app, so this script refuses
    to build without the file.
#>
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$defines = Join-Path $PSScriptRoot 'dart_defines.json'
if (-not (Test-Path $defines)) {
    Write-Error "dart_defines.json is missing. Copy dart_defines.example.json to dart_defines.json and set SERVER_URL to the home server's address."
}

$serverUrl = (Get-Content $defines -Raw | ConvertFrom-Json).SERVER_URL
if (-not $serverUrl -or $serverUrl -match 'your-machine') {
    Write-Error "SERVER_URL in dart_defines.json is unset or still the example placeholder."
}

Write-Host "Building release APK against $serverUrl"
flutter build apk --release --dart-define-from-file=dart_defines.json
