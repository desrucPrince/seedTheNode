const express = require('express');
const Database = require('better-sqlite3');
const { execFileSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const multer = require('multer');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// ---------------------------------------------------------------------------
// Database Setup
// ---------------------------------------------------------------------------

const db = new Database(path.join(__dirname, 'seedthenode.db'));
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS tracks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    ipfs_cid TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS versions (
    id TEXT PRIMARY KEY,
    track_id TEXT NOT NULL,
    version_number INTEGER NOT NULL,
    audio_cid TEXT NOT NULL,
    voice_note_cid TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
  );
`);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function uuid() {
  return crypto.randomUUID();
}

function getStorageInfo() {
  try {
    const output = execFileSync('df', ['-B1', '/']).toString().trim();
    const lines = output.split('\n');
    const parts = lines[lines.length - 1].split(/\s+/);
    const totalBytes = parseInt(parts[1]);
    const usedBytes = parseInt(parts[2]);
    const freeBytes = parseInt(parts[3]);
    return {
      totalGB: +(totalBytes / 1e9).toFixed(1),
      usedGB: +(usedBytes / 1e9).toFixed(1),
      freeGB: +(freeBytes / 1e9).toFixed(1),
    };
  } catch {
    return { totalGB: 0, usedGB: 0, freeGB: 0 };
  }
}

function getIpfsStats() {
  try {
    const idRaw = execFileSync('ipfs', ['id', '--encoding=json']).toString();
    const id = JSON.parse(idRaw);
    const peersRaw = execFileSync('ipfs', ['swarm', 'peers']).toString().trim();
    const peerCount = peersRaw ? peersRaw.split('\n').length : 0;
    return {
      peerId: id.ID,
      agentVersion: id.AgentVersion,
      peers: peerCount,
    };
  } catch {
    return { peerId: null, agentVersion: null, peers: 0 };
  }
}

function getUptimeInfo() {
  let systemUptimeSeconds = null;
  try {
    const raw = fs.readFileSync('/proc/uptime', 'utf-8');
    systemUptimeSeconds = Math.floor(parseFloat(raw.split(' ')[0]));
  } catch {
    // Not on Linux or /proc unavailable
  }
  return {
    systemSeconds: systemUptimeSeconds,
    apiSeconds: Math.floor(process.uptime()),
  };
}

// Validate CID format (base32/base58, alphanumeric)
function isValidCID(cid) {
  return /^[a-zA-Z0-9]+$/.test(cid) && cid.length >= 46 && cid.length <= 128;
}

// File upload storage — temp dir, cleaned up after IPFS add
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir);

const upload = multer({
  dest: uploadDir,
  limits: { fileSize: 100 * 1024 * 1024 }, // 100 MB max
  fileFilter: (req, file, cb) => {
    const allowed = [
      'audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/aac',
      'audio/wav', 'audio/x-wav', 'audio/aiff', 'audio/x-aiff',
      'audio/flac', 'audio/ogg',
    ];
    cb(null, allowed.includes(file.mimetype));
  },
});

// ---------------------------------------------------------------------------
// Routes: Health
// ---------------------------------------------------------------------------

app.get('/api/health', (req, res) => {
  const trackCount = db.prepare('SELECT COUNT(*) as count FROM tracks').get().count;
  const storage = getStorageInfo();
  const ipfs = getIpfsStats();
  const uptime = getUptimeInfo();

  res.json({
    status: 'online',
    node: 'seedthenode',
    timestamp: new Date().toISOString(),
    message: 'SeedTheNode is live',
    trackCount,
    storage,
    ipfs,
    uptime,
  });
});

// ---------------------------------------------------------------------------
// Routes: Tracks
// ---------------------------------------------------------------------------

// List all tracks
app.get('/api/tracks', (req, res) => {
  const tracks = db.prepare(`
    SELECT t.*, COUNT(v.id) as version_count
    FROM tracks t
    LEFT JOIN versions v ON v.track_id = t.id
    GROUP BY t.id
    ORDER BY t.created_at DESC
  `).all();
  res.json(tracks);
});

// Get single track with versions
app.get('/api/tracks/:id', (req, res) => {
  const track = db.prepare('SELECT * FROM tracks WHERE id = ?').get(req.params.id);
  if (!track) return res.status(404).json({ error: 'Track not found' });

  const versions = db.prepare(
    'SELECT * FROM versions WHERE track_id = ? ORDER BY version_number DESC'
  ).all(req.params.id);

  res.json({ ...track, versions });
});

// Create a new track
app.post('/api/tracks', (req, res) => {
  const { title, artistName } = req.body;
  if (!title || !artistName) {
    return res.status(400).json({ error: 'title and artistName are required' });
  }

  const id = uuid();
  const now = new Date().toISOString();

  db.prepare(`
    INSERT INTO tracks (id, title, artist_name, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, title, artistName, now, now);

  const track = db.prepare('SELECT * FROM tracks WHERE id = ?').get(id);
  res.status(201).json(track);
});

