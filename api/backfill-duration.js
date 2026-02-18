#!/usr/bin/env node
// backfill-duration.js — One-time script to compute duration for existing tracks.
// Run on Pi: node backfill-duration.js

const Database = require('better-sqlite3');
const { execFileSync, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const db = new Database(path.join(__dirname, 'seedthenode.db'));
db.pragma('journal_mode = WAL');

// Ensure the duration column exists
try { db.exec('ALTER TABLE tracks ADD COLUMN duration REAL'); } catch {}

const tracks = db.prepare(
  'SELECT id, title, ipfs_cid FROM tracks WHERE ipfs_cid IS NOT NULL AND duration IS NULL'
).all();

console.log(`Found ${tracks.length} track(s) to backfill.\n`);

const update = db.prepare('UPDATE tracks SET duration = ? WHERE id = ?');

let success = 0;
let failed = 0;

for (const track of tracks) {
  const label = `  ${track.title} (${track.ipfs_cid.slice(0, 12)}...)`;
  process.stdout.write(label + '  ');

  // Write IPFS content to a temp file, then probe it
  const tmp = path.join(os.tmpdir(), `backfill-${track.id}`);
  try {
    const audio = execFileSync('ipfs', ['cat', track.ipfs_cid], { timeout: 60000 });
    fs.writeFileSync(tmp, audio);

    const result = spawnSync('ffprobe', [
      '-v', 'quiet', '-print_format', 'json', '-show_format', tmp,
    ], { timeout: 15000 });

    const parsed = JSON.parse(result.stdout.toString());
    const dur = parseFloat(parsed.format?.duration);

    if (isFinite(dur) && dur > 0) {
      update.run(dur, track.id);
      console.log(`${dur.toFixed(2)}s`);
      success++;
    } else {
      console.log('no duration found');
      failed++;
    }
  } catch (err) {
    console.log(`ERROR: ${err.message.split('\n')[0]}`);
    failed++;
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
}

console.log(`\nDone. Updated: ${success}, Failed: ${failed}`);
db.close();
