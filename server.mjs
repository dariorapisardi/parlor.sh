// Rooms: ephemeral chat rooms for agents. Zero dependencies, in-memory state,
// append-only JSONL audit log per room under ./data.
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { readFileSync, mkdirSync, appendFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8787);
const PUBLIC_URL = process.env.PUBLIC_URL; // otherwise derived from the Host header
const DATA_DIR = process.env.DATA_DIR || path.join(DIR, 'data');
const DEFAULT_TTL = 24 * 3600;
const MAX_TTL = 7 * 24 * 3600;
const MAX_BODY = 64 * 1024;
const MAX_WAIT = 55;
const MAX_MESSAGES = 10_000;

const DOCS = {
  index: readFileSync(path.join(DIR, 'docs/index.md'), 'utf8'),
  room: readFileSync(path.join(DIR, 'docs/room.md'), 'utf8'),
};
mkdirSync(DATA_DIR, { recursive: true });

const rooms = new Map();

const rand = (n) => randomBytes(n).toString('base64url');
const render = (tpl, vars) => tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? '');

class HttpError extends Error {
  constructor(status, error, hint) {
    super(error);
    this.status = status;
    this.hint = hint;
  }
}

function audit(room, record) {
  appendFileSync(path.join(DATA_DIR, `${room.id}.jsonl`), JSON.stringify(record) + '\n');
}

function cleanHandle(raw, fallback) {
  const h = String(raw ?? '').trim().replace(/^@/, '').replace(/[^A-Za-z0-9._-]/g, '-').slice(0, 32);
  return h || fallback;
}

const TEST_TOKENS = process.env.ROOMS_TEST_TOKENS; // test only: file that receives every issued token

function addParticipant(room, wanted, role) {
  let handle = wanted;
  for (let n = 2; room.participants.has(handle.toLowerCase()); n++) handle = `${wanted}-${n}`;
  const token = rand(24);
  room.participants.set(handle.toLowerCase(), { handle, role, joinedAt: Date.now(), left: false });
  room.tokens.set(token, handle);
  if (TEST_TOKENS) appendFileSync(TEST_TOKENS, `${room.id} ${handle} ${token}\n`);
  return { handle, token };
}

function visibleTo(msg, handle) {
  return !msg.to || msg.to === handle || msg.from === handle;
}

function mentions(msg, handle) {
  if (msg.to === handle) return true;
  const re = new RegExp(`(^|[^A-Za-z0-9._-])@${handle.replace(/[.]/g, '\\.')}(?![A-Za-z0-9_-])`, 'i');
  return re.test(msg.body);
}

function select(room, { handle, since, forMe }) {
  return room.messages.filter(
    (m) => m.id > since && visibleTo(m, handle) && (!forMe || (handle && m.from !== handle && mentions(m, handle))),
  );
}

// A reader's own posts are returned like any other message but never count as
// "something arrived" for a long-poll.
function hasNews(room, sel) {
  return select(room, sel).some((m) => m.from !== sel.handle || m.kind === 'system');
}

function append(room, msg) {
  const full = { id: room.messages.length + 1, ts: new Date().toISOString(), ...msg };
  room.messages.push(full);
  audit(room, full);
  for (const w of [...room.waiters]) {
    if (room.status === 'closed' || hasNews(room, w)) w.flush();
  }
  return full;
}

function closeRoom(room, reason) {
  if (room.status === 'closed') return;
  room.status = 'closed';
  append(room, { kind: 'system', from: null, to: null, reply_to: null, body: reason });
}

function formatText(room, msgs, cursor) {
  const lines = msgs.map((m) => {
    const who = m.kind === 'system' ? '*' : m.from;
    const dest = m.to ? ` -> ${m.to} (private)` : '';
    const re = m.reply_to ? ` (re #${m.reply_to})` : '';
    const body = m.body.replace(/\n/g, '\n    ');
    return `[#${m.id} ${m.ts.slice(11, 19)}] ${who}${dest}${re}: ${body}`;
  });
  const people = [...room.participants.values()];
  const present = `${people.filter((p) => !p.left).length}/${people.length}`;
  lines.push(`--- cursor: ${cursor} | status: ${room.status} | present: ${present}${msgs.length ? '' : ' | nothing new'}`);
  return lines.join('\n') + '\n';
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > MAX_BODY) throw new HttpError(413, 'body too large', `Max ${MAX_BODY} bytes.`);
    chunks.push(c);
  }
  return Buffer.concat(chunks).toString('utf8');
}

