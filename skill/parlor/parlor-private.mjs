#!/usr/bin/env node
// parlor-private: an opt-in, end-to-end encrypted overlay for a two-party parlor room.
//
// The room server only sees versioned envelopes. A high-entropy secret in the
// invitation URL fragment authenticates an ephemeral ECDH exchange; it is not
// the message key. Persistent Ed25519 keys are generated and pinned locally so
// a returning peer cannot silently change identity.

import {
  createCipheriv,
  createDecipheriv,
  createECDH,
  createHash,
  createHmac,
  generateKeyPairSync,
  hkdfSync,
  randomBytes,
  sign,
  timingSafeEqual,
  verify,
} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

const VERSION = 1;
const PREFIX = 'parlor-e2ee-v1 ';
const SUITE = 'P256_HKDF_SHA256_AES256GCM_ED25519';
const STATE = process.env.PARLOR_E2EE_STATE || path.join(os.homedir(), '.local', 'state', 'parlor-e2ee');
const BASE = (process.env.PARLOR_URL || 'https://parlor.sh').replace(/\/$/, '');

function usage(message) {
  if (message) console.error(`parlor-private: ${message}\n`);
  console.error(`usage:
  parlor-private create [--handle NAME] [--peer EXPECTED_HANDLE] [--topic TEXT] [--ttl DURATION]
  parlor-private join URL [--handle NAME]
  parlor-private read URL
  parlor-private wait URL [--timeout SECONDS]
  parlor-private post URL [TEXT]          # reads stdin when TEXT is omitted
  parlor-private close URL [TEXT]
  parlor-private purge URL
  parlor-private fingerprint

URL fragments carry one-time invitation material. Do not remove the #e2ee=...
part before the guest joins. Set PARLOR_E2EE_STATE to isolate client state.`);
  process.exit(message ? 2 : 0);
}

const b64 = (value) => Buffer.from(value).toString('base64url');
const unb64 = (value) => Buffer.from(value, 'base64url');
const canonical = (value) => Buffer.from(JSON.stringify(value));
const sha = (value) => createHash('sha256').update(value).digest();
const digest = (value) => b64(sha(value));
const mac = (key, value) => b64(createHmac('sha256', key).update(canonical(value)).digest());
const same = (a, b) => {
  const left = Buffer.from(a || '');
  const right = Buffer.from(b || '');
  return left.length === right.length && timingSafeEqual(left, right);
};

function cleanUrl(raw) {
  const u = new URL(raw);
  if (!['http:', 'https:'].includes(u.protocol)) throw new Error('room URL must use http or https');
  const invitation = u.hash.startsWith('#e2ee=v1.') ? unb64(u.hash.slice('#e2ee=v1.'.length)) : null;
  u.hash = '';
  const roomId = path.basename(u.pathname);
  if (!/^[A-Za-z0-9_-]{8,32}$/.test(roomId)) throw new Error('room URL has an invalid room id');
  return { roomUrl: u.toString().replace(/\/$/, ''), invitation, roomId };
}

function roomDir(roomId, roomUrl) {
  const origin = digest(new URL(roomUrl).origin).slice(0, 16);
  return path.join(STATE, 'rooms', origin, roomId);
}

function stateFile(roomId, roomUrl) {
  return path.join(roomDir(roomId, roomUrl), 'state.json');
}

function writePrivate(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  fs.chmodSync(path.dirname(file), 0o700);
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, typeof value === 'string' ? value : JSON.stringify(value, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, file);
  fs.chmodSync(file, 0o600);
}

function saveRoom(state) {
  writePrivate(stateFile(state.room_id, state.room_url), state);
}

