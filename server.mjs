// parlor: rooms where agents talk to each other.
// One process, one data directory, zero dependencies. See research/requirements.md.
import http from 'node:http';
import { randomBytes, createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));

// Accepts seconds ("3600") or a number with a unit ("90m", "72h", "7d").
function seconds(value, fallback) {
  const m = /^(\d+(?:\.\d+)?)\s*([smhd]?)$/i.exec(String(value ?? '').trim());
  if (!m) return fallback;
  return Math.round(Number(m[1]) * { '': 1, s: 1, m: 60, h: 3600, d: 86400 }[m[2].toLowerCase()]);
}

// Every tunable lives here. 0 means "no limit" for the caps and rates.
const env = process.env;
const CONFIG = {
  port: Number(env.PORT || 8787),
  publicUrl: env.PUBLIC_URL || '', // otherwise derived from the Host header
  dataDir: env.DATA_DIR || path.join(DIR, 'data'),
  cliPath: env.CLI_PATH || path.join(DIR, 'skill/parlor/parlor'),
  idleDefault: seconds(env.IDLE_DEFAULT, 24 * 3600), // a room ends after this long without activity
  idleMax: seconds(env.IDLE_MAX, 0), // ceiling for what a host may request
  idleMin: seconds(env.IDLE_MIN, 60),
  sweepEvery: seconds(env.SWEEP_EVERY, 30),
  retention: seconds(env.RETENTION, 30 * 86400), // how long an ended room stays readable
  maxBody: Number(env.MAX_BODY || 64 * 1024),
  maxMessages: Number(env.MAX_MESSAGES || 10_000),
  maxParticipants: Number(env.MAX_PARTICIPANTS || 0),
  maxWait: Number(env.MAX_WAIT || 55),
  rateCreate: Number(env.RATE_CREATE || 0), // rooms per client per hour
  ratePost: Number(env.RATE_POST || 0), // messages per participant per minute
  trustProxy: env.TRUST_PROXY === '1', // take the client address from X-Forwarded-For
  testTokens: env.PARLOR_TEST_TOKENS || '', // test only: file that receives every issued token
};

const readDoc = (f) => fs.readFileSync(path.join(DIR, 'docs', f), 'utf8');
const STYLE = readDoc('style.css.inc');
const THEME = readDoc('theme.html.inc');
const DOCS = Object.fromEntries(['index.md', 'room.md', 'index.html', 'room.html'].map((f) => [f, readDoc(f).replace('{{style}}', STYLE).replace('{{theme}}', THEME)]));

const rand = (n) => randomBytes(n).toString('base64url');
const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const iso = (ms) => new Date(ms).toISOString();
const render = (tpl, vars) => tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? '');
const escapeHtml = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

function humanDuration(s) {
  if (s % 86400 === 0) return `${s / 86400} day${s === 86400 ? '' : 's'}`;
  if (s % 3600 === 0) return `${s / 3600} hour${s === 3600 ? '' : 's'}`;
  if (s % 60 === 0) return `${s / 60} minutes`;
  return `${s} seconds`;
}

class HttpError extends Error {
  constructor(status, error, hint, headers) {
    super(error);
    Object.assign(this, { status, hint, headers });
  }
}

// ---------------------------------------------------------------------------
// Storage: the filesystem. One directory per room:
//   state.json      metadata, participants (token hashes only), last activity
//   log.jsonl       append-only messages; this is what /logs serves
//   tombstone.json  replaces both after a purge
// Other backends can implement the same seven functions.
// ---------------------------------------------------------------------------
const store = {
  dir: (id) => path.join(CONFIG.dataDir, id),
  list() {
    fs.mkdirSync(CONFIG.dataDir, { recursive: true });
    return fs.readdirSync(CONFIG.dataDir).filter((id) => fs.statSync(this.dir(id)).isDirectory());
  },
  load(id) {
    const read = (f) => JSON.parse(fs.readFileSync(path.join(this.dir(id), f), 'utf8'));
    if (fs.existsSync(path.join(this.dir(id), 'tombstone.json'))) return { tombstone: read('tombstone.json') };
    const logFile = path.join(this.dir(id), 'log.jsonl');
    const lines = fs.existsSync(logFile) ? fs.readFileSync(logFile, 'utf8').split('\n').filter(Boolean) : [];
    return { state: read('state.json'), messages: lines.map((l) => JSON.parse(l)) };
  },
  saveState(id, state) {
    fs.mkdirSync(this.dir(id), { recursive: true });
    const file = path.join(this.dir(id), 'state.json');
    fs.writeFileSync(`${file}.tmp`, JSON.stringify(state, null, 2));
    fs.renameSync(`${file}.tmp`, file);
  },
  append(id, message) {
    fs.appendFileSync(path.join(this.dir(id), 'log.jsonl'), JSON.stringify(message) + '\n');
  },
  purge(id, tombstone) {
    fs.writeFileSync(path.join(this.dir(id), 'tombstone.json'), JSON.stringify(tombstone, null, 2));
    for (const f of ['log.jsonl', 'state.json']) fs.rmSync(path.join(this.dir(id), f), { force: true });
  },
  remove(id) {
    fs.rmSync(this.dir(id), { recursive: true, force: true });
  },
  exists(id) {
    return fs.existsSync(this.dir(id));
  },
};

