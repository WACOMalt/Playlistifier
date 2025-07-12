param(
    [Parameter(Position=0, Mandatory=$false)]
    [string]$PlaylistUrl
)

# Get the directory where the exe is located
# For PS2EXE compiled executables, use process path
try {
    # Get the actual executable path from the current process
    $exePath = (Get-Process -Id $PID).Path
    if ($exePath -and (Test-Path $exePath)) {
        $exeDir = Split-Path $exePath -Parent
    } else {
        throw "Process path not found"
    }
} catch {
    try {
        # Fallback: use assembly location
        $assemblyLocation = [System.Reflection.Assembly]::GetExecutingAssembly().Location
        if ($assemblyLocation -and (Test-Path $assemblyLocation)) {
            $exeDir = Split-Path $assemblyLocation -Parent
        } else {
            throw "Assembly location not found"
        }
    } catch {
        # Final fallback to working directory (this is what we want to avoid)
        $exeDir = Get-Location
        Write-Host "Warning: Could not determine exe location, using current directory" -ForegroundColor Yellow
    }
}

# Test if exe directory is writable, fallback to current directory if not
function Test-DirectoryWritable {
    param($Path)
    try {
        $testFile = Join-Path $Path "write_test_$(Get-Random).tmp"
        $null = New-Item -Path $testFile -ItemType File -Force
        Remove-Item -Path $testFile -Force
        return $true
    } catch {
        return $false
    }
}

# Dependencies (yt-dlp.exe, config.json) should be next to the EXE
# Output files (playlist txt, download folders) should be in current working directory
if (-not (Test-DirectoryWritable $exeDir)) {
    Write-Host "Exe directory is not writable, using current directory for dependencies" -ForegroundColor Yellow
    $dependencyDir = Get-Location
} else {
    $dependencyDir = $exeDir
}

# Always use current working directory for output files
$outputDir = Get-Location

# Initialize persistent variables outside main loop
$outputFile = $null
$playlistSource = $null
$playlistProcessed = $false