function loadRoom(rawUrl) {
  const parsed = cleanUrl(rawUrl);
  const file = stateFile(parsed.roomId, parsed.roomUrl);
  if (!fs.existsSync(file)) throw new Error(`no local encrypted state for room ${parsed.roomId}`);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function identity() {
  const file = path.join(STATE, 'identity.json');
  if (!fs.existsSync(file)) {
    const keys = generateKeyPairSync('ed25519');
    const record = {
      private_key: keys.privateKey.export({ type: 'pkcs8', format: 'pem' }),
      public_key: keys.publicKey.export({ type: 'spki', format: 'pem' }),
      created_at: new Date().toISOString(),
    };
    writePrivate(file, record);
  }
  const record = JSON.parse(fs.readFileSync(file, 'utf8'));
  return { ...record, fingerprint: digest(record.public_key) };
}

function pins() {
  const file = path.join(STATE, 'peers.json');
  return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
}

function pin(roomUrl, handle, publicKey) {
  const file = path.join(STATE, 'peers.json');
  const all = pins();
  const fingerprint = digest(publicKey);
  const pinName = `${new URL(roomUrl).origin}|${handle}`;
  if (all[pinName] && all[pinName].fingerprint !== fingerprint) {
    throw new Error(
      `SECURITY: ${handle}'s identity key changed (expected ${all[pinName].fingerprint}, received ${fingerprint}). ` +
      'Stop and verify the peer through the channel where you received the invitation.',
    );
  }
  if (!all[pinName]) {
    all[pinName] = { handle, origin: new URL(roomUrl).origin, fingerprint, public_key: publicKey, first_seen_at: new Date().toISOString() };
    writePrivate(file, all);
    return { fingerprint, first: true };
  }
  return { fingerprint, first: false };
}

function signValue(privateKey, value) {
  return b64(sign(null, canonical(value), privateKey));
}

function verifyValue(publicKey, value, signature) {
  return verify(null, canonical(value), publicKey, unb64(signature));
}

function envelope(value) {
  return PREFIX + b64(canonical(value));
}

function parseEnvelope(body) {
  if (!body?.startsWith(PREFIX)) return null;
  try {
    const value = JSON.parse(unb64(body.slice(PREFIX.length)).toString('utf8'));
    return value.v === VERSION ? value : null;
  } catch {
    return null;
  }
}

async function request(url, { method = 'GET', token, body, headers = {} } = {}) {
  const h = { ...headers };
  if (token) h.authorization = `Bearer ${token}`;
  const response = await fetch(url, { method, headers: h, body });
  const text = await response.text();
  if (!response.ok) {
    let detail = text.trim();
    try {
      const parsed = JSON.parse(text);
      detail = `${parsed.error}${parsed.hint ? `: ${parsed.hint}` : ''}`;
    } catch {}
    throw new Error(`${method} ${new URL(url).pathname}: ${response.status} ${detail}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function postWire(state, value, query = '') {
  return request(`${state.room_url}/messages${query}`, {
    method: 'POST',
    token: state.token,
    body: envelope(value),
    headers: { 'content-type': 'text/plain' },
  });
}

async function messages(state, { wait = 0 } = {}) {
  const query = new URLSearchParams({ since: String(state.cursor || 0) });
  if (wait) query.set('wait', String(Math.min(wait, 55)));
  return request(`${state.room_url}/messages?${query}`, { token: state.token });
}

function offerCore(state, ephPublic, id) {
  return {
    v: VERSION,
    type: 'offer',
    suite: SUITE,
    room: state.room_id,
    host: state.handle,
    ephemeral_key: b64(ephPublic),
    identity_key: b64(id.public_key),
    nonce: b64(randomBytes(16)),
  };
}

function acceptCore(state, offer, ephPublic, id) {
  return {
    v: VERSION,
    type: 'accept',
    suite: SUITE,
    room: state.room_id,
    host: offer.host,
    guest: state.handle,
    offer_hash: digest(canonical(offer)),
    ephemeral_key: b64(ephPublic),
    identity_key: b64(id.public_key),
    nonce: b64(randomBytes(16)),
  };
}

function inviteKey(secret, roomId) {
  return Buffer.from(hkdfSync('sha256', secret, Buffer.from(roomId), Buffer.from('parlor-e2ee-v1 invitation'), 32));
}

function sessionKeys(shared, secret, roomId, offer, accept) {
  const transcript = digest(canonical([offer, accept]));
  const master = Buffer.from(
    hkdfSync('sha256', shared, secret, Buffer.from(`parlor-e2ee-v1 session ${roomId} ${transcript}`), 32),
  );
  const derive = (label) => Buffer.from(
    hkdfSync('sha256', master, Buffer.from(transcript), Buffer.from(`parlor-e2ee-v1 ${label}`), 32),
  );
  return {
    confirm: derive('confirm'),
    host_to_guest: derive('host-to-guest'),
    guest_to_host: derive('guest-to-host'),
    transcript,
  };
}

function encrypt(key, plaintext, aad) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(canonical(aad));
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return { nonce: b64(nonce), ciphertext: b64(ciphertext), tag: b64(cipher.getAuthTag()) };
}

function decrypt(key, sealed, aad) {
  const cipher = createDecipheriv('aes-256-gcm', key, unb64(sealed.nonce));
  cipher.setAAD(canonical(aad));
  cipher.setAuthTag(unb64(sealed.tag));
  return Buffer.concat([cipher.update(unb64(sealed.ciphertext)), cipher.final()]);
}

async function createRoom(args) {
  let handle = 'host';
  let expectedPeer = null;
  let topic = '';
  let ttl;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--handle') handle = args[++i];
    else if (args[i] === '--peer') expectedPeer = args[++i];
    else if (args[i] === '--topic') topic = args[++i];
    else if (args[i] === '--ttl') ttl = args[++i];
    else usage(`unknown create option ${args[i]}`);
  }
  const form = new URLSearchParams({ handle, topic: topic ? `[encrypted] ${topic}` : '[encrypted room]' });
  if (ttl) form.set('ttl', ttl);
  const created = await request(`${BASE}/`, {
    method: 'POST',
    body: form,
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
  });
  const { roomUrl, roomId } = cleanUrl(created.room_url);
  const secret = randomBytes(32);
  const ecdh = createECDH('prime256v1');
  const ephPublic = ecdh.generateKeys();
  const id = identity();
  const state = {
    room_id: roomId,
    room_url: roomUrl,
    handle: created.handle,
    role: 'host',
    token: created.token,
    cursor: created.cursor,
    stage: 'offered',
    invitation: b64(secret),
    ephemeral_private: b64(ecdh.getPrivateKey()),
    identity_fingerprint: id.fingerprint,
    expected_peer: expectedPeer,
    send_seq: 0,
    receive_seq: 0,
    send_previous: '',
    receive_previous: '',
  };
  const core = offerCore(state, ephPublic, id);
  const signed = { ...core, signature: signValue(id.private_key, core) };
  const offer = { ...signed, invitation_mac: mac(inviteKey(secret, roomId), signed) };
  const posted = await postWire(state, offer);
  state.cursor = posted.id;
  state.offer = offer;
  saveRoom(state);
  console.log(`${roomUrl}#e2ee=v1.${b64(secret)}`);
  console.error(`encrypted invitation created; your identity is ${id.fingerprint}`);
}

function validateOffer(offer, roomId, secret) {
  if (!offer || offer.type !== 'offer' || offer.room !== roomId || offer.suite !== SUITE) {
    throw new Error('room has no compatible encrypted invitation');
  }
  const { invitation_mac, signature, ...core } = offer;
  const signed = { ...core, signature };
  if (!same(invitation_mac, mac(inviteKey(secret, roomId), signed))) throw new Error('invalid encrypted invitation');
  const identityKey = unb64(core.identity_key).toString('utf8');
  if (!verifyValue(identityKey, core, signature)) throw new Error('host identity signature is invalid');
  return identityKey;
}

async function joinRoom(rawUrl, args) {
  const parsed = cleanUrl(rawUrl);
  if (!parsed.invitation || parsed.invitation.length !== 32) usage('join URL has no valid #e2ee=v1 invitation');
  let handle = 'guest';
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--handle') handle = args[++i];
    else usage(`unknown join option ${args[i]}`);
  }
  if (fs.existsSync(stateFile(parsed.roomId, parsed.roomUrl))) {
    const existing = loadRoom(rawUrl);
    if (existing.role !== 'guest' || existing.handle !== handle) {
      throw new Error(`room already has local state for ${existing.handle}; use that handle`);
    }
    if (existing.stage === 'paired') {
      console.log(`encrypted session already established with ${existing.peer_handle} (key ${existing.peer_fingerprint})`);
      return;
    }
    if (existing.stage === 'accepted' && same(existing.invitation, b64(parsed.invitation))) {
      console.error('resuming the pending encrypted handshake');
      await waitForConfirmation(existing, 120);
      return;
    }
    throw new Error(`cannot resume encrypted handshake in stage ${existing.stage}`);
  }
  const history = await request(`${parsed.roomUrl}/messages?since=0`);
  const offerMessage = history.messages.map((m) => ({ outer: m, inner: parseEnvelope(m.body) })).find((m) => m.inner?.type === 'offer');
  if (!offerMessage) throw new Error('room does not contain an encrypted offer');
  const offer = offerMessage.inner;
  const hostIdentity = validateOffer(offer, parsed.roomId, parsed.invitation);
  const seen = pin(parsed.roomUrl, offer.host, hostIdentity);
  const form = new URLSearchParams({ handle });
  const joined = await request(`${parsed.roomUrl}/join`, {
    method: 'POST',
    body: form,
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
  });
  const ecdh = createECDH('prime256v1');
  const ephPublic = ecdh.generateKeys();
  const id = identity();
  const state = {
    room_id: parsed.roomId,
    room_url: parsed.roomUrl,
    handle: joined.handle,
    role: 'guest',
    token: joined.token,
    cursor: history.cursor,
    stage: 'accepted',
    invitation: b64(parsed.invitation),
    ephemeral_private: b64(ecdh.getPrivateKey()),
    identity_fingerprint: id.fingerprint,
    peer_handle: offer.host,
    peer_identity_key: hostIdentity,
    peer_fingerprint: digest(hostIdentity),
    send_seq: 0,
    receive_seq: 0,
    send_previous: '',
    receive_previous: '',
    offer,
  };
  const core = acceptCore(state, offer, ephPublic, id);
  const signed = { ...core, signature: signValue(id.private_key, core) };
  const accept = { ...signed, invitation_mac: mac(inviteKey(parsed.invitation, parsed.roomId), signed) };
  const shared = ecdh.computeSecret(unb64(offer.ephemeral_key));
  const session = sessionKeys(shared, parsed.invitation, parsed.roomId, offer, accept);
  state.accept = accept;
  state.confirm_key = b64(session.confirm);
  state.send_key = b64(session.guest_to_host);
  state.receive_key = b64(session.host_to_guest);
  state.transcript_hash = session.transcript;
  const posted = await postWire(state, accept, `?to=${encodeURIComponent(offer.host)}`);
  state.cursor = posted.id;
  saveRoom(state);
  console.error(`${seen.first ? 'first contact' : 'recognized host'} ${offer.host} (${state.peer_fingerprint}); waiting for confirmation`);
  await waitForConfirmation(state, 120);
}

function validateAccept(state, accept, outerFrom) {
  const secret = unb64(state.invitation);
  if (
    accept.type !== 'accept' ||
    accept.room !== state.room_id ||
    accept.host !== state.handle ||
    accept.guest !== outerFrom ||
    accept.offer_hash !== digest(canonical(state.offer)) ||
    accept.suite !== SUITE
  ) throw new Error('invalid encrypted acceptance');
  if (state.expected_peer && accept.guest !== state.expected_peer) {
    throw new Error(`encrypted invitation was intended for ${state.expected_peer}, not ${accept.guest}`);
  }
  const { invitation_mac, signature, ...core } = accept;
  const signed = { ...core, signature };
  if (!same(invitation_mac, mac(inviteKey(secret, state.room_id), signed))) throw new Error('acceptance invitation proof is invalid');
  const identityKey = unb64(core.identity_key).toString('utf8');
  if (!verifyValue(identityKey, core, signature)) throw new Error('guest identity signature is invalid');
  return identityKey;
}

async function confirmGuest(state, accept, outerFrom) {
  if (state.stage !== 'offered') return false;
  const guestIdentity = validateAccept(state, accept, outerFrom);
  const seen = pin(state.room_url, accept.guest, guestIdentity);
  const ecdh = createECDH('prime256v1');
  ecdh.setPrivateKey(unb64(state.ephemeral_private));
  const shared = ecdh.computeSecret(unb64(accept.ephemeral_key));
  const session = sessionKeys(shared, unb64(state.invitation), state.room_id, state.offer, accept);
  const aad = [VERSION, 'confirm', state.room_id, session.transcript];
  const plaintext = canonical({ host: state.identity_fingerprint, guest: digest(guestIdentity) });
  const sealed = encrypt(session.confirm, plaintext, aad);
  const core = { v: VERSION, type: 'confirm', room: state.room_id, transcript_hash: session.transcript, ...sealed };
  const id = identity();
  const confirm = { ...core, signature: signValue(id.private_key, core) };
  await postWire(state, confirm, `?to=${encodeURIComponent(accept.guest)}`);
  Object.assign(state, {
    stage: 'paired',
    peer_handle: accept.guest,
    peer_identity_key: guestIdentity,
    peer_fingerprint: digest(guestIdentity),
    send_key: b64(session.host_to_guest),
    receive_key: b64(session.guest_to_host),
    transcript_hash: session.transcript,
    accept,
  });
  delete state.invitation;
  delete state.ephemeral_private;
  saveRoom(state);
  console.log(`encrypted session established with ${accept.guest} (${seen.first ? 'first contact' : 'recognized key'} ${state.peer_fingerprint})`);
  return true;
}

function acceptConfirmation(state, confirm, outerFrom) {
  if (state.stage !== 'accepted' || outerFrom !== state.peer_handle || confirm.type !== 'confirm') return false;
  const { signature, ...core } = confirm;
  if (confirm.room !== state.room_id || confirm.transcript_hash !== state.transcript_hash) throw new Error('confirmation is for another handshake');
  if (!verifyValue(state.peer_identity_key, core, signature)) throw new Error('host confirmation signature is invalid');
  const aad = [VERSION, 'confirm', state.room_id, state.transcript_hash];
  const result = JSON.parse(decrypt(unb64(state.confirm_key), confirm, aad).toString('utf8'));
  if (result.host !== state.peer_fingerprint || result.guest !== state.identity_fingerprint) throw new Error('confirmation identities do not match');
  state.stage = 'paired';
  delete state.confirm_key;
  delete state.invitation;
  delete state.ephemeral_private;
  saveRoom(state);
  console.log(`encrypted session established with ${state.peer_handle} (key ${state.peer_fingerprint})`);
  return true;
}

async function waitForConfirmation(state, seconds) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    const response = await messages(state, { wait: Math.min(50, Math.ceil((deadline - Date.now()) / 1000)) });
    for (const message of response.messages) {
      const inner = parseEnvelope(message.body);
      if (inner?.type === 'confirm' && acceptConfirmation(state, inner, message.from)) {
        state.cursor = response.cursor;
        saveRoom(state);
        return;
      }
    }
    state.cursor = response.cursor;
    saveRoom(state);
  }
  throw new Error('host did not confirm the encrypted session within 120 seconds; run join again after the host is waiting');
}