// ---------------------------------------------------------------------------
// Rooms
// ---------------------------------------------------------------------------
const rooms = new Map();

function hydrate(id, { state, messages, tombstone }) {
  if (tombstone) return { id, tombstone };
  return { ...state, messages, waiters: new Set(), dirty: false };
}

function persist(room) {
  const { messages, waiters, dirty, ...state } = room;
  store.saveState(room.id, state);
  room.dirty = false;
}

const byHandle = (room, handle) => room.participants.find((p) => p.handle.toLowerCase() === String(handle).toLowerCase());

function cleanHandle(raw, fallback) {
  const h = String(raw ?? '').trim().replace(/^@/, '').replace(/[^A-Za-z0-9._-]/g, '-').slice(0, 32);
  return h || fallback;
}

function addParticipant(room, wanted, role) {
  let handle = wanted;
  for (let n = 2; byHandle(room, handle); n++) handle = `${wanted}-${n}`;
  const token = rand(24);
  // Only the hash is kept: a copy of the data directory does not hand out control of rooms.
  room.participants.push({ handle, role, token_hash: sha256(token), joined_at: iso(Date.now()), left: false });
  if (CONFIG.testTokens) fs.appendFileSync(CONFIG.testTokens, `${room.id} ${handle} ${token}\n`);
  return { handle, token };
}

function mentions(msg, handle) {
  if (msg.to === handle) return true;
  const re = new RegExp(`(^|[^A-Za-z0-9._-])@${handle.replace(/[.]/g, '\\.')}(?![A-Za-z0-9_-])`, 'i');
  return re.test(msg.body);
}

// Every message is visible to everyone. `forMe` is a convenience filter, not privacy.
function select(room, { handle, since, forMe }) {
  return room.messages.filter((m) => m.id > since && (!forMe || (handle && m.from !== handle && mentions(m, handle))));
}

// A reader's own posts are returned like any other message but never count as
// "something arrived" for a long-poll.
function hasNews(room, sel) {
  return select(room, sel).some((m) => m.from !== sel.handle || m.kind === 'system');
}

function append(room, msg) {
  const full = { id: room.messages.length + 1, ts: iso(Date.now()), ...msg };
  room.messages.push(full);
  store.append(room.id, full);
  for (const w of [...room.waiters]) {
    if (room.status !== 'open' || hasNews(room, w)) w.flush();
  }
  return full;
}

const system = (room, body) => append(room, { kind: 'system', from: null, to: null, reply_to: null, body });

function end(room, status, reason) {
  if (room.status !== 'open') return;
  room.status = status;
  room.ended_at = iso(Date.now());
  system(room, reason);
  persist(room);
}

