#!/usr/bin/env python3
"""Two implementations, the same requests, byte-for-byte the same answers?

The conformance suite checks what the contract promises; this checks everything else a client
could notice: exact error texts, odd inputs, header sets, page bytes. It starts both commands
(from the repo root, like the suite), plays one scenario against each, and prints every response
that differs once room ids, tokens, times and ports are masked.

usage:
  tests/conformance/compare.py "node server.mjs" "sh gleam/build/erlang-shipment/entrypoint.sh run"
"""
import http.client, json, os, re, shlex, signal, socket, subprocess, sys, tempfile, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
IGNORED = {'date', 'connection', 'keep-alive', 'content-length', 'transfer-encoding'}
ENV = {'MAX_ROOM_BYTES': '4000', 'MAX_MESSAGES': '12', 'MAX_BODY': '300', 'MAX_PARTICIPANTS': '9',
       'RATE_POST': '50', 'RATE_CREATE': '100', 'TTL_MIN': '60', 'TTL_MAX': '7d'}


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class Side:
    def __init__(self, cmd):
        self.port, self.data = free_port(), tempfile.mkdtemp(prefix='parlor-compare-')
        env = {**os.environ, **ENV, 'PORT': str(self.port), 'HOST': '127.0.0.1', 'DATA_DIR': self.data}
        env.pop('PUBLIC_URL', None)
        self.proc = subprocess.Popen(shlex.split(cmd), cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.names = {}  # real id or token -> placeholder
        for _ in range(100):
            try:
                self.raw('GET', '/', None, {})
                return
            except OSError:
                time.sleep(0.1)
        raise RuntimeError(f'{cmd} did not come up')

    def raw(self, method, path, body, headers):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=30)
        try:
            conn.putrequest(method, path, skip_accept_encoding=True)
            for k, v in headers.items():
                conn.putheader(k, v)
            if body is not None and 'Transfer-Encoding' not in headers:
                conn.putheader('Content-Length', str(len(body)))
            conn.endheaders()
            if body is not None:
                if headers.get('Transfer-Encoding') == 'chunked':
                    for i in range(0, len(body), 7):
                        part = body[i:i + 7]
                        conn.send(b'%x\r\n%s\r\n' % (len(part), part))
                    conn.send(b'0\r\n\r\n')
                else:
                    conn.send(body)
            r = conn.getresponse()
            return r.status, [(k.lower(), v) for k, v in r.getheaders()], r.read()
        finally:
            conn.close()

    def name(self, real, kind):
        if real not in self.names:
            self.names[real] = f'<{kind}{sum(1 for v in self.names.values() if v.startswith("<" + kind))}>'
        return self.names[real]

    def learn(self, body):
        """Give every room id and token in a response a placeholder, in order of appearance."""
        try:
            obj = json.loads(body)
        except Exception:
            return
        if isinstance(obj, dict):
            if 'room_url' in obj:
                self.name(obj['room_url'].rsplit('/', 1)[1], 'room')
            if 'token' in obj:
                self.name(obj['token'], 'token')

    def mask(self, text):
        for real, fake in sorted(self.names.items(), key=lambda kv: -len(kv[0])):
            text = text.replace(real, fake)
        text = text.replace(f'127.0.0.1:{self.port}', 'HOST').replace(f'localhost:{self.port}', 'HOST')
        text = re.sub(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z', 'TIME', text)
        text = re.sub(r'(\[#\d+ )\d\d:\d\d:\d\d\]', r'\1HH:MM:SS]', text)
        text = re.sub(r'#(\d+) · \d\d:\d\d:\d\d UTC', r'#\1 · HH:MM:SS UTC', text)
        text = re.sub(r'Try again in \d+ s', 'Try again in N s', text)
        return text

    def stop(self):
        self.proc.send_signal(signal.SIGTERM)
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def scenario(do):
    """Requests; `do` returns the parsed JSON (or None). {room}, {tok} etc. are filled per side."""
    J = {'Content-Type': 'application/json'}
    F = {'Content-Type': 'application/x-www-form-urlencoded'}
    T = {'Content-Type': 'text/plain'}
    H = {'Accept': 'text/html'}
    # The service's own pages.
    for path in ('/', '/example', '/cli', '/nope', '/r', '/r/', '/r/short', '/r/AAAAAAAAAAAAAAAA', '/r/%2e%2e/logs',
                 '/example/join', '/?x=1', '//', '/r//x', '//x', '//example', '/./example', '/r/../example'):
        do('GET', path)
        do('GET', path, headers=H)
    do('HEAD', '/')
    do('PUT', '/')
    do('DELETE', '/r/AAAAAAAAAAAAAAAA')
    # Creating, in every encoding an agent tries.
    do('POST', '/', b'handle=maker&topic=line+one%0Aline+two+%3Cb%3E', F, keep='a')
    do('POST', '/', b'{"handle": "jsonmaker", "topic": 42, "ttl": "90m"}', J, keep='b')
    do('POST', '/?handle=q&ttl=2h&topic=t', None, keep='c')
    do('POST', '/', b'{"handle": null, "topic": ["x", 1, true, null], "ttl": 7200}', J, keep='d')
    do('POST', '/', b'{"handle": 12.0, "ttl": 1e9}', J, keep='e')
    do('POST', '/', b'{"handle": "x", "idle": "3d"}', J, keep='f')
    do('POST', '/', b'   {"handle": "sneaky"}', F, keep='g')
    do('POST', '/', b'{"handle": "\xff\xfe bad utf8"}', J, keep='h')
    do('POST', '/', b'{broken', J)
    do('POST', '/', b'{broken', T, keep='i')
    do('POST', '/', b'handle=x&ttl=soon', F)
    do('POST', '/', b'handle=x&ttl=', F)
    do('POST', '/', b'handle=x&ttl=5', F, keep='j')
    do('POST', '/', b'handle=%E2%9C%A8+sparkle+%F0%9F%98%80+%zz', F, keep='k')
    do('POST', '/', b'x' * 400, T)
    do('POST', '/', b'handle=chunky&topic=' + b'y' * 50, {**F, 'Transfer-Encoding': 'chunked'}, keep='l')
    do('POST', '/', b'"just a string"', J, keep='m')
    do('POST', '/', b'[1, 2]', J, keep='n')
    do('POST', '/', b'topic=' + ('é' * 1990 + '😀😀😀').encode(), F, keep='o')
    # One room, through its whole life.
    room = '/r/{a}'
    for h in ({}, H):
        do('GET', room, headers=h)
    do('GET', room + '/participants')
    do('POST', room + '/join', b'handle=@Guest One!', F, keep='g1')
    do('POST', room + '/join', b'{"handle": "GUEST-one-"}', J, keep='g2')
    do('POST', room + '/join?handle=' + 'z' * 40, None, keep='g3')
    do('POST', room + '/join', b'handle=%F0%9F%98%80emoji', F, keep='g4')
    do('POST', room + '/join', b'', F, keep='g5')
    do('POST', room + '/join', b'handle=again', F, auth='{a.tok}')
    do('POST', room + '/join', b'handle=wrongtoken', F, auth='nonsense')
    do('POST', room + '/messages', b'hello @Guest-One- and @guest-one-. and x@guest-one- ', T, auth='{a.tok}')
    do('POST', room + '/messages', b'{"body": "json body\\nsecond line", "to": "maker", "reply_to": 2}', J, auth='{g1.tok}')
    do('POST', room + '/messages?to=nobody', b'to nobody', T, auth='{g1.tok}')
    do('POST', room + '/messages?to=', b'empty to', T, auth='{g1.tok}')
    for r in ('0', 'abc', '1.5', '99', '-1', '3'):
        do('POST', room + '/messages?reply_to=' + r, b'reply ' + r.encode(), T, auth='{g2.tok}')
    do('POST', room + '/messages', b'{"body": 5}', J, auth='{g2.tok}')
    do('POST', room + '/messages', b'{"text": "wrong field"}', J, auth='{g2.tok}')
    do('POST', room + '/messages', b'   \n\t ', T, auth='{g2.tok}')
    do('POST', room + '/messages', b'{"body": "x"', J, auth='{g2.tok}')
    do('POST', room + '/messages', b'{"body": "x"', T, auth='{g2.tok}')
    do('POST', room + '/messages', b'bad \xc3\x28 utf8 \xe2\x82 end \xf0\x9f\x98', T, auth='{g2.tok}')
    do('POST', room + '/messages', b'w' * 301, T, auth='{g2.tok}')
    do('POST', room + '/messages', b'my token {g2.tok} oops', T, auth='{g2.tok}')
    do('POST', room + '/messages', b'no auth', T)
    do('POST', room + '/messages', b'bad auth', T, auth='nope')
    do('POST', room + '/messages', b'lower bearer', T, raw_auth='bearer {g2.tok}')
    do('POST', room + '/messages', b'extra space', T, raw_auth='Bearer   {g2.tok}')
    do('POST', room + '/messages', b'trailing', T, raw_auth='Bearer {g2.tok} x')
    do('POST', room + '/messages', b'@maker ping', T, auth='{g3.tok}')
    for q in ('since=0', 'since=0&format=text', 'since=3&format=text', 'since=abc', 'since=-5&format=text',
              'since=2.7&format=text', 'since=999&format=text', 'since=0&for_me=1&format=text', 'since=0&for_me=1',
              'since=0&for_me=true'):
        do('GET', room + '/messages?' + q, auth='{a.tok}')
        do('GET', room + '/messages?' + q, auth='{g1.tok}')
        do('GET', room + '/messages?' + q)
    do('GET', room + '/messages?since=0&wait=0.2&format=text', auth='{a.tok}')
    for q in ('', '?format=jsonl', '?format=text', '?format=other'):
        do('GET', room + '/logs' + q)
        do('GET', room + '/logs' + q, headers=H)
    do('GET', room + '/logs', headers={'Accept': 'application/x-ndjson'})
    do('GET', room + '/logs/extra')
    do('GET', room + '/participants')
    do('GET', room + '/join')
    do('POST', room + '/nothing')
    do('POST', room + '/leave', auth='{g3.tok}')
    do('POST', room + '/leave', auth='{g3.tok}')
    do('GET', room + '/participants')
    do('POST', room + '/messages', b'back again', T, auth='{g3.tok}')
    do('POST', room + '/close', b'not the host', T, auth='{g1.tok}')
    do('POST', room + '/purge', auth='{g1.tok}')
    for h in ({}, H):
        do('GET', room, headers=h)
    # Filling a room: 12 messages, one held back for the host.
    full = '/r/{c}'
    for i in range(12):
        do('POST', full + '/messages', f'message {i} '.encode() + b'.' * 200, T, auth='{c.tok}')
        do('GET', full + '/messages?since=0&format=text', auth='{c.tok}')
    do('GET', full)
    do('POST', full + '/close', b'{"body": "continued at elsewhere"}', J, auth='{c.tok}')
    do('POST', full + '/close', b'again', T, auth='{c.tok}')
    do('GET', full + '/messages?since=0&format=text')
    for h in ({}, H):
        do('GET', full, headers=h)
    do('POST', full + '/join', b'handle=late', F)
    do('POST', full + '/messages', b'late', T, auth='{c.tok}')
    do('POST', full + '/leave', auth='{c.tok}')
    do('POST', '/r/{d}/close', b'w' * 301, T, auth='{d.tok}')
    do('POST', '/r/{d}/close', b'last word with {d.tok}', T, auth='{d.tok}')
    do('POST', '/r/{d}/close', b'   ', T, auth='{d.tok}')
    # Purged: the notice, and 410 for everything else.
    gone = '/r/{b}'
    do('POST', gone + '/purge', auth='{b.tok}')
    for path in ('', '/logs', '/logs?format=jsonl', '/messages?since=0', '/participants', '/whatever'):
        do('GET', gone + path)
        do('GET', gone + path, headers=H)
    for path in ('/join', '/messages', '/leave', '/close', '/purge', '/whatever'):
        do('POST', gone + path, b'x', T, auth='{b.tok}')


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    a, b = Side(sys.argv[1]), Side(sys.argv[2])
    kept = {a: {}, b: {}}
    results = {a: [], b: []}
    try:
        for side in (a, b):
            def fill(s):
                def sub(m):
                    key, _, field = m.group(1).partition('.')
                    obj = kept[side].get(key, {})
                    if field == 'tok':
                        return obj.get('token', 'missing')
                    return obj.get('room_url', '/r/missing').rsplit('/', 1)[1]
                return re.sub(r'\{(\w+(?:\.tok)?)\}', sub, s)

            def do(method, path, body=None, headers=None, auth=None, raw_auth=None, keep=None):
                h = dict(headers or {})
                if auth:
                    h['Authorization'] = 'Bearer ' + fill(auth)
                if raw_auth:
                    h['Authorization'] = fill(raw_auth)
                if body is not None:
                    body = fill(body.decode('latin-1')).encode('latin-1')
                status, hdrs, data = side.raw(method, fill(path), body, h)
                side.learn(data)
                if keep:
                    try:
                        kept[side][keep] = json.loads(data)
                    except Exception:
                        pass
                shown = sorted((k, side.mask(v)) for k, v in hdrs if k not in IGNORED)
                results[side].append((f'{method} {path} {body[:60] if body else ""}', status, shown, side.mask(data.decode('utf-8', 'replace'))))
            scenario(do)
    finally:
        a.stop()
        b.stop()
    diffs = 0
    for (req, sa, ha, ba), (_, sb, hb, bb) in zip(results[a], results[b]):
        if (sa, ha, ba) != (sb, hb, bb):
            diffs += 1
            print(f'--- {req}')
            if sa != sb:
                print(f'    status: {sa} vs {sb}')
            if ha != hb:
                print(f'    headers only in A: {sorted(set(ha) - set(hb))}\n    headers only in B: {sorted(set(hb) - set(ha))}')
            if ba != bb:
                la, lb = ba.split('\n'), bb.split('\n')
                for i, (x, y) in enumerate(zip(la, lb)):
                    if x != y:
                        print(f'    body line {i + 1}:\n      A {x[:300]!r}\n      B {y[:300]!r}')
                        break
                else:
                    print(f'    body lengths: {len(la)} vs {len(lb)} lines')
    print(f'{len(results[a])} requests, {diffs} differ')
    sys.exit(1 if diffs else 0)


if __name__ == '__main__':
    main()
