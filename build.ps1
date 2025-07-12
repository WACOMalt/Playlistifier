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
              -description "Universal Playlist Converter - Spotify & YouTube to MP3" `
              -company "WACOMalt" `
              -product "Playlistifier" `
              -copyright "Copyright 2025" `
              -version "0.2.0.0"

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build completed successfully!" -ForegroundColor Green
    Write-Host "EXE created at: build\Playlistifier.exe" -ForegroundColor Green
} else {
    Write-Host "Build failed!" -ForegroundColor Red
}
