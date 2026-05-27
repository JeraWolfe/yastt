// YASTT -- C-Watch local token-monitoring server
// Serves the dashboard from THIS folder on localhost:8765; reads/writes YASTT data in ~/.claude/yastt/.
// Open http://localhost:8765/token_usage.html in a browser.
// /usage -> Claude rate-limit reset times + utilization. The OAuth token stays in this process; it
// is read from Claude Code's own ~/.claude/.credentials.json and never written, copied, or logged.

const http  = require('http');
const https = require('https');
const fs    = require('fs');
const path  = require('path');
const os    = require('os');

const PORT = 8765;
const ASSET_DIR = __dirname;                                                  // dashboard + this server (bundled with the package)
const DATA_DIR  = path.join(os.homedir(), '.claude', 'yastt');                // YASTT's data: CSVs + rollup state (never the package dir)
const CRED_PATH = path.join(os.homedir(), '.claude', '.credentials.json');    // Claude's OAuth token (read-only; never leaves here)
try { fs.mkdirSync(DATA_DIR, { recursive: true }); } catch (e) {}

const MIME = { '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript', '.csv': 'text/csv', '.json': 'application/json' };

// --- Rate-limit usage endpoint (undocumented OAuth endpoint) ---
const USAGE_TTL = 30000;                       // server-side cache: hit Anthropic at most every 30s
const OAUTH_BETA = 'oauth-2025-04-20';         // beta gate header -- update here if it changes
let usageCache = { body: null, at: 0 };

function fetchUsage() {
  return new Promise((resolve, reject) => {
    let token;
    try {
      const cred = JSON.parse(fs.readFileSync(CRED_PATH, 'utf8'));
      token = cred.claudeAiOauth && cred.claudeAiOauth.accessToken;
    } catch (e) { return reject(new Error('no credentials file')); }
    if (!token) return reject(new Error('no access token'));
    const r = https.request({
      hostname: 'api.anthropic.com', path: '/api/oauth/usage', method: 'GET',
      headers: { 'Authorization': 'Bearer ' + token, 'anthropic-beta': OAUTH_BETA },
    }, resp => {
      let body = '';
      resp.on('data', c => body += c);
      resp.on('end', () => resp.statusCode === 200 ? resolve(body) : reject(new Error('status ' + resp.statusCode)));
    });
    r.on('error', reject);
    r.setTimeout(15000, () => r.destroy(new Error('timeout')));
    r.end();
  });
}

// --- LOD rollup / retention (dormant until a billing week completes) ---------------
// Display grain coarsens as you zoom out; storage grain coarsens as data ages — same ladder.
// pips --(week ends)--> hourly per-WHO --(bumped off last week)--> weekly WHO-stripped (forever).
// The one safety rule: ROLL UP -> VERIFY -> SCRUB. Never delete finer rows until the coarser
// sum is written AND verified to equal them. The compact trigger is the user's real weekly
// reset (seven_day.resets_at). Idempotent: a re-run replaces (not duplicates) a week's rows.
const HOUR_MS = 3600000;
const WEEK_MS = 7 * 24 * HOUR_MS;
const ROLLUP_INTERVAL = 24 * HOUR_MS;
const F = {
  pips:   path.join(DATA_DIR, 'token_usage.csv'),
  hourly: path.join(DATA_DIR, 'yastt_hourly.csv'),
  weekly: path.join(DATA_DIR, 'yastt_weekly.csv'),
  state:  path.join(DATA_DIR, 'yastt_rollup_state.json'),
};
const HOURLY_HEADER = 'HourStart,DeltaSum,CostSum,CacheAvg,Who';
const WEEKLY_HEADER = 'WeekStart,DeltaSum,CostSum,CacheAvg';

const readLines     = file => { try { return fs.readFileSync(file, 'utf8').trim().split('\n').filter(l => l.trim()); } catch (e) { return []; } };
const pipMs         = c => { const ms = new Date(`${(c[3]||'').trim()}T${(c[4]||'').trim()}`).getTime(); return isNaN(ms) ? null : ms; };
const hourStartMs   = ms => Math.floor(ms / HOUR_MS) * HOUR_MS;
const weekStartMs   = (ms, anchor) => anchor + Math.floor((ms - anchor) / WEEK_MS) * WEEK_MS;
const loadState     = () => { try { return JSON.parse(fs.readFileSync(F.state, 'utf8')); } catch (e) { return {}; } };
const saveState     = s  => { try { fs.writeFileSync(F.state, JSON.stringify(s)); } catch (e) {} };