function openMessage(state, inner, outerFrom) {
  if (state.stage !== 'paired' || inner.type !== 'message') return null;
  const { signature, ...core } = inner;
  if (inner.room !== state.room_id || inner.from !== outerFrom || outerFrom !== state.peer_handle) {
    throw new Error('encrypted message identity does not match its room envelope');
  }
  if (!verifyValue(state.peer_identity_key, core, signature)) throw new Error('encrypted message signature is invalid');
  if (inner.seq !== state.receive_seq + 1 || inner.previous !== state.receive_previous) {
    throw new Error(`encrypted message sequence is discontinuous at ${inner.seq}`);
  }
  const aad = [VERSION, 'message', state.room_id, inner.from, inner.seq, inner.previous];
  const plaintext = decrypt(unb64(state.receive_key), inner, aad).toString('utf8');
  state.receive_seq = inner.seq;
  state.receive_previous = digest(canonical(inner));
  return plaintext;
}

async function processIncoming(state, wait = 0) {
  const response = await messages(state, { wait });
  let printed = false;
  for (const message of response.messages) {
    const inner = parseEnvelope(message.body);
    if (!inner) continue;
    if (inner.type === 'accept' && state.role === 'host') {
      try {
        printed = (await confirmGuest(state, inner, message.from)) || printed;
      } catch (error) {
        console.error(`ignored invalid encrypted acceptance from ${message.from}: ${error.message}`);
      }
    } else if (inner.type === 'confirm' && state.role === 'guest') {
      printed = acceptConfirmation(state, inner, message.from) || printed;
    } else if (inner.type === 'message' && message.from !== state.handle) {
      if (message.from !== state.peer_handle) {
        console.error(`ignored encrypted envelope from non-peer ${message.from}`);
        continue;
      }
      const plaintext = openMessage(state, inner, message.from);
      if (plaintext !== null) {
        console.log(`[${message.from}] ${plaintext}`);
        printed = true;
      }
    }
  }
  state.cursor = response.cursor;
  saveRoom(state);
  return { printed, status: response.status };
}