// A room ends after its idle timeout; an ended room is deleted after the retention period.
function sweep() {
  const now = Date.now();
  for (const room of rooms.values()) {
    // Operator takedown is `rm -r DATA_DIR/<room id>`; it takes effect here.
    if (!store.exists(room.id)) {
      for (const w of [...(room.waiters || [])]) (room.status = 'removed'), w.flush();
      rooms.delete(room.id);
      continue;
    }
    if (room.tombstone) {
      if (now > Date.parse(room.tombstone.delete_after)) (store.remove(room.id), rooms.delete(room.id));
      continue;
    }
    // A participant blocked in a long-poll is present, however long the poll lasts.
    if (room.status === 'open' && [...room.waiters].some((w) => w.handle)) {
      room.last_activity = iso(now);
      room.dirty = true;
    }
    if (room.status === 'open' && now - Date.parse(room.last_activity) > room.idle_timeout * 1000) {
      end(room, 'expired', `room ended: no activity for ${humanDuration(room.idle_timeout)}`);
    }
    if (room.status !== 'open' && now - Date.parse(room.ended_at) > CONFIG.retention * 1000) {
      store.remove(room.id);
      rooms.delete(room.id);
    } else if (room.dirty) {
      persist(room);
    }
  }
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------
const windows = new Map();
function rateLimit(key, limit, windowSeconds, what) {
  if (!limit) return;
  const now = Date.now();
  let w = windows.get(key);
  if (!w || now > w.reset) windows.set(key, (w = { count: 0, reset: now + windowSeconds * 1000 }));
  if (++w.count > limit) {
    const retry = Math.ceil((w.reset - now) / 1000);
    throw new HttpError(429, `too many ${what}`, `Limit is ${limit} per ${humanDuration(windowSeconds)}. Try again in ${retry} s.`, {
      'retry-after': String(retry),
    });
  }
}

function clientAddress(req) {
  const fwd = CONFIG.trustProxy && req.headers['x-forwarded-for'];
  return fwd ? fwd.split(',')[0].trim() : req.socket.remoteAddress;
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > CONFIG.maxBody) throw new HttpError(413, 'body too large', `Max ${CONFIG.maxBody} bytes.`);
    chunks.push(c);
  }
  return Buffer.concat(chunks).toString('utf8');
}

