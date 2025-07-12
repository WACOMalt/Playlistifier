# Build script for Playlistifier
# This script compiles the PowerShell script into a standalone EXE

# Ensure build directory exists
if (-not (Test-Path "build")) {
    New-Item -ItemType Directory -Path "build" -Force
}

# Build the EXE with optimized flags for faster startup
Write-Host "Building Playlistifier.exe..." -ForegroundColor Green
Invoke-ps2exe -inputFile "playlistifier_unified.ps1" `
              -outputFile "build\Playlistifier.exe" `
              -iconFile "Playlistifier.ico" `
              -noConfigFile `
              -requireAdmin:$false `
              -title "Playlistifier" `
              -description "Universal Playlist Converter" `
              -company "Your Company" `
              -product "Playlistifier" `
              -copyright "Copyright 2024" `
              -version "1.0.0.0"

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build completed successfully!" -ForegroundColor Green
    Write-Host "EXE created at: build\Playlistifier.exe" -ForegroundColor Green
} else {
    Write-Host "Build failed!" -ForegroundColor Red
}