// Delete a track
app.delete('/api/tracks/:id', (req, res) => {
  const result = db.prepare('DELETE FROM tracks WHERE id = ?').run(req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Track not found' });
  res.json({ deleted: true });
});

// Upload audio file to a track → IPFS add + pin + update track CID
app.post('/api/tracks/:id/upload', upload.single('audio'), (req, res) => {
  const track = db.prepare('SELECT * FROM tracks WHERE id = ?').get(req.params.id);
  if (!track) {
    if (req.file) fs.unlinkSync(req.file.path);
    return res.status(404).json({ error: 'Track not found' });
  }
  if (!req.file) {
    return res.status(400).json({ error: 'No audio file provided or unsupported format' });
  }

  try {
    // Add file to IPFS
    const addOutput = execFileSync('ipfs', ['add', '-q', req.file.path]).toString().trim();
    const cid = addOutput.split('\n').pop();

    // Pin the CID
    execFileSync('ipfs', ['pin', 'add', cid]);

    // Update track with the CID
    const now = new Date().toISOString();
    db.prepare('UPDATE tracks SET ipfs_cid = ?, updated_at = ? WHERE id = ?')
      .run(cid, now, req.params.id);

    // Create a version record
    const versionCount = db.prepare(
      'SELECT COUNT(*) as count FROM versions WHERE track_id = ?'
    ).get(req.params.id).count;

    db.prepare(`
      INSERT INTO versions (id, track_id, version_number, audio_cid, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(uuid(), req.params.id, versionCount + 1, cid, now);

    // Clean up temp file
    fs.unlinkSync(req.file.path);

    const updated = db.prepare('SELECT * FROM tracks WHERE id = ?').get(req.params.id);
    res.json(updated);
  } catch (err) {
    if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
    res.status(500).json({ error: 'Failed to add file to IPFS: ' + err.message });
  }
});

// ---------------------------------------------------------------------------
// Routes: IPFS
// ---------------------------------------------------------------------------

// Get content from IPFS by CID (JSON metadata)
app.get('/api/ipfs/:cid', (req, res) => {
  if (!isValidCID(req.params.cid)) {
    return res.status(400).json({ error: 'Invalid CID format' });
  }
  try {
    const data = execFileSync('ipfs', ['cat', req.params.cid]).toString();
    res.json({ cid: req.params.cid, content: data });
  } catch (err) {
    res.status(404).json({ error: 'CID not found or IPFS error' });
  }
});

// Stream audio from IPFS — AVPlayer hits this URL directly
app.get('/api/stream/:cid', (req, res) => {
  if (!isValidCID(req.params.cid)) {
    return res.status(400).json({ error: 'Invalid CID format' });
  }
  try {
    const data = execFileSync('ipfs', ['cat', req.params.cid], { maxBuffer: 200 * 1024 * 1024 });
    res.set('Content-Type', 'audio/mp4');
    res.set('Content-Length', data.length);
    res.set('Accept-Ranges', 'bytes');
    res.send(data);
  } catch (err) {
    res.status(404).json({ error: 'CID not found or IPFS error' });
  }
});

// Pin a CID
app.post('/api/ipfs/pin/:cid', (req, res) => {
  if (!isValidCID(req.params.cid)) {
    return res.status(400).json({ error: 'Invalid CID format' });
  }
  try {
    execFileSync('ipfs', ['pin', 'add', req.params.cid]);
    res.json({ pinned: true, cid: req.params.cid });
  } catch (err) {
    res.status(500).json({ error: 'Failed to pin' });
  }
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

app.listen(PORT, '0.0.0.0', () => {
  console.log(`SeedTheNode API running on port ${PORT}`);
});