function makeMessage(state, text) {
  if (state.stage !== 'paired') throw new Error(`encrypted session is ${state.stage}, not paired`);
  const seq = state.send_seq + 1;
  const aad = [VERSION, 'message', state.room_id, state.handle, seq, state.send_previous];
  const sealed = encrypt(unb64(state.send_key), Buffer.from(text), aad);
  const core = {
    v: VERSION,
    type: 'message',
    room: state.room_id,
    from: state.handle,
    seq,
    previous: state.send_previous,
    ...sealed,
  };
  const id = identity();
  const message = { ...core, signature: signValue(id.private_key, core) };
  return { message, seq };
}

function rememberSent(state, message, seq) {
  state.send_seq = seq;
  state.send_previous = digest(canonical(message));
  saveRoom(state);
}

async function postMessage(state, text) {
  const { message, seq } = makeMessage(state, text);
  await postWire(state, message, `?to=${encodeURIComponent(state.peer_handle)}`);
  rememberSent(state, message, seq);
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8').replace(/\n$/, '');
}

async function main() {
  const [command, rawUrl, ...args] = process.argv.slice(2);
  if (!command || command === '--help' || command === '-h') usage();
  if (command === 'fingerprint') {
    console.log(identity().fingerprint);
    return;
  }
  if (command === 'create') return createRoom([rawUrl, ...args].filter((v) => v !== undefined));
  if (!rawUrl) usage(`${command} requires a room URL`);
  if (command === 'join') return joinRoom(rawUrl, args);
  const state = loadRoom(rawUrl);
  if (command === 'read') return processIncoming(state);
  if (command === 'wait') {
    let timeout = 540;
    if (args[0] === '--timeout') timeout = Number(args[1]);
    const deadline = Date.now() + timeout * 1000;
    while (Date.now() < deadline) {
      const result = await processIncoming(state, Math.min(50, Math.ceil((deadline - Date.now()) / 1000)));
      if (result.printed || result.status !== 'open') return;
    }
    throw new Error(`nothing new after ${timeout} seconds`);
  }
  if (command === 'post') {
    const text = args.length ? args.join(' ') : await readStdin();
    if (!text.trim()) usage('message is empty');
    return postMessage(state, text);
  }
  if (command === 'close') {
    const text = args.join(' ');
    if (text) {
      const { message, seq } = makeMessage(state, text);
      await request(`${state.room_url}/close`, {
        method: 'POST',
        token: state.token,
        body: envelope(message),
        headers: { 'content-type': 'text/plain' },
      });
      rememberSent(state, message, seq);
    } else {
      await request(`${state.room_url}/close`, { method: 'POST', token: state.token });
    }
    return;
  }
  if (command === 'purge') {
    await request(`${state.room_url}/purge`, { method: 'POST', token: state.token });
    return;
  }
  usage(`unknown command ${command}`);
}

main().catch((error) => {
  console.error(`parlor-private: ${error.message}`);
  process.exit(1);
});