// Forgiving input: JSON body, or query params, or (for messages) raw text.
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

function auth(room, req, { required = true } = {}) {
  const m = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization || '');
  const handle = m && room.tokens.get(m[1]);
  if (!handle && required) {
    throw new HttpError(
      401,
      m ? 'unknown token for this room' : 'missing Authorization: Bearer TOKEN header',
      `Join first: POST /r/${room.id}/join?handle=YOUR_NAME returns your token.`,
    );
  }
  return handle ? room.participants.get(handle.toLowerCase()) : null;
}

function send(res, status, body, type = 'application/json', headers = {}) {
  const out = typeof body === 'string' ? body : JSON.stringify(body) + '\n';
  res.writeHead(status, { 'content-type': `${type}; charset=utf-8`, 'cache-control': 'no-store', ...headers });
  res.end(out);
}

function sendDoc(req, res, md) {
  const browser = /text\/html/.test(req.headers.accept || '');
  send(res, 200, md, browser ? 'text/plain' : 'text/markdown');
}

async function handle(req, res) {
  const base = PUBLIC_URL || `http://${req.headers.host}`;
  const url = new URL(req.url, base);
  const parts = url.pathname.split('/').filter(Boolean);
  const method = req.method;

  if (parts.length === 0) {
    if (method === 'GET') {
      return sendDoc(req, res, render(DOCS.index, { base, default_ttl: DEFAULT_TTL, max_ttl: MAX_TTL }));
    }
    if (method === 'POST') {
      const f = parseFields(await readBody(req), req.headers['content-type'], url.searchParams, { form: true });
      const ttl = Math.min(Math.max(Number(f.ttl) || DEFAULT_TTL, 60), MAX_TTL);
      const room = {
        id: rand(9),
        topic: String(f.topic ?? '').slice(0, 2000),
        status: 'open',
        createdAt: Date.now(),
        expiresAt: Date.now() + ttl * 1000,
        participants: new Map(),
        tokens: new Map(),
        messages: [],
        waiters: new Set(),
      };
      rooms.set(room.id, room);
      const me = addParticipant(room, cleanHandle(f.handle, 'host'), 'host');
      audit(room, { kind: 'room', id: room.id, topic: room.topic, created_at: new Date().toISOString(), host: me.handle });
      append(room, { kind: 'system', from: null, to: null, reply_to: null, body: `${me.handle} created the room` });
      return send(res, 201, {
        room_url: `${base}/r/${room.id}`,
        share: `Give this URL to your agent and ask it to fetch it; the page explains how to join: ${base}/r/${room.id}`,
        handle: me.handle,
        token: me.token,
        role: 'host',
        cursor: 0,
        expires_at: new Date(room.expiresAt).toISOString(),
      });
    }
  }

  if (parts[0] === 'r' && parts[1]) {
    const room = rooms.get(parts[1]);
    if (!room) throw new HttpError(404, 'no such room', 'It may have expired. Rooms are ephemeral.');
    const roomUrl = `${base}/r/${room.id}`;
    const action = parts[2];

    if (!action && method === 'GET') {
      const people = [...room.participants.values()]
        .map((p) => `${p.handle}${p.role === 'host' ? ' (host)' : ''}${p.left ? ' (left)' : ''}`)
        .join(', ');
      const topic = room.topic ? room.topic.split('\n').map((l) => `> ${l}`).join('\n') : '> (none given)';
      return sendDoc(
        req,
        res,
        render(DOCS.room, {
          id: room.id,
          room: roomUrl,
          status: room.status,
          expires_at: new Date(room.expiresAt).toISOString(),
          participants: people,
          topic,
          max_body: MAX_BODY,
        }),
      );
    }

    if (action === 'join' && method === 'POST') {
      if (room.status === 'closed') throw new HttpError(410, 'room is closed', 'The log is still readable: GET /messages.');
      if (auth(room, req, { required: false })) {
        throw new HttpError(409, 'you are already in this room', 'Use the token you already have.');
      }
      const f = parseFields(await readBody(req), req.headers['content-type'], url.searchParams, { form: true });
      const me = addParticipant(room, cleanHandle(f.handle, 'guest'), 'guest');
      append(room, { kind: 'system', from: null, to: null, reply_to: null, body: `${me.handle} joined` });
      return send(res, 201, { handle: me.handle, token: me.token, role: 'guest', cursor: 0 });
    }

    if (action === 'participants' && method === 'GET') {
      return send(res, 200, {
        participants: [...room.participants.values()].map(({ handle, role, left }) => ({ handle, role, left })),
      });
    }

    if (action === 'messages' && method === 'GET') {
      const me = auth(room, req, { required: false });
      const q = url.searchParams;
      const sel = { handle: me?.handle ?? null, since: Number(q.get('since')) || 0, forMe: q.get('for_me') === '1' };
      const wait = Math.min(Math.max(Number(q.get('wait')) || 0, 0), MAX_WAIT);
      const respond = () => {
        const msgs = select(room, sel);
        // Cursor only advances past what this reader was allowed to see up to.
        const cursor = sel.forMe ? (msgs.at(-1)?.id ?? sel.since) : Math.max(sel.since, room.messages.length);
        const meta = { 'x-room-cursor': String(cursor), 'x-room-status': room.status };
        if (q.get('format') === 'text') return send(res, 200, formatText(room, msgs, cursor), 'text/plain', meta);
        return send(res, 200, { messages: msgs, cursor, status: room.status }, 'application/json', meta);
      };
      if (!wait || room.status === 'closed' || hasNews(room, sel)) return respond();
      const waiter = { ...sel };
      const done = () => {
        clearTimeout(timer);
        room.waiters.delete(waiter);
      };
      waiter.flush = () => (done(), respond());
      const timer = setTimeout(waiter.flush, wait * 1000);
      room.waiters.add(waiter);
      res.on('close', done);
      return;
    }

    if (action === 'messages' && method === 'POST') {
      const me = auth(room, req);
      if (room.status === 'closed') throw new HttpError(410, 'room is closed', 'No more posts. The log is still readable.');
      if (room.messages.length >= MAX_MESSAGES) throw new HttpError(429, 'room is full');
      const raw = await readBody(req);
      const f = parseFields(raw, req.headers['content-type'], url.searchParams);
      const body = (f._json && typeof f.body === 'string' ? f.body : f._json ? '' : raw).trimEnd();
      if (!body.trim()) {
        throw new HttpError(400, 'empty message', 'Send the text as the request body, or JSON {"body": "..."}.');
      }
      for (const token of room.tokens.keys()) {
        if (body.includes(token)) {
          throw new HttpError(400, 'message contains a room token', 'Tokens are secrets; never post them. Nothing was sent.');
        }
      }
      let to = null;
      if (f.to) {
        const target = room.participants.get(cleanHandle(f.to, '').toLowerCase());
        if (!target) {
          const names = [...room.participants.values()].map((p) => p.handle).join(', ');
          throw new HttpError(404, `no participant "${f.to}"`, `Participants: ${names}`);
        }
        to = target.handle;
      }
      const replyTo = f.reply_to ? Number(f.reply_to) : null;
      if (replyTo && !(room.messages[replyTo - 1] && visibleTo(room.messages[replyTo - 1], me.handle))) {
        throw new HttpError(400, `cannot reply to #${replyTo}`, 'No such message visible to you.');
      }
      me.left = false;
      const msg = append(room, { kind: 'message', from: me.handle, to, reply_to: replyTo, body });
      return send(res, 201, { id: msg.id, ts: msg.ts });
    }

    if (action === 'leave' && method === 'POST') {
      const me = auth(room, req);
      if (!me.left && room.status === 'open') {
        me.left = true;
        append(room, { kind: 'system', from: null, to: null, reply_to: null, body: `${me.handle} left` });
      }
      return send(res, 200, { ok: true });
    }

    if (action === 'close' && method === 'POST') {
      const me = auth(room, req);
      if (me.role !== 'host') throw new HttpError(403, 'only the host can close the room', 'You can POST /leave instead.');
      closeRoom(room, `${me.handle} closed the room`);
      return send(res, 200, { ok: true, status: 'closed' });
    }
  }

  throw new HttpError(404, 'not found', `GET ${base}/ explains this service.`);
}

setInterval(() => {
  for (const room of rooms.values()) {
    if (Date.now() < room.expiresAt) continue;
    closeRoom(room, 'room expired');
    rooms.delete(room.id);
  }
}, 30_000).unref();

http
  .createServer((req, res) => {
    handle(req, res).catch((err) => {
      if (!(err instanceof HttpError)) console.error(err);
      if (res.headersSent) return res.end();
      const status = err.status || 500;
      send(res, status, { error: err.status ? err.message : 'internal error', ...(err.hint && { hint: err.hint }) });
    });
  })
  .listen(PORT, () => console.log(`rooms listening on :${PORT}`));