// Roll one completed week's raw pips into hourly per-WHO sums, then scrub those pips. Idempotent.
function compactPipsWeek(ws) {
  const we = ws + WEEK_MS;
  const lines = readLines(F.pips);
  if (lines.length <= 1) return;
  const header = lines[0];
  const inWeek = [], keep = [];
  lines.slice(1).forEach(l => { const c = l.split(','); const ms = pipMs(c); if (ms != null && ms >= ws && ms < we) inWeek.push(c); else keep.push(l); });
  if (!inWeek.length) return;
  const buckets = {};
  inWeek.forEach(c => {
    const key = hourStartMs(pipMs(c)) + '|' + ((c[7] || '?').trim() || '?');
    const e = buckets[key] || (buckets[key] = { hs: hourStartMs(pipMs(c)), who: (c[7] || '?').trim() || '?', delta: 0, cost: 0, cacheSum: 0, n: 0 });
    e.delta += parseInt(c[0]) || 0; e.cost += parseFloat(c[9]) || 0; e.cacheSum += parseFloat(c[10]) || 0; e.n++;
  });
  const newRows = Object.values(buckets).map(e => `${e.hs},${e.delta},${e.cost.toFixed(6)},${(e.n ? e.cacheSum / e.n : 0).toFixed(4)},${e.who}`);
  const expDelta = inWeek.reduce((s, c) => s + (parseInt(c[0]) || 0), 0);
  const expCost  = inWeek.reduce((s, c) => s + (parseFloat(c[9]) || 0), 0);
  // ROLL UP — replace any prior rows for this week (idempotent), append the fresh sums.
  let hLines = readLines(F.hourly); if (!hLines.length) hLines = [HOURLY_HEADER];
  const hKept = hLines.slice(1).filter(l => { const hs = parseInt(l.split(',')[0]); return !(hs >= ws && hs < we); });
  fs.writeFileSync(F.hourly, [hLines[0]].concat(hKept, newRows).join('\n') + '\n');
  // VERIFY — the just-written hourly rows for this week must equal the pip sums.
  const check = readLines(F.hourly).slice(1).map(l => l.split(',')).filter(c => { const hs = parseInt(c[0]); return hs >= ws && hs < we; });
  const gotDelta = check.reduce((s, c) => s + (parseFloat(c[1]) || 0), 0);
  const gotCost  = check.reduce((s, c) => s + (parseFloat(c[2]) || 0), 0);
  if (Math.round(gotDelta) !== Math.round(expDelta) || Math.abs(gotCost - expCost) > 1e-4) {
    console.log(`[rollup] VERIFY FAILED week ${new Date(ws).toISOString().slice(0, 10)} (delta ${gotDelta}/${expDelta}) — pips NOT scrubbed`);
    return;
  }
  // SCRUB — only now remove the raw pips.
  fs.writeFileSync(F.pips, [header].concat(keep).join('\n') + '\n');
  console.log(`[rollup] compacted ${inWeek.length} pips -> ${newRows.length} hourly rows, week ${new Date(ws).toISOString().slice(0, 10)}`);
}

