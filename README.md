# Playlistifier v0.2

**Universal Playlist Converter - Music Streaming Services to MP3**

A powerful, user-friendly tool that converts music streaming playlists, albums, and tracks to downloadable MP3 files by finding matching video content. Also supports direct video playlist conversion.

## ✨ Features

- **🎵 Music Streaming Support**: Playlists, albums, and individual tracks
- **📺 Video Platform Support**: Playlist extraction and conversion
- **🔐 Secure Authentication**: PKCE OAuth flow (no secrets required)
- **🎨 Custom Artwork**: Embeds original streaming service artwork and metadata
- **📁 Smart Organization**: Auto-creates organized folders with proper naming
- **⚡ Auto-Dependencies**: Downloads yt-dlp and ffmpeg automatically
- **🛡️ Robust Fallback**: Works from any directory, handles read-only locations
- **🎛️ Interactive Interface**: User-friendly menu system

## 🚀 Quick Start

1. **Download** the latest release
2. **Extract** the ZIP file anywhere on your computer
3. **Run** `Playlistifier.exe`
4. **Paste** your music streaming or video platform playlist URL
5. **Enjoy** your downloaded music!

## 📋 Supported URLs

### Music Streaming Services
- **Playlists**: `https://open.spotify.com/playlist/[playlist_id]`
- **Albums**: `https://open.spotify.com/album/[album_id]`
- **Tracks**: `https://open.spotify.com/track/[track_id]`

### Video Platforms
- **Playlists**: `https://www.youtube.com/playlist?list=[playlist_id]`

## 🔧 How It Works

1. **URL Processing**: Analyzes your playlist URL to determine the source
2. **Authentication**: For streaming services, opens browser for secure OAuth login
3. **Track Discovery**: Searches video platforms for matching songs
4. **Download**: Uses yt-dlp to download high-quality audio
5. **Enhancement**: Embeds custom artwork and metadata using ffmpeg
6. **Organization**: Creates clean, organized folders with proper naming

## 📂 Output Structure

```
📁 Playlist Name/
├── 📄 Songs_Playlist Name.txt (URL list)
├── 🎵 01 - Artist - Song Title.mp3
├── 🎵 02 - Artist - Song Title.mp3
└── ...
```

## ⚙️ Download Options

- **Audio Format**: MP3 (320kbps when available)
- **Video Format**: MP4 (for video platform playlists)
- **Numbering**: Choose numbered filenames or clean titles
- **Artwork**: Automatic embedding of album artwork
- **Metadata**: Full ID3 tags (title, artist, album, track number)

## 💡 Pro Tips

- **Batch Processing**: Process multiple playlists by restarting after each one
- **Directory Fallback**: Works from any location, even read-only drives
- **Explorer Integration**: Press 'E' to open download folder in Windows Explorer
- **Interrupt Safety**: Press 'R' to restart or 'Q' to quit at any time
- **Resume Capability**: Partial downloads are saved if interrupted

## 🛠️ Technical Details

- **Dependencies**: Auto-downloads yt-dlp and ffmpeg as needed
- **Authentication**: Uses PKCE OAuth (no client secrets stored)
- **Compatibility**: Windows 10/11 (x64)
- **Network**: Requires internet connection for downloads
- **Storage**: Varies by playlist size (typically 5-10MB per song)

## 📁 Directory Behavior

- **Writable Directory**: Creates folders in the current location
- **Read-Only Directory**: Automatically falls back to `%USERPROFILE%\Documents\playlistifier`
- **Portable**: Can be run from any location (USB drives, network shares, etc.)

## 🔒 Privacy & Security

- **No Data Collection**: All processing happens locally
- **Secure Authentication**: Uses industry-standard PKCE OAuth
- **No Secrets**: No API keys or sensitive data stored
- **Open Source**: Full source code available on GitHub

## 🐛 Troubleshooting

### Common Issues

**"No tracks found"**
- Check your playlist URL is correct and public
- Verify internet connection
- Try copying the URL from your browser address bar

**"Authentication failed"**
- Ensure you're logged into the streaming service in your browser
- Check that you clicked "Agree" in the authorization page
- Try restarting the application

**"Download failed"**
- Some videos may be region-restricted or private
- Age-restricted content may not be accessible
- Check available disk space

**"Directory not writable"**
- The app will automatically fallback to your Documents folder
- Check antivirus software isn't blocking file creation

## 📊 Performance

- **Small Playlists** (1-20 songs): 1-5 minutes
- **Medium Playlists** (20-100 songs): 5-30 minutes  
- **Large Playlists** (100+ songs): 30+ minutes
- **Processing**: ~2-5 seconds per song (search + download)

## 🔄 Version History

### v0.2 (Current)
- PKCE OAuth implementation for secure streaming service authentication
- Custom artwork embedding from streaming services
- Robust directory fallback system
- Automatic dependency management
- Interactive interface with Explorer integration
- Complete metadata embedding (title, artist, album, track number)

## 🤝 Contributing

Found a bug or have a feature request? Please open an issue on GitHub!

## 📄 License

This project is open source. See the repository for license details.

## ⚠️ Disclaimer

This tool is for personal use only. Please respect copyright laws and terms of service for all streaming platforms and video services. Only download content you have the right to access.

---

**Playlistifier v0.2** - Created by WACOMalt  
🔗 [GitHub Repository](https://github.com/WACOMalt/Playlistifier)
