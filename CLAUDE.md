# SeedTheNode — Monorepo

Decentralized audio platform: iOS app → Express.js API → IPFS on Raspberry Pi 5.

## Project Layout

```
seedTheNode/
├── api/                    # Express.js API (lives on Pi at /home/pi/seedthenode/api/)
│   └── server.js           # Main server (SQLite + IPFS CLI + multer uploads)
├── iOS/seedTheNode/        # SwiftUI iOS app (has its own .git, branch: ios/main)
│   ├── CLAUDE.md           # ← Detailed iOS project context (read this for iOS work)
│   ├── seedTheNode.xcodeproj
│   ├── seedTheNode/        # Swift source files
│   └── Info.plist
└── CLAUDE.md               # ← You are here
```

## Two Git Histories

| Scope | Location | Remote Branch | Auth |
|-------|----------|---------------|------|
| Parent (Pi/API) | `/seedTheNode/.git` | `main` | `gh` CLI / HTTPS |
| iOS app | `/seedTheNode/iOS/seedTheNode/.git` | `ios/main` | `gh` CLI / HTTPS |

Both push to `github.com/desrucPrince/seedTheNode` on different branches.

## Pi Access

- **Host**: `10.0.0.204` / `seedthenode.local`
- **SSH**: `ssh pi@10.0.0.204` (key: `~/.ssh/id_ed25519`, passphrase-protected)
- **Non-interactive**: `ssh -o BatchMode=yes pi@10.0.0.204 "<cmd>"`
- **API**: `http://10.0.0.204:3000`
- **API source on Pi**: `/home/pi/seedthenode/api/server.js` (lowercase path)
- **Services**: `ipfs.service` + `seedthenode-api.service` (both auto-start)

### Quick Health Check
```bash
curl -s http://10.0.0.204:3000/api/health | python3 -m json.tool
```

## For iOS Work

Start your session from `iOS/seedTheNode/` — the `CLAUDE.md` there has complete Xcode build instructions, API endpoint reference, architecture details, and all the gotchas.

## User
- **Name**: Darrion Johnson
- **Output style**: Learning mode (educational insights + interactive code contributions)
