# SeedTheNode — iOS App

A SwiftUI iOS app that streams audio from IPFS via a Raspberry Pi 5 backend. The Pi runs an Express.js API + IPFS Kubo daemon; the app talks to it over the local network.

## Quick Verification Commands

```bash
# Test Pi connectivity
ssh -o BatchMode=yes pi@10.0.0.204 "echo connected"

# Test API is running
curl -s http://10.0.0.204:3000/api/health | python3 -m json.tool

# Check services on Pi
ssh -o BatchMode=yes pi@10.0.0.204 "systemctl status seedthenode-api --no-pager"
ssh -o BatchMode=yes pi@10.0.0.204 "systemctl status ipfs --no-pager"

# View API logs
ssh -o BatchMode=yes pi@10.0.0.204 "journalctl -u seedthenode-api -n 50 --no-pager"

# Build iOS app (use xcodebuild, NOT XcodeBuildMCP build_sim — DVTBuildVersion stderr bug)
xcodebuild -project seedTheNode.xcodeproj -scheme seedTheNode -destination 'id=1C995C78-9DAF-4039-A2B8-342ABC54297B' build 2>&1 | tail -5
```

## Pi / Backend

- **Host**: `10.0.0.204` (use IP, not `.local` — more reliable from iOS)
- **SSH**: `ssh pi@10.0.0.204` (key: `~/.ssh/id_ed25519`, passphrase-protected, must be in ssh-agent)
- **Non-interactive SSH**: `ssh -o BatchMode=yes pi@10.0.0.204 "<command>"`
- **API source**: `/home/pi/seedthenode/api/server.js` (lowercase `seedthenode` on disk)
- **Database**: SQLite at `/home/pi/seedthenode/api/seedthenode.db` (WAL mode)
- **Uploads temp dir**: `/home/pi/seedthenode/api/uploads/`

### Systemd Services
| Service | Description | Auto-start |
|---------|-------------|------------|
| `ipfs.service` | IPFS Kubo 0.27.0 daemon | Yes (boot) |
| `seedthenode-api.service` | Express API on port 3000 | Yes (after IPFS) |

Service files: `/etc/systemd/system/`
Restart a service: `ssh pi@10.0.0.204 "sudo systemctl restart seedthenode-api"`

### API Endpoints (port 3000)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/health` | Node status, track count, storage, IPFS peers |
| `GET` | `/api/tracks` | List all tracks (with version_count) |
| `GET` | `/api/tracks/:id` | Single track + versions array |
| `POST` | `/api/tracks` | Create track (`{ title, artistName }`) |
| `DELETE` | `/api/tracks/:id` | Delete track |
| `POST` | `/api/tracks/:id/upload` | Upload audio file (multipart `audio` field, 100MB max) → IPFS pin + version |
| `GET` | `/api/stream/:cid` | Stream audio from IPFS (returns `audio/mp4`, full file, no range support) |
| `GET` | `/api/ipfs/:cid` | Get raw IPFS content as JSON |
| `POST` | `/api/ipfs/pin/:cid` | Pin a CID |

### Database Schema
```sql
tracks (id TEXT PK, title TEXT, artist_name TEXT, ipfs_cid TEXT, created_at TEXT, updated_at TEXT)
versions (id TEXT PK, track_id TEXT FK, version_number INT, audio_cid TEXT, voice_note_cid TEXT, created_at TEXT)
```

## Xcode Project

- **Xcode version**: 26 beta (Swift 6.2)
- **Deployment target**: iOS 26.2
- **Bundle ID**: `neoCortez.seedTheNode`
- **Dev Team**: `F8265QBRGN`
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (strict Swift 6.2 concurrency)
- **Project format**: objectVersion 77 with `PBXFileSystemSynchronizedRootGroup` — new Swift files are auto-discovered, no pbxproj edits needed
- **Info.plist**: at project root (outside `seedTheNode/` source dir) to avoid conflict with `GENERATE_INFOPLIST_FILE`
- **Simulator**: `iPhone 17 Pro` (ID: `1C995C78-9DAF-4039-A2B8-342ABC54297B`) — no iPhone 16 Pro in Xcode 26