# Main execution loop
do {
    $restart = $false
    $global:shouldRestart = $false

    # Check if URL parameter is provided and playlist not already processed
    if ([string]::IsNullOrWhiteSpace($PlaylistUrl) -and -not $playlistProcessed) {
        Write-Host "`nUniversal Playlist Converter" -ForegroundColor DarkMagenta
        Write-Host "===========================" -ForegroundColor DarkMagenta
        Write-Host "`nSupported formats:" -ForegroundColor DarkMagenta
        Write-Host "  • Spotify: https://open.spotify.com/playlist/..." -ForegroundColor Green
        Write-Host "  • YouTube: https://www.youtube.com/playlist?list=..." -ForegroundColor Green
        Write-Host "`nPlease enter a playlist URL:" -ForegroundColor DarkMagenta
        Write-Host "URL: " -NoNewline -ForegroundColor White
        
        # Use Console.ReadLine() which works better with PS2EXE than Read-Host
        $PlaylistUrl = [Console]::ReadLine()
        
        if ([string]::IsNullOrWhiteSpace($PlaylistUrl)) {
            Write-Host "`nNo URL entered." -ForegroundColor Red
            # This will fall through to the restart prompt
        }
    }

# Load configuration from file
function Load-Configuration {
    param($ExeDirectory)
    $configPath = Join-Path $ExeDirectory "config.json"
    
    if (-not (Test-Path $configPath)) {
        Write-Host "Configuration file not found. Creating blank config.json..." -ForegroundColor Cyan
        
        # Create blank config file
        $blankConfig = @"
{
  "spotify": {
    "client_id": "",
    "client_secret": ""
  },
  "youtube": {
    "api_key": ""
  }
}
"@
        
        try {
            $blankConfig | Out-File -FilePath $configPath -Encoding UTF8
            Write-Host "Created blank config.json. You can optionally add a YouTube API key for faster search." -ForegroundColor Green
        }
        catch {
            Write-Host "Could not create config file: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        # Return default config
        return @{
            spotify = @{
                client_id = ""
                client_secret = ""
            }
            youtube = @{
                api_key = ""
            }
        }
    }
    
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        
        # Validate required fields
        if (-not $config.spotify -or -not $config.youtube) {
            Write-Host "Invalid configuration file format." -ForegroundColor Red
            return $null
        }
        
        return $config
    }
    catch {
        Write-Host "Error reading configuration file: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Load API credentials from configuration (completely optional)
$config = Load-Configuration -ExeDirectory $dependencyDir
if (-not $config) {
    Write-Host "Error loading configuration. Using default settings: Spotify OAuth + yt-dlp fallback." -ForegroundColor Yellow
    $config = @{
        spotify = @{
            client_id = ""
            client_secret = ""
        }
        youtube = @{
            api_key = ""
        }
    }
}

# Hardcoded API credentials for OAuth (no user config needed)
$SPOTIFY_CLIENT_ID = "98780a86674b4edfa5eb772dedbcf8ae"
$SPOTIFY_CLIENT_SECRET = "af2f1a86d4e84197a424560c11f6ebf1"

$YOUTUBE_API_KEY = $config.youtube.api_key

# Validate API keys and set flags for which APIs to use
$useSpotifyAPI = $SPOTIFY_CLIENT_ID -and $SPOTIFY_CLIENT_ID -ne "your_spotify_client_id_here"

$useYouTubeAPI = $YOUTUBE_API_KEY -and $YOUTUBE_API_KEY -ne "your_youtube_api_key_here"

if (-not $useSpotifyAPI) {
    Write-Host "Spotify Client ID not configured - Spotify playlists will not work" -ForegroundColor Cyan
}

if (-not $useYouTubeAPI) {
    Write-Host "YouTube API key not configured - will use yt-dlp fallback (recommended for most users)" -ForegroundColor Cyan
}

# Function to download yt-dlp if not present
function Ensure-YtDlp {
    param($ExeDirectory)
    $ytDlpPath = Join-Path $ExeDirectory "yt-dlp.exe"
    
    if (-not (Test-Path $ytDlpPath)) {
        Write-Host "yt-dlp.exe not found. Downloading..." -ForegroundColor Cyan
        
        try {
            # Download yt-dlp from GitHub releases
            $downloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
            Write-Host "Downloading yt-dlp from: $downloadUrl" -ForegroundColor Gray
            
            # Use WebClient for compatibility with PS2EXE
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($downloadUrl, $ytDlpPath)
            
            if (Test-Path $ytDlpPath) {
                Write-Host "yt-dlp.exe downloaded successfully!" -ForegroundColor Green
            } else {
                throw "Download completed but file not found"
            }
        }
        catch {
            Write-Host "Failed to download yt-dlp: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Note: Some features may not work without yt-dlp fallback" -ForegroundColor Cyan
            return $false
        }
    } else {
        Write-Host "yt-dlp.exe found" -ForegroundColor Green
    }
    
    return $true
}

    # Only process if URL is provided and playlist hasn't been processed yet
    if (-not [string]::IsNullOrWhiteSpace($PlaylistUrl) -and -not $playlistProcessed) {
        Write-Host "`nUniversal Playlist Converter (Standalone)" -ForegroundColor DarkMagenta
        Write-Host "=========================================" -ForegroundColor DarkMagenta
        Write-Host "URL: $PlaylistUrl`n"

        # Load required assemblies when actually needed
        Add-Type -AssemblyName System.Web
        Add-Type -AssemblyName System.Net.Http

        # Ensure yt-dlp is available
        $ytDlpAvailable = Ensure-YtDlp -ExeDirectory $dependencyDir

# Function to download songs from playlist file
function Start-DownloadSongs {
    param($OutputFile, $PlaylistSource, $OutputDir)
    
    $ytDlpPath = Join-Path $dependencyDir "yt-dlp.exe"
    
    if (-not (Test-Path $ytDlpPath)) {
        Write-Host "`nyt-dlp.exe not found. Cannot download songs." -ForegroundColor Red
        return
    }
    
    if (-not (Test-Path $OutputFile)) {
        Write-Host "`nPlaylist file not found: $OutputFile" -ForegroundColor Red
        return
    }
    
    # Determine download format based on playlist source
    $downloadAsAudio = $true
    $formatDescription = "MP3 audio"
    
    if ($PlaylistSource -eq "YouTube") {
        Write-Host "`nDownload Format:" -ForegroundColor Yellow
        Write-Host "  A - Audio only (MP3 format)" -ForegroundColor White
        Write-Host "  V - Video files (highest quality, MP4 format)" -ForegroundColor White
        Write-Host "`nChoose format: " -NoNewline -ForegroundColor Yellow
        
        $formatKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Write-Host $formatKey.Character
        
        if ($formatKey.Character -eq 'v' -or $formatKey.Character -eq 'V') {
            $downloadAsAudio = $false
            $formatDescription = "video files (MP4)"
        } else {
            $formatDescription = "MP3 audio"
        }
    }
    
    # Ask about numbered filenames for all playlist types
    Write-Host "`nFilename Options:" -ForegroundColor Yellow
    Write-Host "  Y - Add track numbers (001 - Song Title.ext)" -ForegroundColor White
    Write-Host "  N - No track numbers (Song Title.ext)" -ForegroundColor White
    Write-Host "`nNumber files? " -NoNewline -ForegroundColor Yellow
    
    $numberKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host $numberKey.Character
    
    $useTrackNumbers = ($numberKey.Character -eq 'y' -or $numberKey.Character -eq 'Y')
    
    Write-Host "`nStarting download as $formatDescription..." -ForegroundColor Cyan
    Write-Host "This may take a very long time depending on playlist size!" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to cancel at any time.`n" -ForegroundColor Yellow
    
    # Read URLs from the playlist file
    $urls = @()
    $content = Get-Content $OutputFile -Encoding UTF8
    foreach ($line in $content) {
        if ($line -match "^https://www\.youtube\.com/watch\?v=") {
            $urls += $line.Trim()
        }
    }
    
    if ($urls.Count -eq 0) {
        Write-Host "No YouTube URLs found in playlist file." -ForegroundColor Red
        return
    }
    
    Write-Host "Found $($urls.Count) songs to download`n" -ForegroundColor Green
    
    # Extract playlist name from the output file
    $playlistName = "Downloads" # Default fallback
    foreach ($line in $content) {
        if ($line -match "^# Playlist: (.+)$") {
            $playlistName = $matches[1].Trim()
            # Clean the name for use as a folder name
            $playlistName = $playlistName -replace '[\u003c\u003e:"/\\|?*]', '_'
            break
        }
    }
    
    # Use the existing playlist directory (should already exist from URL parsing)
    $downloadDir = Join-Path $OutputDir $playlistName
    if (-not (Test-Path $downloadDir)) {
        New-Item -Path $downloadDir -ItemType Directory | Out-Null
        Write-Host "Created directory: $downloadDir" -ForegroundColor Green
    } else {
        Write-Host "Using existing directory: $downloadDir" -ForegroundColor Green
    }
    
    $downloaded = 0
    $failed = 0
    
    # Calculate padding for track numbers
    $totalTracks = $urls.Count
    $padding = $totalTracks.ToString().Length
    
    for ($i = 0; $i -lt $urls.Count; $i++) {
        $url = $urls[$i]
        $progress = [math]::Round((($i + 1) / $urls.Count) * 100, 0)
        
        Write-Host "[$($i + 1)/$($urls.Count)] ($progress%) Downloading: $url"
        
        try {
            if ($useTrackNumbers) {
                $trackNumber = ($i + 1).ToString().PadLeft($padding, '0')
                $outputTemplate = "$downloadDir/$trackNumber - %(title)s.%(ext)s"
                $successMessage = "Downloaded successfully as track $trackNumber"
            } else {
                $outputTemplate = "$downloadDir/%(title)s.%(ext)s"
                $successMessage = "Downloaded successfully"
            }
            
            if ($downloadAsAudio) {
                # Download as audio format preference
                $result = & $ytDlpPath --extract-audio --audio-format mp3 --audio-quality 0 -o $outputTemplate $url 2>&1
            } else {
                # Download as video with highest quality
                $result = & $ytDlpPath -f "bestvideo+bestaudio/best" --merge-output-format mp4 -o $outputTemplate $url 2>&1
            }
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   ✓ $successMessage" -ForegroundColor Green
                $downloaded++
            } else {
                Write-Host "   ✗ Download failed" -ForegroundColor Red
                $failed++
            }
        }
        catch {
            Write-Host "   ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }
    
    Write-Host "`nDownload completed!" -ForegroundColor Green
    Write-Host "Successfully downloaded: $downloaded/$($urls.Count) songs" -ForegroundColor Green
    Write-Host "Failed downloads: $failed/$($urls.Count) songs" -ForegroundColor Red
    Write-Host "Downloaded files are in the '$downloadDir' folder." -ForegroundColor Cyan
}

# Function to get Spotify access token via OAuth
function Get-SpotifyAccessTokenOAuth {
    param($ClientId, $ClientSecret, $RedirectUri)
    
    Write-Host "Starting OAuth authentication..." -ForegroundColor Cyan
    
    # Start local HTTP listener
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("$RedirectUri/")
    
    try {
        $listener.Start()
        Write-Host "Local server started on $RedirectUri" -ForegroundColor Green
    }
    catch {
        Write-Host "Error starting local server: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    
    # Construct the authorization URL with required scopes
    $scopes = "playlist-modify-public playlist-modify-private user-read-private"
    $encodedScopes = [System.Web.HttpUtility]::UrlEncode($scopes)
    $encodedRedirectUri = [System.Web.HttpUtility]::UrlEncode($RedirectUri)
    $authUrl = "https://accounts.spotify.com/authorize?response_type=code&client_id=$ClientId&redirect_uri=$encodedRedirectUri&scope=$encodedScopes"
    
    Write-Host "Opening browser for Spotify authorization..." -ForegroundColor Cyan
    Write-Host "If browser doesn't open, go to: $authUrl" -ForegroundColor Yellow
    
    # Open the browser for user to authorize
    try {
        Start-Process $authUrl
    }
    catch {
        Write-Host "Could not open browser automatically. Please visit the URL above." -ForegroundColor Yellow
    }
    
    Write-Host "Waiting for authorization..." -ForegroundColor Cyan
    
    # Wait for user authorization with timeout
    $context = $null
    
    try {
        # Use synchronous method which is more reliable
        Write-Host "Waiting for you to complete authorization in the browser..." -ForegroundColor Yellow
        $context = $listener.GetContext()
        Write-Host "Authorization callback received!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error waiting for authorization: $($_.Exception.Message)" -ForegroundColor Red
        $listener.Stop()
        return $null
    }
    
    if (-not $context) {
        Write-Host "Timeout waiting for authorization" -ForegroundColor Red
        $listener.Stop()
        return $null
    }
    
    # Extract authorization code
    $code = $context.Request.QueryString["code"]
    $error = $context.Request.QueryString["error"]
    
    Write-Host "Processing authorization response..." -ForegroundColor Cyan
    Write-Host "Code received: $($code -ne $null)" -ForegroundColor Gray
    Write-Host "Error received: $error" -ForegroundColor Gray
    
    # Respond to HTTP request
    $response = $context.Response
    $responseText = if ($error) {
        "<html><body><h2>Authorization Failed</h2><p>Error: $error</p><p>You can close this tab.</p></body></html>"
    } else {
        "<html><body><h2>Authorization Successful!</h2><p>You can close this tab and return to the application.</p></body></html>"
    }
    
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseText)
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
    $listener.Stop()
    
    if ($error) {
        Write-Host "Authorization failed: $error" -ForegroundColor Red
        return $null
    }
    
    if (-not $code) {
        Write-Host "No authorization code received" -ForegroundColor Red
        return $null
    }
    
    Write-Host "Authorization code received, exchanging for access token..." -ForegroundColor Cyan
    
    # Exchange the authorization code for an access token
    $tokenUri = "https://accounts.spotify.com/api/token"
    $tokenBody = @{
        code = $code
        redirect_uri = $RedirectUri
        grant_type = "authorization_code"
        client_id = $ClientId
        client_secret = $ClientSecret
    }
    
    try {
        $tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method Post -Body $tokenBody
        Write-Host "Access token obtained successfully!" -ForegroundColor Green
        return $tokenResponse.access_token
    }
    catch {
        Write-Host "Error exchanging code for token: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}


# Function to get Spotify playlist info
function Get-SpotifyPlaylistInfo {
    param($PlaylistId, $AccessToken)
    
    $headers = @{ 'Authorization' = "Bearer $AccessToken" }
    
    try {
        $response = Invoke-RestMethod -Uri "https://api.spotify.com/v1/playlists/$PlaylistId" -Headers $headers
        return @{
            Name = $response.name
            TrackCount = $response.tracks.total
        }
    }
    catch {
        Write-Host "Error getting playlist info: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to get Spotify playlist tracks
function Get-SpotifyTracks {
    param($PlaylistId, $AccessToken)
    
    $headers = @{ 'Authorization' = "Bearer $AccessToken" }
    $tracks = @()
    $offset = 0
    $limit = 50
    
    do {
        try {
            $response = Invoke-RestMethod -Uri "https://api.spotify.com/v1/playlists/$PlaylistId/tracks?offset=$offset&limit=$limit" -Headers $headers
            foreach ($item in $response.items) {
                if ($item.track -and $item.track.type -eq 'track') {
                    $artistNames = ($item.track.artists | ForEach-Object { $_.name }) -join ', '
                    $tracks += @{
                        Name = $item.track.name
                        Artists = $artistNames
                    }
                }
            }
            $offset += $limit
        }
        catch {
            Write-Host "Error getting tracks: $($_.Exception.Message)" -ForegroundColor Red
            break
        }
    } while ($response.next)
    
    return $tracks
}

# Function to search YouTube using API
function Search-YouTubeAPI {
    param($Query, $ApiKey)
    
    try {
        $encodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)
        $url = "https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&q=$encodedQuery&key=$ApiKey&maxResults=1"
        $response = Invoke-RestMethod -Uri $url
        
        if ($response.items -and $response.items.Count -gt 0) {
            $videoId = $response.items[0].id.videoId
            return "https://www.youtube.com/watch?v=$videoId"
        }
        return $null
    }
    catch {
        if ($_.Exception.Message -like "*quotaExceeded*" -or $_.Exception.Message -like "*403*") {
            return "QUOTA_EXCEEDED"
        }
        return $null
    }
}


# Function to search YouTube using yt-dlp fallback
function Search-YouTubeFallback {
    param($Query)
    
    $ytDlpPath = Join-Path $dependencyDir "yt-dlp.exe"

    if (-not (Test-Path $ytDlpPath)) {
        Write-Host "   yt-dlp.exe not available for fallback" -ForegroundColor Red
        return $null
    }
    
    try {
        $escapedQuery = $Query -replace '"', '\"'
        $result = & $ytDlpPath --no-download --get-id --default-search "ytsearch1:" "`"$escapedQuery`"" 2>$null
        if ($result -and $result.Trim() -ne "") {
            return "https://www.youtube.com/watch?v=$($result.Trim())"
        }
        return $null
    }
    catch {
        return $null
    }
}

# Function to get YouTube playlist info
function Get-YouTubePlaylistInfo {
    param($PlaylistId, $ApiKey)
    
    try {
        $url = "https://www.googleapis.com/youtube/v3/playlists?part=snippet&id=$PlaylistId&key=$ApiKey"
        $response = Invoke-RestMethod -Uri $url
        
        if ($response.items -and $response.items.Count -gt 0) {
            return @{
                Name = $response.items[0].snippet.title
            }
        }
        return $null
    }
    catch {
        return $null
    }
}

# Function to get YouTube playlist videos
function Get-YouTubePlaylistVideos {
    param($PlaylistId, $ApiKey)
    
    $videos = @()
    $nextPageToken = $null
    
    do {
        try {
            $url = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=$PlaylistId&key=$ApiKey&maxResults=50"
            if ($nextPageToken) {
                $url += "&pageToken=$nextPageToken"
            }
            
            $response = Invoke-RestMethod -Uri $url
            
            foreach ($item in $response.items) {
                if ($item.snippet.resourceId.videoId) {
                    $videos += "https://www.youtube.com/watch?v=$($item.snippet.resourceId.videoId)"
                }
            }
            
            $nextPageToken = $response.nextPageToken
        }
        catch {
            if ($_.Exception.Message -like "*quotaExceeded*" -or $_.Exception.Message -like "*403*") {
                return "QUOTA_EXCEEDED"
            }
            Write-Host "Error getting playlist videos: $($_.Exception.Message)" -ForegroundColor Red
            break
        }
    } while ($nextPageToken)
    
    return $videos
}

# Function to get YouTube playlist videos using yt-dlp fallback
function Get-YouTubePlaylistVideosFallback {
    param($PlaylistUrl)
    
    $ytDlpPath = Join-Path $dependencyDir "yt-dlp.exe"
    
    if (-not (Test-Path $ytDlpPath)) {
        Write-Host "yt-dlp.exe not available for fallback" -ForegroundColor Red
        return @()
    }
    
    try {
        Write-Host "Using yt-dlp to extract playlist..." -ForegroundColor Cyan
        $result = & $ytDlpPath --no-download --get-url --flat-playlist $PlaylistUrl 2>$null
        if ($result) {
            return $result | Where-Object { $_ -and $_.Trim() -ne "" }
        }
        return @()
    }
    catch {
        Write-Host "Error using yt-dlp fallback: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

        # Detect playlist type
        if ($PlaylistUrl -match "spotify\.com") {
            Write-Host "Detected: Spotify Playlist" -ForegroundColor Green
            $playlistSource = "Spotify"
            
            if (-not $useSpotifyAPI) {
                Write-Host "Error: Spotify API keys not configured." -ForegroundColor Red
                Write-Host "Please update config.json with valid Spotify API credentials." -ForegroundColor Yellow
                return
            }
            
            Write-Host "Converting Spotify playlist to YouTube URLs...`n"

            # Extract playlist ID
            if ($PlaylistUrl -match "playlist/([a-zA-Z0-9]+)") {
                $playlistId = $matches[1]
            } else {
                Write-Host "Error: Could not extract Spotify playlist ID from URL" -ForegroundColor Red
                exit 1
            }
            
            Write-Host "Spotify API to YouTube Converter"
            Write-Host "================================="
            Write-Host "Playlist ID: $playlistId"
            
            # Get access token via OAuth
            Write-Host "Getting Spotify access token via OAuth..."
            $redirectUri = "http://127.0.0.1:8888/callback"
            $accessToken = Get-SpotifyAccessTokenOAuth -ClientId $SPOTIFY_CLIENT_ID -ClientSecret $SPOTIFY_CLIENT_SECRET -RedirectUri $redirectUri
            if (-not $accessToken) {
                Write-Host "Failed to get access token. Exiting." -ForegroundColor Red
                exit 1
            }
            
            # Get playlist info
            Write-Host "Fetching playlist info..."
            $playlistInfo = Get-SpotifyPlaylistInfo -PlaylistId $playlistId -AccessToken $accessToken
            if (-not $playlistInfo) {
                Write-Host "Failed to get playlist info. Using playlist ID as name." -ForegroundColor Cyan
                $playlistName = $playlistId
                $trackCount = "Unknown"
            } else {
                $playlistName = $playlistInfo.Name
                $trackCount = $playlistInfo.TrackCount
                Write-Host "Playlist: $playlistName" -ForegroundColor Green
            }
            
            # Get tracks
            Write-Host "Fetching playlist tracks..."
            $tracks = Get-SpotifyTracks -PlaylistId $playlistId -AccessToken $accessToken
            if ($tracks.Count -eq 0) {
                Write-Host "No tracks found in playlist. Exiting." -ForegroundColor Red
                exit 1
            }
            Write-Host "Found $($tracks.Count) tracks" -ForegroundColor Green
            
            # Create playlist folder immediately
            $cleanPlaylistName = $playlistName -replace '[\u003c\u003e:"/\\|?*]', '_'
            $playlistFolder = Join-Path $outputDir $cleanPlaylistName
            if (-not (Test-Path $playlistFolder)) {
                New-Item -Path $playlistFolder -ItemType Directory | Out-Null
                Write-Host "Created directory: $playlistFolder" -ForegroundColor Green
            } else {
                Write-Host "Using existing directory: $playlistFolder" -ForegroundColor Green
            }
            
            # Prepare output file (inside playlist folder)
            $outputFile = Join-Path $playlistFolder "Songs_$cleanPlaylistName.txt"
            
            # Write initial header
            $header = @"
# Playlist: $playlistName
# Total tracks: $($tracks.Count)
# Generated: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')

"@
            $header | Set-Content -Path $outputFile -Encoding UTF8
            
            Write-Host "`nSearching YouTube for each track..."
            Write-Host "This may take a while..."
            Write-Host "Note: File is updated after each successful find, so you can cancel anytime!" -ForegroundColor Cyan
            Write-Host "Press 'R' at any time to restart or 'Q' to quit`n"
            
            $found = 0
            $failed = 0
            $quotaExceeded = $false
            $fallbackNotified = $false
            
            # Pre-check: If YouTube API is not configured, show notification once
            if (-not $useYouTubeAPI) {
                Write-Host "Note: Using yt-dlp fallback for all searches (YouTube API not configured)" -ForegroundColor Cyan
                $fallbackNotified = $true
            }
            
            for ($i = 0; $i -lt $tracks.Count; $i++) {
                # Check for interrupt keys
                if ($Host.UI.RawUI.KeyAvailable) {
                    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    if ($key.Character -eq 'r' -or $key.Character -eq 'R') {
                        Write-Host "`n`nRestart requested! Returning to main menu..." -ForegroundColor Yellow
                        $global:shouldRestart = $true
                        return
                    }
                    if ($key.Character -eq 'q' -or $key.Character -eq 'Q') {
                        Write-Host "`n`nQuitting..." -ForegroundColor Yellow
                        exit 0
                    }
                }
                
                $track = $tracks[$i]
                $query = "$($track.Name) - $($track.Artists)"
                $progress = [math]::Round((($i + 1) / $tracks.Count) * 100, 0)
                
                Write-Host "[$($i + 1)/$($tracks.Count)] ($progress%) Searching: $query"
                
                $videoUrl = $null
                
                if (-not $quotaExceeded -and $useYouTubeAPI) {
                    $videoUrl = Search-YouTubeAPI -Query $query -ApiKey $YOUTUBE_API_KEY
                    if ($videoUrl -eq "QUOTA_EXCEEDED") {
                        $quotaExceeded = $true
                        $videoUrl = $null
                        if (-not $fallbackNotified) {
                            Write-Host "   YouTube API quota exceeded. Switching to yt-dlp fallback for remaining searches..." -ForegroundColor Cyan
                            $fallbackNotified = $true
                        }
                    }
                }
                
                if (-not $videoUrl) {
                    $videoUrl = Search-YouTubeFallback -Query $query
                    if ($videoUrl) {
                        Write-Host "   Found (yt-dlp): $videoUrl" -ForegroundColor Green
                    }
                } else {
                    Write-Host "   Found (API): $videoUrl" -ForegroundColor Green
                }
                
                if ($videoUrl) {
                    "$videoUrl" | Add-Content -Path $outputFile -Encoding UTF8
                    $found++
                } else {
                    Write-Host "   Not found" -ForegroundColor Red
                    $failed++
                }
            }
            
            # Add final summary
            $summary = @"

# Final Summary:
# Successfully found: $found/$($tracks.Count) tracks
# Failed to find: $failed/$($tracks.Count) tracks
# Completed: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
"@
            $summary | Add-Content -Path $outputFile -Encoding UTF8

            Write-Host "`nConversion completed!" -ForegroundColor Green
            Write-Host "Results saved to: $outputFile" -ForegroundColor Green
            Write-Host "Success: $found/$($tracks.Count) tracks" -ForegroundColor Green
            Write-Host "Failed: $failed/$($tracks.Count) tracks" -ForegroundColor Red

            # Mark playlist as processed
            $playlistProcessed = $true

        } elseif ($PlaylistUrl -match "youtube\.com.*[?&]list=([^ -]+)" -or $PlaylistUrl -match "youtu\.be.*[?&]list=([^ -]+)") {
            Write-Host "Detected: YouTube Playlist" -ForegroundColor Green
            $playlistSource = "YouTube"
            Write-Host "Extracting YouTube playlist URLs...`n"

            # Extract playlist ID
            if ($PlaylistUrl -match "[?&]list=([^ -]+)") {
                $playlistId = $matches[1]
            } else {
                Write-Host "Error: Could not extract YouTube playlist ID from URL" -ForegroundColor Red
                exit 1
            }

            Write-Host "YouTube Playlist Extractor"
            Write-Host "=========================="
            Write-Host "Playlist ID: $playlistId"

            # Get playlist info
            Write-Host "Fetching playlist info..."
            $playlistInfo = $null
            $playlistName = $playlistId

            if ($useYouTubeAPI) {
                $playlistInfo = Get-YouTubePlaylistInfo -PlaylistId $playlistId -ApiKey $YOUTUBE_API_KEY
                if ($playlistInfo) {
                    $playlistName = $playlistInfo.Name
                    Write-Host "Playlist: $playlistName" -ForegroundColor Green
                } else {
                    Write-Host "Failed to get playlist info using API. Using playlist ID as name." -ForegroundColor Cyan
                }
            } else {
                Write-Host "YouTube API not configured, using yt-dlp for all operations" -ForegroundColor Cyan
            }

            # Get videos
            Write-Host "Fetching playlist videos..."
            $videos = $null

            if ($useYouTubeAPI) {
                $videos = Get-YouTubePlaylistVideos -PlaylistId $playlistId -ApiKey $YOUTUBE_API_KEY
            }

            if (-not $useYouTubeAPI -or $videos -eq "QUOTA_EXCEEDED" -or -not $videos) {
                if ($videos -eq "QUOTA_EXCEEDED") {
                    Write-Host "API quota exceeded, using yt-dlp fallback..." -ForegroundColor Cyan
                } elseif (-not $useYouTubeAPI) {
                    Write-Host "Using yt-dlp to extract playlist..." -ForegroundColor Cyan
                }
                $videos = Get-YouTubePlaylistVideosFallback -PlaylistUrl $PlaylistUrl
                
                # Try to get playlist name from yt-dlp if API failed
                $ytDlpPath = Join-Path $dependencyDir "yt-dlp.exe"
                if ($playlistName -eq $playlistId -and (Test-Path $ytDlpPath)) {
                    try {
                        # Use --print to get playlist title directly
                        $playlistTitle = & $ytDlpPath --no-download --print "%(playlist_title)s" --playlist-items 1 $PlaylistUrl 2>$null | Select-Object -First 1
                        if ($playlistTitle -and $playlistTitle.Trim() -ne "NA" -and $playlistTitle.Trim() -ne "") {
                            $playlistName = $playlistTitle.Trim()
                            Write-Host "Got playlist name from yt-dlp: $playlistName" -ForegroundColor Green
                        }
                    } catch {
                        # Keep using playlist ID as name
                    }
                }
            }
            
            if ($videos.Count -eq 0) {
                Write-Host "No videos found in playlist. Exiting." -ForegroundColor Red
                exit 1
            }
            
            Write-Host "Found $($videos.Count) videos" -ForegroundColor Green
            
            # Create playlist folder immediately
            $cleanPlaylistName = $playlistName -replace '[\u003c\u003e:"/\\|?*]', '_'
            $playlistFolder = Join-Path $outputDir $cleanPlaylistName
            if (-not (Test-Path $playlistFolder)) {
                New-Item -Path $playlistFolder -ItemType Directory | Out-Null
                Write-Host "Created directory: $playlistFolder" -ForegroundColor Green
            } else {
                Write-Host "Using existing directory: $playlistFolder" -ForegroundColor Green
            }
            
            # Prepare output file (inside playlist folder)
            $outputFile = Join-Path $playlistFolder "Songs_$cleanPlaylistName.txt"
            
            # Write results
            $content = @"
# Playlist: $playlistName
# Total videos: $($videos.Count)
# Generated: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')

"@
            
            for ($i = 0; $i -lt $videos.Count; $i++) {
                $content += "$($videos[$i])`r`n"
            }
            
            $content += @"

# Final Summary:
# Successfully extracted: $($videos.Count) videos
# Completed: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
"@
            
            $content | Set-Content -Path $outputFile -Encoding UTF8
            
            Write-Host "`nExtraction completed!" -ForegroundColor Green
            Write-Host "Results saved to: $outputFile" -ForegroundColor Green
            Write-Host "Videos extracted: $($videos.Count)" -ForegroundColor Green
            
            # Mark playlist as processed
            $playlistProcessed = $true

        } else {
            Write-Host "Error: Unsupported URL format" -ForegroundColor Red
            Write-Host "Supported formats:" -ForegroundColor Yellow
            Write-Host "  - Spotify: https://open.spotify.com/playlist/..." -ForegroundColor Yellow
            Write-Host "  - YouTube: https://www.youtube.com/playlist?list=..." -ForegroundColor Yellow
        }
    }

    # Check if restart was requested during processing
    if ($global:shouldRestart) {
        $restart = $true
        $PlaylistUrl = $null  # Clear the URL so it prompts again
        $playlistProcessed = $false
        Write-Host "`n" # Add some space before restart
    } elseif ($playlistProcessed -and -not [string]::IsNullOrWhiteSpace($PlaylistUrl)) {
        # Show options menu after playlist processing
        Write-Host "`nOptions:" -ForegroundColor Yellow
        Write-Host "  1 - Restart with a new playlist" -ForegroundColor White
        Write-Host "  D - Download all found songs using yt-dlp" -ForegroundColor White
        Write-Host "  Any other key - Exit" -ForegroundColor White
        Write-Host "`nChoose an option: " -NoNewline -ForegroundColor Yellow
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Write-Host $key.Character
        
        if ($key.Character -eq '1') {
            $restart = $true
            $PlaylistUrl = $null  # Clear the URL so it prompts again
            $playlistProcessed = $false
            Write-Host "`n" # Add some space before restart
        } elseif ($key.Character -eq 'd' -or $key.Character -eq 'D') {
            if ($outputFile -and (Test-Path $outputFile)) {
                Start-DownloadSongs -OutputFile $outputFile -PlaylistSource $playlistSource -OutputDir $outputDir
                # After download, show the options menu again without re-processing
                $restart = $true
            } else {
                Write-Host "`nNo playlist file found to download from." -ForegroundColor Red
                $restart = $true
            }
        }
    }

} while ($restart)