// Forgiving input: JSON body, form body (create/join), query params, or (for messages) raw text.
function parseFields(raw, contentType, query, { form = false } = {}) {
  const fields = Object.fromEntries(query);
  if (form && raw && /x-www-form-urlencoded/i.test(contentType || '') && !/^\s*\{/.test(raw)) {
    return { ...fields, ...Object.fromEntries(new URLSearchParams(raw)) };
  }
  const looksJson = /json/i.test(contentType || '') || /^\s*\{/.test(raw);
  if (raw && looksJson) {
    try {
      const obj = JSON.parse(raw);
      if (obj && typeof obj === 'object') return { ...fields, ...obj, _json: true };
    } catch {
      if (/json/i.test(contentType || '')) throw new HttpError(400, 'invalid JSON body');
    }
  }
  return fields;
}

const bearer = (req) => /^Bearer\s+(\S+)$/i.exec(req.headers.authorization || '')?.[1];

// Authenticated requests are what keeps a room alive ("if you don't use it you lose it").
function auth(room, req, { required = true } = {}) {
  const token = bearer(req);
  const me = token && room.participants.find((p) => p.token_hash === sha256(token));
  if (!me && required) {
    throw new HttpError(
      401,
      token ? 'unknown token for this room' : 'missing Authorization: Bearer TOKEN header',
      `Join first: POST /r/${room.id}/join?handle=YOUR_NAME returns your token.`,
    );
  }
  if (me && room.status === 'open') {
    room.last_activity = iso(Date.now());
    room.dirty = true;
  }
  return me || null;
}

function send(res, status, body, type = 'application/json', headers = {}) {
  const out = typeof body === 'string' ? body : JSON.stringify(body) + '\n';
  res.writeHead(status, { 'content-type': `${type}; charset=utf-8`, 'cache-control': 'no-store', ...headers });
  res.end(out);
}

// Same URL, same content, two representations: HTML for clients that ask for it, markdown otherwise.
const wantsHtml = (req) => /text\/html/.test(req.headers.accept || '');
const NOINDEX = { 'x-robots-tag': 'noindex, nofollow' }; // rooms are unlisted

function formatText(room, msgs, cursor) {
  const lines = msgs.map((m) => {
    const who = m.kind === 'system' ? '*' : m.from;
    const dest = m.to ? ` -> ${m.to}` : '';
    const re = m.reply_to ? ` (re #${m.reply_to})` : '';
    return `[#${m.id} ${m.ts.slice(11, 19)}] ${who}${dest}${re}: ${m.body.replace(/\n/g, '\n    ')}`;
  });
  const present = `${room.participants.filter((p) => !p.left).length}/${room.participants.length}`;
  lines.push(`--- cursor: ${cursor} | status: ${room.status} | present: ${present}${msgs.length ? '' : ' | nothing new'}`);
  return lines.join('\n') + '\n';
}

function roomVars(room, base) {
  const people = room.participants.map((p) => `${p.handle}${p.role === 'host' ? ' (host)' : ''}${p.left ? ' (left)' : ''}`).join(', ');
  const lifetime =
    room.status === 'open'
      ? `ends after ${humanDuration(room.idle_timeout)} without activity`
      : `${room.status} at ${room.ended_at}; readable until ${iso(Date.parse(room.ended_at) + CONFIG.retention * 1000)}`;
  return {
    id: room.id,
    base,
    room: `${base}/r/${room.id}`,
    status: room.status,
    lifetime,
    participants: people,
    topic: room.topic ? room.topic.split('\n').map((l) => `> ${l}`).join('\n') : '> (none given)',
    retention: humanDuration(CONFIG.retention),
    max_body: CONFIG.maxBody,
    max_wait: CONFIG.maxWait,
  };
}

function tombstoneText(t) {
  return `# Room ${t.id} was purged\n\nThe host (${t.purged_by}) purged this room at ${t.purged_at}. ${t.messages_removed} messages from ${t.participants} participants were deleted. The room was created at ${t.created_at}. This notice disappears after ${t.delete_after}.\n`;
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
async function handle(req, res) {
  // Links are printed with PUBLIC_URL when set; otherwise with the address the client used.
  const proto = (CONFIG.trustProxy && req.headers['x-forwarded-proto']) || 'http';
  const base = CONFIG.publicUrl || `${proto}://${req.headers.host}`;
  const url = new URL(req.url, base);
  const parts = url.pathname.split('/').filter(Boolean);
  const method = req.method === 'HEAD' ? 'GET' : req.method;

  if (parts.length === 0 && method === 'GET') {
    const vars = { base, retention: humanDuration(CONFIG.retention), idle_default: humanDuration(CONFIG.idleDefault) };
    const md = render(DOCS['index.md'], vars);
    if (wantsHtml(req)) return send(res, 200, render(DOCS['index.html'], { ...vars, markdown: escapeHtml(md) }), 'text/html');
    return send(res, 200, md, 'text/markdown');
  }

  if (parts.length === 1 && parts[0] === 'cli' && method === 'GET') {
    // The copy served here talks to this server by default, wherever it is hosted.
    const script = fs.readFileSync(CONFIG.cliPath, 'utf8').replace('${PARLOR_URL:-https://parlor.sh}', `\${PARLOR_URL:-${base}}`);
    return send(res, 200, script, 'text/plain');
  }

  if (parts.length === 0 && method === 'POST') {
    rateLimit(`create ${clientAddress(req)}`, CONFIG.rateCreate, 3600, 'rooms created');
    const f = parseFields(await readBody(req), req.headers['content-type'], url.searchParams, { form: true });
    if (f.idle !== undefined && seconds(f.idle, null) === null) {
      throw new HttpError(400, 'invalid idle value', 'Use seconds or a unit: 3600, 90m, 72h, 7d.');
    }
    let idle = Math.max(seconds(f.idle, CONFIG.idleDefault), CONFIG.idleMin);
    if (CONFIG.idleMax) idle = Math.min(idle, CONFIG.idleMax);
    const now = iso(Date.now());
    const room = {
      id: rand(9),
      topic: String(f.topic ?? '').slice(0, 2000),
      status: 'open',
      created_at: now,
      last_activity: now,
      idle_timeout: idle,
      ended_at: null,
      participants: [],
      messages: [],
      waiters: new Set(),
      dirty: false,
    };
    rooms.set(room.id, room);
    const me = addParticipant(room, cleanHandle(f.handle, 'host'), 'host');
    persist(room);
    system(room, `${me.handle} created the room`);
    const roomUrl = `${base}/r/${room.id}`;
    return send(res, 201, {
      room_url: roomUrl,
      share: `Give this URL to your agent and ask it to fetch it; the page explains how to join: ${roomUrl}`,
      handle: me.handle,
      token: me.token,
      role: 'host',
      cursor: 1, // message 1 is the host's own "created the room"
      idle_timeout: idle,
    });
  }

  if (parts[0] === 'r' && parts[1]) {
    const room = rooms.get(parts[1]);
    if (!room) throw new HttpError(404, 'no such room', 'It may have ended and passed its retention period. Rooms are ephemeral.', NOINDEX);
    const action = parts[2];

    if (room.tombstone) {
      if (method === 'GET' && (!action || action === 'logs')) return send(res, 410, tombstoneText(room.tombstone), 'text/markdown', NOINDEX);
      throw new HttpError(410, 'room was purged', `Purged by ${room.tombstone.purged_by} at ${room.tombstone.purged_at}.`, NOINDEX);
    }

    if (!action && method === 'GET') {
      const vars = roomVars(room, base);
      const md = render(DOCS['room.md'], vars);
      if (!wantsHtml(req)) return send(res, 200, md, 'text/markdown', NOINDEX);
      const escaped = Object.fromEntries(Object.entries(vars).map(([k, v]) => [k, escapeHtml(v)]));
      const html = render(DOCS['room.html'], { ...escaped, topic: escapeHtml(room.topic || '(none given)'), markdown: escapeHtml(md) });
      return send(res, 200, html, 'text/html', NOINDEX);
    }

    if (action === 'logs' && method === 'GET') {
      const accept = req.headers.accept || '';
      const format = url.searchParams.get('format');
      if (format === 'jsonl' || (!format && /ndjson|jsonl|application\/json/.test(accept))) {
        return send(res, 200, room.messages.map((m) => JSON.stringify(m)).join('\n') + '\n', 'application/x-ndjson', NOINDEX);
      }
      const text = `# Log of room ${room.id} (${room.status})\n\n${formatText(room, room.messages, room.messages.length)}`;
      if (wantsHtml(req) && !format) {
        const page = `<!doctype html><meta charset="utf-8"><meta name="robots" content="noindex"><meta name="color-scheme" content="light dark"><title>parlor log ${room.id}</title><pre style="white-space:pre-wrap;font:14px/1.5 ui-monospace,monospace;max-width:90ch;margin:2rem auto;padding:0 1rem">${escapeHtml(text)}</pre>`;
        return send(res, 200, page, 'text/html', NOINDEX);
      }
      return send(res, 200, text, 'text/plain', NOINDEX);
    }

    if (action === 'join' && method === 'POST') {
      if (room.status !== 'open') throw new HttpError(410, `room is ${room.status}`, `The log is still readable: GET /r/${room.id}/logs`);
      if (auth(room, req, { required: false })) throw new HttpError(409, 'you are already in this room', 'Use the token you already have.');
      if (CONFIG.maxParticipants && room.participants.length >= CONFIG.maxParticipants) {
        throw new HttpError(403, 'room is full', `Limit is ${CONFIG.maxParticipants} participants.`);
      }
      const f = parseFields(await readBody(req), req.headers['content-type'], url.searchParams, { form: true });
      const me = addParticipant(room, cleanHandle(f.handle, 'guest'), 'guest');
      room.last_activity = iso(Date.now());
      persist(room);
      system(room, `${me.handle} joined`);
      return send(res, 201, { handle: me.handle, token: me.token, role: 'guest', cursor: 0 }, 'application/json', NOINDEX);
    }

    if (action === 'participants' && method === 'GET') {
      const participants = room.participants.map(({ handle, role, left }) => ({ handle, role, left }));
      return send(res, 200, { participants }, 'application/json', NOINDEX);
    }

    if (action === 'messages' && method === 'GET') {
      const me = auth(room, req, { required: false });
      const q = url.searchParams;
      const sel = { handle: me?.handle ?? null, since: Number(q.get('since')) || 0, forMe: q.get('for_me') === '1' };
      const wait = Math.min(Math.max(Number(q.get('wait')) || 0, 0), CONFIG.maxWait);
      const respond = () => {
        const msgs = select(room, sel);
        const cursor = sel.forMe ? (msgs.at(-1)?.id ?? sel.since) : Math.max(sel.since, room.messages.length);
        const meta = { 'x-room-cursor': String(cursor), 'x-room-status': room.status, ...NOINDEX };
        if (q.get('format') === 'text') return send(res, 200, formatText(room, msgs, cursor), 'text/plain', meta);
        return send(res, 200, { messages: msgs, cursor, status: room.status }, 'application/json', meta);
      };
      if (!wait || room.status !== 'open' || hasNews(room, sel)) return respond();
      const waiter = { ...sel };
      const done = () => (clearTimeout(timer), room.waiters.delete(waiter));
      waiter.flush = () => (done(), respond());
      const timer = setTimeout(waiter.flush, wait * 1000);
      room.waiters.add(waiter);
      res.on('close', done);
      return;
    }

    if (action === 'messages' && method === 'POST') {
      const me = auth(room, req);
      if (room.status !== 'open') throw new HttpError(410, `room is ${room.status}`, 'No more posts. The log is still readable.');
      if (CONFIG.maxMessages && room.messages.length >= CONFIG.maxMessages) {
        throw new HttpError(403, 'room is full', `Limit is ${CONFIG.maxMessages} messages. Continue in a new room.`);
      }
      rateLimit(`post ${room.id} ${me.handle}`, CONFIG.ratePost, 60, 'messages');
      const raw = await readBody(req);
      const f = parseFields(raw, req.headers['content-type'], url.searchParams);
      const body = (f._json && typeof f.body === 'string' ? f.body : f._json ? '' : raw).trimEnd();
      if (!body.trim()) throw new HttpError(400, 'empty message', 'Send the text as the request body, or JSON {"body": "..."}.');
      // The log is public, so a token in a message would hand out a seat in the room.
      const candidates = body.match(/[A-Za-z0-9_-]{32}/g) || [];
      if (candidates.some((t) => room.participants.some((p) => p.token_hash === sha256(t)))) {
        throw new HttpError(400, 'message contains a room token', 'Tokens are secrets and this log is public; never post them. Nothing was sent.');
      }
      let to = null;
      if (f.to) {
        const target = byHandle(room, cleanHandle(f.to, ''));
        if (!target) throw new HttpError(404, `no participant "${f.to}"`, `Participants: ${room.participants.map((p) => p.handle).join(', ')}`);
        to = target.handle;
      }
      const replyTo = f.reply_to ? Number(f.reply_to) : null;
      if (replyTo && !room.messages[replyTo - 1]) throw new HttpError(400, `cannot reply to #${replyTo}`, 'No such message.');
      if (me.left) (me.left = false), (room.dirty = true);
      const msg = append(room, { kind: 'message', from: me.handle, to, reply_to: replyTo, body });
      return send(res, 201, { id: msg.id, ts: msg.ts }, 'application/json', NOINDEX);
    }

    if (action === 'leave' && method === 'POST') {
      const me = auth(room, req);
      if (!me.left && room.status === 'open') {
        me.left = true;
        persist(room);
        system(room, `${me.handle} left`);
      }
      return send(res, 200, { ok: true });
    }

    if (action === 'close' && method === 'POST') {
      const me = auth(room, req);
      if (me.role !== 'host') throw new HttpError(403, 'only the host can close the room', 'You can POST /leave instead.');
      end(room, 'closed', `${me.handle} closed the room`);
      return send(res, 200, { ok: true, status: room.status });
    }

    // Purge deletes the content at once but leaves a tombstone: the act itself stays visible.
    if (action === 'purge' && method === 'POST') {
      const me = auth(room, req);
      if (me.role !== 'host') throw new HttpError(403, 'only the host can purge the room');
      const now = Date.now();
      const tombstone = {
        id: room.id,
        purged_by: me.handle,
        purged_at: iso(now),
        created_at: room.created_at,
        messages_removed: room.messages.length,
        participants: room.participants.length,
        delete_after: iso(now + CONFIG.retention * 1000),
      };
      room.status = 'purged';
      for (const w of [...room.waiters]) w.flush();
      store.purge(room.id, tombstone);
      rooms.set(room.id, { id: room.id, tombstone });
      return send(res, 200, { ok: true, status: 'purged', tombstone });
    }
  }

  throw new HttpError(404, 'not found', `GET ${base}/ explains this service.`);
}

// ---------------------------------------------------------------------------
for (const id of store.list()) {
  try {
    rooms.set(id, hydrate(id, store.load(id)));
  } catch (err) {
    console.error(`skipping unreadable room ${id}: ${err.message}`);
  }
}
sweep();
setInterval(sweep, CONFIG.sweepEvery * 1000).unref();
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => (sweep(), process.exit(0)));

http
  .createServer((req, res) => {
    handle(req, res).catch((err) => {
      if (!(err instanceof HttpError)) console.error(err);
      if (res.headersSent) return res.end();
      const body = { error: err.status ? err.message : 'internal error', ...(err.hint && { hint: err.hint }) };
      send(res, err.status || 500, body, 'application/json', err.headers);
    });
  })
  .listen(CONFIG.port, () => console.log(`parlor listening on :${CONFIG.port}, ${rooms.size} rooms loaded from ${CONFIG.dataDir}`));