### Build Notes
- XcodeBuildMCP's `build_sim` tool reports errors due to DVTBuildVersion on stderr even when builds succeed. Use `xcodebuild` directly via Bash instead.
- SourceKit may show "Cannot find 'AudioPlayer'/'NodeService' in scope" during indexing — these are preview indexing noise, not real build errors. Ignore them.

## Architecture

### Dependency Injection
`@Observable` `NodeService` + `AudioPlayer` injected via `.environment()` in `seedTheNodeApp.swift`. **All SwiftUI previews must provide both** via `.environment(NodeService()).environment(AudioPlayer())`.

### Networking
- ATS exception: `NSAllowsLocalNetworking = true` in Info.plist for HTTP to Pi
- Default hostname: `10.0.0.204` (configurable in Settings tab)

### Audio Playback
- Download-then-play pattern with `AVAudioPlayer` (not `AVPlayer` — Pi API doesn't support HTTP range requests)
- Temp file written with `.m4a` extension (required for AVAudioPlayer codec detection)
- Audio session: `.playback` category, `.duckOthers` option
- `CADisplayLink` at 4–15fps for progress updates (power-efficient)
- `isLooping` — AVAudioPlayerDelegate restarts on finish

### Now Playing (Apple Music-style)
- `tabViewBottomAccessory(isEnabled: player.hasTrack)` — the `isEnabled:` parameter variant is critical; the plain closure version renders an empty Liquid Glass capsule even when there's no track
- `.tabBarMinimizeBehavior(.onScrollDown)` + `@Environment(\.tabViewBottomAccessoryPlacement)` for adaptive layout
- `matchedTransitionSource(id:in:)` + `.fullScreenCover` + `navigationTransition(.zoom)` for Apple Music morph animation between mini and full player
- **DragGesture does NOT work** inside `tabViewBottomAccessory` — system Liquid Glass container intercepts touches
- Apple Music pattern: mini player persists until explicit stop (X button), no dismiss gesture
- Context menu: repeat toggle + stop

### Key Patterns
- `TrackGradient` — deterministic gradient from track ID hash for album art placeholder
- `@Namespace` shared between `NowPlayingAccessory` and `NowPlayingFullScreen`
- 4-tab TabView: Overview, Catalog, Upload, Settings

## Source Files

| File | Purpose |
|------|---------|
| `seedTheNodeApp.swift` | App entry, environment injection of AudioPlayer + NodeService |
| `ContentView.swift` | TabView + NowPlayingAccessory + NowPlayingFullScreen + TrackGradient |
| `AudioPlayer.swift` | `@Observable` playback engine (AVAudioPlayer, download-then-play) |
| `NodeService.swift` | API client (tracks CRUD, upload, node health) |
| `CatalogView.swift` | Track list with play/pause row indicators |
| `OverviewView.swift` | Node status dashboard (storage, IPFS peers, uptime) |
| `UploadView.swift` | File picker (DocumentPicker) + voice recorder (AVAudioRecorder) |
| `SettingsView.swift` | Hostname configuration |
| `Info.plist` | ATS exception + NSMicrophoneUsageDescription |

## Git

- This iOS project has its **own `.git`** (separate from the parent monorepo)
- Remote: `origin` → `https://github.com/desrucPrince/seedTheNode.git`
- Branch: `ios/main` (the parent repo's Pi/API code lives on `main`)
- GitHub auth: `gh` CLI over HTTPS (no SSH needed for GitHub)
- Push: `git push origin main:ios/main`

## User Preferences

- **Name**: Darrion Johnson
- **Output style**: Learning mode — educational insights + interactive code contributions
- **Approach**: Explain trade-offs, request 5-10 line contributions for meaningful decisions

## Current Status

- All views implemented, build succeeds on iPhone 17 Pro simulator
- Apple Music-style now-playing with zoom morph transition (latest feature)
- Audio playback NOT yet confirmed working end-to-end (needs device on same network as Pi)
- IPFS websocket warnings in daemon logs are normal (peer churn)