// Bump hourly rows older than last week into weekly WHO-stripped blocks, then scrub them. Idempotent.
function bumpHourlyToWeekly(lastWeekStart, anchor) {
  const lines = readLines(F.hourly);
  if (lines.length <= 1) return;
  const header = lines[0];
  const bump = [], keep = [];
  lines.slice(1).forEach(l => { const c = l.split(','); const ws = weekStartMs(parseInt(c[0]), anchor); if (ws < lastWeekStart) bump.push(c); else keep.push(l); });
  if (!bump.length) return;
  const buckets = {};
  bump.forEach(c => {
    const ws = weekStartMs(parseInt(c[0]), anchor);
    const e = buckets[ws] || (buckets[ws] = { ws, delta: 0, cost: 0, cacheSum: 0, n: 0 });
    e.delta += parseFloat(c[1]) || 0; e.cost += parseFloat(c[2]) || 0; e.cacheSum += parseFloat(c[3]) || 0; e.n++;
  });
  const newRows = Object.values(buckets).map(e => `${e.ws},${e.delta},${e.cost.toFixed(6)},${(e.n ? e.cacheSum / e.n : 0).toFixed(4)}`);
  const expDelta = bump.reduce((s, c) => s + (parseFloat(c[1]) || 0), 0);
  const expCost  = bump.reduce((s, c) => s + (parseFloat(c[2]) || 0), 0);
  const bumpedWeeks = new Set(Object.keys(buckets).map(Number));
  // ROLL UP — replace any prior blocks for these weeks (idempotent), append.
  let wLines = readLines(F.weekly); if (!wLines.length) wLines = [WEEKLY_HEADER];
  const wKept = wLines.slice(1).filter(l => !bumpedWeeks.has(parseInt(l.split(',')[0])));
  fs.writeFileSync(F.weekly, [wLines[0]].concat(wKept, newRows).join('\n') + '\n');
  // VERIFY
  const check = readLines(F.weekly).slice(1).map(l => l.split(',')).filter(c => bumpedWeeks.has(parseInt(c[0])));
  const gotDelta = check.reduce((s, c) => s + (parseFloat(c[1]) || 0), 0);
  const gotCost  = check.reduce((s, c) => s + (parseFloat(c[2]) || 0), 0);
  if (Math.round(gotDelta) !== Math.round(expDelta) || Math.abs(gotCost - expCost) > 1e-4) {
    console.log('[rollup] WEEKLY VERIFY FAILED — hourly NOT scrubbed');
    return;
  }
  // SCRUB
  fs.writeFileSync(F.hourly, [header].concat(keep).join('\n') + '\n');
  console.log(`[rollup] bumped ${bump.length} hourly rows -> ${newRows.length} weekly blocks`);
}

// One pass: align to the real weekly reset, compact every completed week, then age hourly to weekly.
async function runRollup() {
  let anchor;
  try { const j = JSON.parse(await fetchUsage()); anchor = j.seven_day && j.seven_day.resets_at ? Date.parse(j.seven_day.resets_at) : null; } catch (e) { return; }
  if (!anchor) return;
  const now = Date.now();
  const cws = weekStartMs(now, anchor);     // start of the current (incomplete) week
  const state = loadState();
  if (state.lastCompactedWeekStart == null) { state.lastCompactedWeekStart = cws; saveState(state); }  // fresh install: don't touch the current week
  for (let ws = state.lastCompactedWeekStart; ws < cws; ws += WEEK_MS) {
    compactPipsWeek(ws);
    state.lastCompactedWeekStart = ws + WEEK_MS;
    saveState(state);
  }
  bumpHourlyToWeekly(cws - WEEK_MS, anchor);  // keep the last completed week as hourly; older -> weekly
}

http.createServer(async (req, res) => {
  const urlPath = req.url.split('?')[0];

  if (urlPath === '/usage') {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json');
    const now = Date.now();
    if (usageCache.body && now - usageCache.at < USAGE_TTL) { res.writeHead(200); res.end(usageCache.body); return; }
    try {
      const body = await fetchUsage();
      usageCache = { body, at: now };
      res.writeHead(200); res.end(body);
    } catch (e) {
      if (usageCache.body) { res.writeHead(200); res.end(usageCache.body); }      // serve stale rather than fail
      else { res.writeHead(200); res.end(JSON.stringify({ error: String(e.message || e) })); }
    }
    return;
  }

  // Data files (.csv) come from the user's data dir; the dashboard + assets come from the bundle.
  const baseDir = path.extname(urlPath) === '.csv' ? DATA_DIR : ASSET_DIR;
  const file = path.normalize(path.join(baseDir, urlPath));
  if (!file.startsWith(baseDir)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', MIME[path.extname(file)] || 'application/octet-stream');
    res.writeHead(200);
    res.end(data);
  });
}).listen(PORT, 'localhost', () => {
  console.log(`C-Watch running on http://localhost:${PORT}/token_usage.html`);
});

// Retention sweep: once on startup, then daily. Checks whether a weekly reset has passed;
// compacts + scrubs only when one has. No-ops on young data (nothing past a retention window yet).
runRollup();
setInterval(runRollup, ROLLUP_INTERVAL);
