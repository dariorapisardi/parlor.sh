#!/usr/bin/env node
// End-to-end check for the optional encrypted-room client. Node standard library only.

import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..');
const CLIENT = path.join(ROOT, 'skill', 'parlor', 'parlor-private.mjs');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'parlor-e2ee-test-'));

const reservePort = () => new Promise((resolve, reject) => {
  const socket = net.createServer();
  socket.on('error', reject);
  socket.listen(0, '127.0.0.1', () => {
    const { port } = socket.address();
    socket.close(() => resolve(port));
  });
});

const port = await reservePort();
const base = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['server.mjs'], {
  cwd: ROOT,
  env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', PUBLIC_URL: base, DATA_DIR: path.join(scratch, 'data') },
  stdio: ['ignore', 'pipe', 'pipe'],
});

const hostState = path.join(scratch, 'host');
const guestState = path.join(scratch, 'guest');
const readRoomState = (stateRoot, roomId) => {
  const rooms = path.join(stateRoot, 'rooms');
  const origin = fs.readdirSync(rooms)[0];
  return JSON.parse(fs.readFileSync(path.join(rooms, origin, roomId, 'state.json')));
};
const client = (state, args, options = {}) => {
  const result = spawnSync(process.execPath, [CLIENT, ...args], {
    cwd: ROOT,
    env: { ...process.env, PARLOR_URL: base, PARLOR_E2EE_STATE: state },
    encoding: 'utf8',
    timeout: options.timeout || 15_000,
    input: options.input,
  });
  if (!options.failure && result.status !== 0) {
    throw new Error(`client ${args[0]} failed (${result.status}): ${result.stderr || result.stdout}`);
  }
  return result;
};

const waitForServer = async () => {
  for (let i = 0; i < 50; i++) {
    try {
      const response = await fetch(base);
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('server did not start');
};

try {
  await waitForServer();

  const created = client(hostState, ['create', '--handle', 'alice', '--peer', 'bob', '--topic', 'public label only']);
  const inviteUrl = created.stdout.trim();
  assert.match(inviteUrl, /#e2ee=v1\.[A-Za-z0-9_-]{43}$/);
  const roomUrl = inviteUrl.split('#')[0];
  const inviteSecret = inviteUrl.split('v1.')[1];
  const roomId = roomUrl.split('/').at(-1);

  // A link-only participant cannot wedge the host by posting something shaped like a handshake.
  const intruderJoin = await fetch(`${roomUrl}/join?handle=mallory`, { method: 'POST' });
  const intruder = await intruderJoin.json();
  const bogus = `parlor-e2ee-v1 ${Buffer.from(JSON.stringify({ v: 1, type: 'accept' })).toString('base64url')}`;
  const intruderPost = await fetch(`${roomUrl}/messages`, {
    method: 'POST',
    headers: { authorization: `Bearer ${intruder.token}`, 'content-type': 'text/plain' },
    body: bogus,
  });
  assert.equal(intruderPost.status, 201);

  const hostWait = spawn(process.execPath, [CLIENT, 'wait', roomUrl, '--timeout', '15'], {
    cwd: ROOT,
    env: { ...process.env, PARLOR_E2EE_STATE: hostState },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const joined = client(guestState, ['join', inviteUrl, '--handle', 'bob'], { timeout: 20_000 });
  assert.match(joined.stdout, /encrypted session established with alice/);
  const hostOutput = await new Promise((resolve, reject) => {
    let stdout = '', stderr = '';
    hostWait.stdout.on('data', (chunk) => (stdout += chunk));
    hostWait.stderr.on('data', (chunk) => (stderr += chunk));
    hostWait.on('error', reject);
    hostWait.on('close', (code) => code === 0 ? resolve(stdout) : reject(new Error(stderr)));
  });
  assert.match(hostOutput, /encrypted session established with bob/);

  client(hostState, ['post', roomUrl, 'the launch code is orchid']);
  client(guestState, ['post', roomUrl, 'received securely']);
  assert.match(client(hostState, ['read', roomUrl]).stdout, /\[bob\] received securely/);
  assert.match(client(guestState, ['read', roomUrl]).stdout, /\[alice\] the launch code is orchid/);

  const rawLog = await (await fetch(`${roomUrl}/logs?format=jsonl`)).text();
  assert.equal(rawLog.includes('the launch code is orchid'), false, 'server log contains host plaintext');
  assert.equal(rawLog.includes('received securely'), false, 'server log contains guest plaintext');
  assert.equal(rawLog.includes(inviteSecret), false, 'server log contains invitation secret');

  for (const stateRoot of [hostState, guestState]) {
    const state = readRoomState(stateRoot, roomId);
    assert.equal(state.stage, 'paired');
    assert.equal('invitation' in state, false, 'paired client retained invitation secret');
    assert.equal('ephemeral_private' in state, false, 'paired client retained ephemeral private key');
  }

  // The relay can alter a stored envelope, but the receiving client must not release plaintext.
  const lines = rawLog.trim().split('\n').map((line) => JSON.parse(line));
  const guestWire = lines.slice().reverse().find((message) => message.from === 'bob' && message.body.startsWith('parlor-e2ee-v1 '));
  const inner = JSON.parse(Buffer.from(guestWire.body.slice('parlor-e2ee-v1 '.length), 'base64url').toString('utf8'));
  inner.ciphertext = `${inner.ciphertext[0] === 'A' ? 'B' : 'A'}${inner.ciphertext.slice(1)}`;
  const alteredBody = `parlor-e2ee-v1 ${Buffer.from(JSON.stringify(inner)).toString('base64url')}`;
  const guestRoomState = readRoomState(guestState, roomId);
  const altered = await fetch(`${roomUrl}/messages?to=alice`, {
    method: 'POST',
    headers: { authorization: `Bearer ${guestRoomState.token}`, 'content-type': 'text/plain' },
    body: alteredBody,
  });
  assert.equal(altered.status, 201);
  const rejected = client(hostState, ['read', roomUrl], { failure: true });
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /encrypted message signature is invalid/);

  // A returning handle with a different identity key is rejected before it joins.
  const replacementHost = path.join(scratch, 'replacement-host');
  const replacement = client(replacementHost, ['create', '--handle', 'alice']);
  const changed = client(guestState, ['join', replacement.stdout.trim(), '--handle', 'bob'], { failure: true });
  assert.notEqual(changed.status, 0);
  assert.match(changed.stderr, /SECURITY: alice's identity key changed/);

  console.log('ok encrypted handshake, ciphertext transport, secret erasure, decryption, tamper rejection, and key continuity');
} finally {
  server.kill('SIGTERM');
  fs.rmSync(scratch, { recursive: true, force: true });
}
