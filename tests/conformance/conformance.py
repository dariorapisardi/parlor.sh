#!/usr/bin/env python3
"""parlor conformance suite: the HTTP contract, checked from the outside.

Any implementation of parlor has to pass it: today's Node server, and the Gleam port before it may
replace it. It looks only at what a client can see (status codes, headers, bodies, timing) and at
what the served pages promise; nothing about how a server is built.

Two tiers:
  contract  runs against any server, production included: shapes, status codes, headers, auth,
            content negotiation, long-poll semantics, close, purge. It creates 11 rooms (topic
            "[conformance] ...") and purges every one at the end. parlor.sh allows 20 per client
            per hour (RATE_CREATE), so against it, one run per hour.
  limits    starts its own servers with small limits (MAX_BODY=100, RATE_POST=2, a TTL of seconds,
            ...), so it needs the command that runs a server. It also covers what only an operator
            can do: restarts, persistence, shutdown. The environment variable names are part of the
            contract here: a port has to honour the same ones.

usage:
  tests/conformance/conformance.py --url https://parlor.sh     contract tier, against a running server
  tests/conformance/conformance.py --cmd "node server.mjs"     both tiers; the command is started (from
                                                               the repo root) once per limits profile,
                                                               with PORT, HOST and DATA_DIR set
  add -k WORD to run only the checks whose name contains WORD.

Python 3 standard library only: the server has no dependencies, and neither does its test.
"""
import argparse, http.client, json, os, re, shlex, signal, socket, subprocess, sys, tempfile, threading, time, urllib.parse

TOPIC = '[conformance] automated check, purged when done'
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))


# --------------------------------------------------------------------------------------------
# HTTP, the way an agent does it: one fresh connection per request, nothing hidden.
# --------------------------------------------------------------------------------------------
class Resp:
    def __init__(self, status, headers, body, elapsed):
        self.status, self._headers, self.body, self.elapsed = status, headers, body, elapsed

    def header(self, name):
        vals = self.all(name)
        return vals[0] if vals else None

    def all(self, name):
        return [v for k, v in self._headers if k == name.lower()]

    @property
    def text(self):
        return self.body.decode('utf-8', 'replace')

    def json(self):
        return json.loads(self.body)

    @property
    def type(self):
        return (self.header('content-type') or '').split(';')[0].strip()

    def __repr__(self):
        return f'<{self.status} {self.type} {self.text[:120]!r}>'


class Server:
    def __init__(self, base):
        self.base = base.rstrip('/')
        u = urllib.parse.urlsplit(self.base)
        self.https, self.host, self.port = u.scheme == 'https', u.hostname, u.port or (443 if u.scheme == 'https' else 80)

    def req(self, method, path, body=None, headers=None, token=None, timeout=20):
        h = dict(headers or {})
        if token:
            h['Authorization'] = f'Bearer {token}'
        if isinstance(body, dict):
            body = json.dumps(body).encode()
            h.setdefault('Content-Type', 'application/json')
        elif isinstance(body, str):
            body = body.encode()
            h.setdefault('Content-Type', 'text/plain')
        conn = (http.client.HTTPSConnection if self.https else http.client.HTTPConnection)(self.host, self.port, timeout=timeout)
        t = time.time()
        try:
            conn.request(method, path, body=body, headers=h)
            r = conn.getresponse()
            data = r.read()
            return Resp(r.status, [(k.lower(), v) for k, v in r.getheaders()], data, time.time() - t)
        finally:
            conn.close()

    def get(self, path, **kw):
        return self.req('GET', path, **kw)

    def post(self, path, body=None, **kw):
        return self.req('POST', path, body, **kw)

    def form(self, path, fields, **kw):
        kw.setdefault('headers', {})['Content-Type'] = 'application/x-www-form-urlencoded'
        return self.req('POST', path, urllib.parse.urlencode(fields).encode(), **kw)


# --------------------------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------------------------
CHECKS = []


def check(tier, env=None):
    """Register a check. Its docstring is its name; `env` is the limits profile it needs."""
    def wrap(fn):
        CHECKS.append((tier, tuple(sorted((env or {}).items())), fn))
        return fn
    return wrap


class Failed(Exception):
    pass


def ok(cond, msg):
    if not cond:
        raise Failed(msg)


def eq(got, want, what):
    if got != want:
        raise Failed(f'{what}: expected {want!r}, got {got!r}')


def is_error(r, status, what):
    """Errors are JSON {"error", "hint"} with the matching status (room.md)."""
    eq(r.status, status, f'{what}: status')
    eq(r.type, 'application/json', f'{what}: content type')
    ok('error' in r.json(), f'{what}: no "error" field in {r.text[:100]!r}')


FOOTER = re.compile(r'^--- cursor: (\d+) \| status: (open|closed) \| present: (\d+)/(\d+)'
                    r'(?: \| left: (?:(\d+) bytes)?(?:, )?(?:(\d+) messages)?)?( \| nothing new)?$')
LINE = re.compile(r'^\[#(\d+) \d\d:\d\d:\d\d\] (\S+?)(?: -> (\S+))?(?: \(re #(\d+)\))?: (.*)$')


def footer(text):
    last = text.rstrip('\n').split('\n')[-1]
    m = FOOTER.match(last)
    ok(m, f'transcript footer does not match the documented format: {last!r}')
    return m


class Ctx:
    """What a check gets: the server, helpers, and rooms it creates (all purged at the end)."""

    def __init__(self, srv, runner=None):
        self.srv, self.runner, self.created, self._main = srv, runner, [], None

    def create(self, fields=None, via='form'):
        fields = {'handle': 'host', 'topic': TOPIC, **(fields or {})}
        if via == 'json':
            r = self.srv.post('/', fields)
        elif via == 'query':
            r = self.srv.post('/?' + urllib.parse.urlencode(fields))
        else:
            r = self.srv.form('/', fields)
        eq(r.status, 201, f'create ({via}) status: {r.text[:200]}')
        room = r.json()
        room['id'] = room['room_url'].rsplit('/', 1)[1]
        self.created.append((room['id'], room['token']))
        return room

    def join(self, rid, handle='guest'):
        r = self.srv.form(f'/r/{rid}/join', {'handle': handle})
        eq(r.status, 201, f'join status: {r.text[:200]}')
        return r.json()

    def say(self, rid, tok, text, **query):
        path = f'/r/{rid}/messages' + ('?' + urllib.parse.urlencode(query) if query else '')
        return self.srv.post(path, text, token=tok)

    def read(self, rid, tok=None, **query):
        return self.srv.get(f'/r/{rid}/messages?' + urllib.parse.urlencode(query), token=tok)

    def main(self):
        """A shared room with a host and a guest, for checks that only read and post."""
        if not self._main:
            host = self.create()
            guest = self.join(host['id'])
            self._main = {'id': host['id'], 'host': host['token'], 'guest': guest['token'], 'guest_handle': guest['handle']}
        return self._main

    def spare(self):
        """A second shared room, for checks that need some other room or add participants to one."""
        if not getattr(self, '_spare', None):
            self._spare = self.create()
        return self._spare

    def cursor(self, rid, tok=None):
        return int(self.read(rid, tok, since=0).header('x-room-cursor'))

    def max_body(self, rid):
        m = re.search(r'max (\d+) bytes per message', self.srv.get(f'/r/{rid}').text)
        ok(m, 'room page does not state "max N bytes per message"')
        return int(m.group(1))

    def cleanup(self):
        for rid, tok in self.created:
            try:
                self.srv.post(f'/r/{rid}/purge', token=tok)
            except Exception:
                pass


def later(seconds, fn):
    t = threading.Timer(seconds, fn)
    t.start()
    return t


SECURITY = {'content-security-policy': None, 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer'}


def security_headers(r, what):
    for name, want in SECURITY.items():
        got = r.header(name)
        ok(got, f'{what}: missing {name}')
        if want:
            eq(got, want, f'{what}: {name}')
    ok(not r.header('access-control-allow-origin'), f'{what}: sends CORS headers (there is no CORS)')


# ---- the front page and static documents ---------------------------------------------------

@check('contract')
def front_page_markdown(c):
    """GET / answers markdown by default, and names its own base URL"""
    r = c.srv.get('/')
    eq(r.status, 200, 'status')
    eq(r.type, 'text/markdown', 'content type')
    ok(r.text.startswith('# parlor'), 'does not start with "# parlor"')
    ok(f'{c.srv.base}/cli' in r.text, f'does not mention {c.srv.base}/cli')
    ok('Accept' in r.all('vary'), f'Vary does not include Accept: {r.all("vary")}')


@check('contract')
def front_page_html(c):
    """GET / with Accept: text/html answers HTML with the same base URL"""
    r = c.srv.get('/', headers={'Accept': 'text/html'})
    eq(r.status, 200, 'status')
    eq(r.type, 'text/html', 'content type')
    ok(r.text.lower().startswith('<!doctype html>'), 'not an HTML document')
    ok(c.srv.base in r.text, 'does not mention its base URL')
    ok('Accept' in r.all('vary'), 'Vary does not include Accept')


@check('contract')
def head_is_get(c):
    """HEAD is answered like GET, without a body"""
    g, h = c.srv.get('/'), c.srv.req('HEAD', '/')
    eq(h.status, g.status, 'status')
    eq(h.type, g.type, 'content type')
    eq(h.body, b'', 'body')


@check('contract')
def cli_served(c):
    """GET /cli serves the bash client, pointed at this server"""
    r = c.srv.get('/cli')
    eq(r.status, 200, 'status')
    eq(r.type, 'text/plain', 'content type')
    ok(r.text.startswith('#!/usr/bin/env bash'), 'not a bash script')
    ok(f'PARLOR_URL:-{c.srv.base}' in r.text, f'default server is not {c.srv.base}')


@check('contract')
def example_room(c):
    """/example is a sample room in both representations, and nothing to join"""
    md = c.srv.get('/example')
    eq(md.status, 200, 'markdown status')
    ok(md.text.startswith('# A sample room') and 'not a room you can join' in md.text, 'markdown is not the sample-room text')
    html = c.srv.get('/example', headers={'Accept': 'text/html'})
    eq(html.type, 'text/html', 'HTML content type')
    ok('Accept' in md.all('vary') and 'Accept' in html.all('vary'), 'Vary does not include Accept')
    is_error(c.srv.form('/example/join', {'handle': 'x'}), 404, 'POST /example/join')


@check('contract')
def unknown_path(c):
    """An unknown path is a JSON 404 that points to the front page"""
    r = c.srv.get('/no-such-thing')
    is_error(r, 404, 'GET /no-such-thing')
    ok(c.srv.base in r.json().get('hint', ''), 'hint does not point to the front page')


@check('contract')
def security_headers_everywhere(c):
    """Every response carries CSP, nosniff and no-referrer, and none sends CORS headers"""
    m = c.main()
    for what, r in [('front page', c.srv.get('/')), ('HTML front page', c.srv.get('/', headers={'Accept': 'text/html'})),
                    ('/cli', c.srv.get('/cli')), ('/example', c.srv.get('/example')), ('404', c.srv.get('/nope')),
                    ('room page', c.srv.get(f'/r/{m["id"]}')), ('messages', c.read(m['id'], since=0)),
                    ('401', c.say(m['id'], 'wrong', 'x')), ('post', c.say(m['id'], m['host'], 'headers check'))]:
        security_headers(r, what)


@check('contract')
def no_connection_close_when_healthy(c):
    """A healthy server does not close connections on every response"""
    for r in (c.srv.get('/'), c.read(c.main()['id'], since=0)):
        ok((r.header('connection') or '').lower() != 'close', 'Connection: close on a healthy response')


# ---- creating a room -----------------------------------------------------------------------

@check('contract')
def create_response(c):
    """Creating a room answers 201 with the documented fields"""
    room = c.create({'handle': 'maker'})
    for k in ('room_url', 'share', 'handle', 'token', 'role', 'cursor', 'ttl', 'next'):
        ok(k in room, f'no "{k}" in the create response')
    ok(room['room_url'].startswith(f'{c.srv.base}/r/'), f'room_url is not under {c.srv.base}/r/: {room["room_url"]}')
    ok(re.fullmatch(r'[A-Za-z0-9_-]{16}', room['id']), f'room id is not 16 base64url characters (12 random bytes): {room["id"]}')
    ok(room['room_url'] in room['share'], 'share does not contain the room URL')
    eq(room['handle'], 'maker', 'handle')
    eq(room['role'], 'host', 'role')
    eq(room['cursor'], 1, 'cursor (message 1 is "created the room")')
    ok(isinstance(room['ttl'], int) and room['ttl'] > 0, f'ttl is not a positive number of seconds: {room["ttl"]}')
    ok('wait' in room['next'], 'next does not say to wait')


@check('contract')
def create_other_encodings(c):
    """Create accepts JSON and query parameters, and the handle defaults to "host" """
    eq(c.create({'handle': 'json-maker'}, via='json')['handle'], 'json-maker', 'handle from a JSON body')
    eq(c.create({'handle': 'query-maker'}, via='query')['handle'], 'query-maker', 'handle from the query')
    r = c.srv.post('/', {'topic': TOPIC})
    eq(r.status, 201, 'create without a handle')
    room = r.json()
    c.created.append((room['room_url'].rsplit('/', 1)[1], room['token']))
    eq(room['handle'], 'host', 'default handle')


@check('contract')
def create_ttl(c):
    """ttl takes a unit ("90m"), and a malformed one is a 400"""
    room = c.create({'ttl': '90m'})
    ok(room['ttl'] >= 5400 or room['ttl'] > 0, 'ttl')  # a server may raise it to its TTL_MIN
    is_error(c.srv.form('/', {'handle': 'h', 'topic': TOPIC, 'ttl': 'soon'}), 400, 'ttl=soon')


# ---- the room page -------------------------------------------------------------------------

@check('contract')
def room_page(c):
    """The room page is markdown by default, HTML on request, unlisted, and states the room"""
    m = c.main()
    md = c.srv.get(f'/r/{m["id"]}')
    eq(md.status, 200, 'status')
    eq(md.type, 'text/markdown', 'content type')
    ok('noindex' in (md.header('x-robots-tag') or ''), 'no X-Robots-Tag: noindex')
    ok('Accept' in md.all('vary'), 'Vary does not include Accept')
    ok(m['id'] in md.text and 'open' in md.text and m['guest_handle'] in md.text, 'page does not state id, status and participants')
    html = c.srv.get(f'/r/{m["id"]}', headers={'Accept': 'text/html'})
    eq(html.type, 'text/html', 'HTML content type')
    ok('noindex' in html.text and m['id'] in html.text, 'HTML page is not the room, or not noindex')


@check('contract')
def room_page_escapes_topic(c):
    """A topic is shown as text: markup in it is escaped on the HTML page"""
    room = c.create({'topic': '[conformance] <script>alert(1)</script> & "quotes"'})
    html = c.srv.get(f'/r/{room["id"]}', headers={'Accept': 'text/html'}).text
    ok('<script>alert(1)' not in html, 'the topic\'s <script> appears unescaped')
    ok('&lt;script&gt;alert(1)' in html, 'the topic is not shown escaped')


@check('contract')
def room_ids_resolve_nothing_else(c):
    """Only well-formed, existing room ids resolve; anything else is a 404, never a file"""
    for path in ('/r/short', '/r/AAAAAAAAAAAAAAAA', '/r/..%2F..%2Fetc%2Fpasswd', '/r/%2e%2e/logs', '/r/AAAAAAAAAAAAAAAA/logs'):
        r = c.srv.get(path)
        is_error(r, 404, path)
        ok('root:' not in r.text, f'{path} leaked a file')


# ---- joining -------------------------------------------------------------------------------

@check('contract')
def join_response(c):
    """Joining answers 201 with a guest token and cursor 0"""
    room = c.spare()
    g = c.join(room['id'], 'visitor')
    eq(g['handle'], 'visitor', 'handle')
    eq(g['role'], 'guest', 'role')
    eq(g['cursor'], 0, 'cursor')
    ok(g['token'] and g['token'] != room['token'], 'no token of its own')


@check('contract')
def join_handles(c):
    """Handles are cleaned, capped at 32, and a taken one (any case) gets a numbered variant"""
    room = c.spare()
    eq(c.join(room['id'], '@Foo Bar!')['handle'], 'Foo-Bar-', 'cleaned handle')
    eq(len(c.join(room['id'], 'x' * 40)['handle']), 32, 'length of a 40-character handle')
    eq(c.join(room['id'], 'dup')['handle'], 'dup', 'first "dup"')
    eq(c.join(room['id'], 'DUP')['handle'], 'DUP-2', 'second, differently cased "dup"')
    r = c.srv.post(f'/r/{room["id"]}/join?handle=byquery')
    eq(r.json().get('handle'), 'byquery', 'handle from the query')
    eq(c.srv.post(f'/r/{room["id"]}/join', {'handle': 'byjson'}).json().get('handle'), 'byjson', 'handle from JSON')


@check('contract')
def join_twice_with_a_token(c):
    """Joining while already holding a token of the room is a 409"""
    m = c.main()
    is_error(c.srv.form(f'/r/{m["id"]}/join', {'handle': 'again'}, token=m['guest']), 409, 'join with a token')


# ---- auth ----------------------------------------------------------------------------------

@check('contract')
def posting_needs_the_right_token(c):
    """Posting needs a token of this room: none, a wrong one, or another room's is a 401"""
    m, other = c.main(), c.spare()
    for what, tok in (('no token', None), ('wrong token', 'x' * 32), ('another room\'s token', other['token'])):
        is_error(c.say(m['id'], tok, 'hello'), 401, what)


@check('contract')
def host_only_actions(c):
    """Only the host can close or purge: a guest gets a 403"""
    m = c.main()
    is_error(c.srv.post(f'/r/{m["id"]}/close', token=m['guest']), 403, 'guest close')
    is_error(c.srv.post(f'/r/{m["id"]}/purge', token=m['guest']), 403, 'guest purge')


# ---- posting -------------------------------------------------------------------------------

@check('contract')
def post_response(c):
    """A post answers 201 with its id, a timestamp and a reminder to wait"""
    m = c.main()
    a, b = c.say(m['id'], m['host'], 'first'), c.say(m['id'], m['guest'], 'second')
    eq(a.status, 201, 'status')
    j = a.json()
    ok(isinstance(j.get('id'), int) and j.get('ts') and 'wait' in j.get('next', ''), f'response lacks id, ts or next: {j}')
    eq(b.json()['id'], j['id'] + 1, 'ids are consecutive')


@check('contract')
def post_addressing(c):
    """to= and reply_to= are kept; an unknown recipient is a 404, an unknown message a 400"""
    m = c.main()
    first = c.say(m['id'], m['guest'], 'question').json()['id']
    r = c.srv.post(f'/r/{m["id"]}/messages', {'body': 'answer', 'to': m['guest_handle'], 'reply_to': first}, token=m['host'])
    eq(r.status, 201, 'JSON post status')
    msg = [x for x in c.read(m['id'], since=0).json()['messages'] if x['id'] == r.json()['id']][0]
    eq((msg['to'], msg['reply_to']), (m['guest_handle'], first), 'to and reply_to')
    r = c.say(m['id'], m['host'], 'hi', to='nobody-here')
    is_error(r, 404, 'to=unknown')
    ok(m['guest_handle'] in r.json().get('hint', ''), 'the 404 hint does not list participants')
    is_error(c.say(m['id'], m['host'], 'hi', reply_to=99999), 400, 'reply_to=unknown')


@check('contract')
def post_rejections(c):
    """Empty posts, posts carrying a room token, and posts over the size limit are refused"""
    m = c.main()
    before = c.cursor(m['id'])
    is_error(c.say(m['id'], m['host'], '   '), 400, 'blank post')
    is_error(c.say(m['id'], m['host'], f'my token is {m["guest"]}'), 400, 'post containing a token')
    is_error(c.say(m['id'], m['host'], 'x' * (c.max_body(m['id']) + 1)), 413, 'post over max_body')
    eq(c.cursor(m['id']), before, 'a refused post changed the room')


@check('contract')
def leave_and_come_back(c):
    """Leave is announced and shown in /participants; posting again brings you back"""
    room = c.spare()
    g = c.join(room['id'], 'leaver')
    eq(c.srv.post(f'/r/{room["id"]}/leave', token=g['token']).json(), {'ok': True}, 'leave response')
    people = {p['handle']: p for p in c.srv.get(f'/r/{room["id"]}/participants').json()['participants']}
    eq(people['leaver']['left'], True, 'left after leave')
    ok('*: leaver left' in c.srv.get(f'/r/{room["id"]}/logs').text, 'no "*: leaver left" line')
    c.say(room['id'], g['token'], 'back')
    people = {p['handle']: p for p in c.srv.get(f'/r/{room["id"]}/participants').json()['participants']}
    eq(people['leaver']['left'], False, 'left after posting again')


# ---- reading -------------------------------------------------------------------------------

@check('contract')
def read_json_shape(c):
    """Reading answers {messages, cursor, status}; messages carry the documented fields"""
    m = c.main()
    j = c.read(m['id'], since=0).json()
    ok(set(j) >= {'messages', 'cursor', 'status'}, f'fields: {sorted(j)}')
    for msg in j['messages']:
        eq(set(msg), {'id', 'ts', 'kind', 'from', 'to', 'reply_to', 'body'}, 'message fields')
        ok(msg['kind'] in ('message', 'system'), f'kind {msg["kind"]}')
    eq(j['messages'][0]['kind'], 'system', 'message 1 kind')
    ok(j['messages'][0]['body'].endswith('created the room'), 'message 1 is not "created the room"')


@check('contract')
def read_text_and_headers(c):
    """The text transcript and the X-Room headers carry the same cursor, status and space left"""
    m = c.main()
    r = c.read(m['id'], since=0, format='text')
    eq(r.type, 'text/plain', 'content type')
    f = footer(r.text)
    eq(r.header('x-room-cursor'), f.group(1), 'X-Room-Cursor vs footer')
    eq(r.header('x-room-status'), f.group(2), 'X-Room-Status vs footer')
    if f.group(5):
        eq(r.header('x-room-bytes-left'), f.group(5), 'X-Room-Bytes-Left vs footer')
    if f.group(6):
        eq(r.header('x-room-messages-left'), f.group(6), 'X-Room-Messages-Left vs footer')
    for line in r.text.rstrip('\n').split('\n')[:-1]:
        ok(LINE.match(line) or line.startswith('    '), f'transcript line does not match the documented format: {line!r}')
    ok(not r.all('vary') or 'Accept' not in ', '.join(r.all('vary')), '/messages negotiates nothing, yet varies on Accept')


@check('contract')
def read_without_token(c):
    """Reading works without a token and returns the same messages"""
    m = c.main()
    eq(c.read(m['id'], since=0).json()['messages'], c.read(m['id'], m['host'], since=0).json()['messages'], 'messages with and without a token')


@check('contract')
def read_since_and_nothing_new(c):
    """Reading from the current cursor returns nothing, and the text says "nothing new" """
    m = c.main()
    cur = c.cursor(m['id'])
    eq(c.read(m['id'], since=cur).json()['messages'], [], 'messages after the cursor')
    ok(footer(c.read(m['id'], since=cur, format='text').text).group(7), 'footer does not say "nothing new"')


@check('contract')
def read_for_me(c):
    """for_me=1 returns only messages addressed to you or mentioning you"""
    m = c.main()
    cur = c.cursor(m['id'])
    c.say(m['id'], m['host'], 'to everyone')
    c.say(m['id'], m['host'], 'to the guest', to=m['guest_handle'])
    c.say(m['id'], m['host'], f'hello @{m["guest_handle"]}')
    got = [x['body'] for x in c.read(m['id'], m['guest'], since=cur, for_me=1).json()['messages']]
    eq(got, ['to the guest', f'hello @{m["guest_handle"]}'], 'for_me messages')


# ---- waiting -------------------------------------------------------------------------------

@check('contract')
def wait_holds_when_nothing_happens(c):
    """wait=2 with nothing new is held about 2 s, then answers "nothing new" """
    m = c.main()
    cur = c.cursor(m['id'])
    r = c.read(m['id'], m['host'], since=cur, wait=2, format='text')
    ok(1.8 <= r.elapsed <= 3.5, f'held {r.elapsed:.2f} s')
    ok(footer(r.text).group(7), 'did not answer "nothing new"')


@check('contract')
def wait_past_the_end_holds(c):
    """A cursor past the end is held like any other"""
    m = c.main()
    r = c.read(m['id'], m['host'], since=99999, wait=2)
    ok(1.8 <= r.elapsed <= 3.5, f'held {r.elapsed:.2f} s')


@check('contract')
def wait_woken_by_a_post(c):
    """Someone else's post wakes a wait at once"""
    m = c.main()
    cur = c.cursor(m['id'])
    later(0.7, lambda: c.say(m['id'], m['guest'], 'wake up'))
    r = c.read(m['id'], m['host'], since=cur, wait=20)
    ok(r.elapsed < 3, f'woke after {r.elapsed:.2f} s')
    ok('wake up' in [x['body'] for x in r.json()['messages']], 'the post is not in the answer')


@check('contract')
def wait_not_woken_by_own_post(c):
    """Your own post does not wake your wait, but is in what you read next"""
    m = c.main()
    cur = c.cursor(m['id'])
    later(0.5, lambda: c.say(m['id'], m['host'], 'talking to myself'))
    r = c.read(m['id'], m['host'], since=cur, wait=2)
    ok(r.elapsed >= 1.8, f'woken by its own post after {r.elapsed:.2f} s')
    ok('talking to myself' in [x['body'] for x in c.read(m['id'], m['host'], since=cur).json()['messages']], 'own post missing from the next read')


@check('contract')
def wait_woken_by_a_join(c):
    """A join wakes the host's wait"""
    room = c.spare()
    cur = c.cursor(room['id'])
    later(0.7, lambda: c.join(room['id'], 'arrival'))
    r = c.read(room['id'], room['token'], since=cur, wait=20)
    ok(r.elapsed < 3, f'woke after {r.elapsed:.2f} s')
    ok(any(x['body'] == 'arrival joined' for x in r.json()['messages']), 'no "arrival joined"')


# ---- logs and participants -----------------------------------------------------------------

@check('contract')
def logs(c):
    """/logs is the whole conversation: text by default, JSON lines or HTML on request"""
    m = c.main()
    t = c.srv.get(f'/r/{m["id"]}/logs')
    eq(t.status, 200, 'status')
    eq(t.type, 'text/plain', 'content type')
    ok(t.text.startswith(f'# Log of room {m["id"]} (open)'), f'heading: {t.text[:60]!r}')
    ok('Accept' in t.all('vary'), 'Vary does not include Accept')
    n = c.cursor(m['id'])
    for what, r in (('?format=jsonl', c.srv.get(f'/r/{m["id"]}/logs?format=jsonl')),
                    ('Accept: application/json', c.srv.get(f'/r/{m["id"]}/logs', headers={'Accept': 'application/json'}))):
        eq(r.type, 'application/x-ndjson', f'{what} content type')
        lines = [json.loads(l) for l in r.text.strip().split('\n')]
        eq(len(lines), n, f'{what}: one line per message')
    eq(c.srv.get(f'/r/{m["id"]}/logs', headers={'Accept': 'text/html'}).type, 'text/html', 'HTML log content type')


@check('contract')
def participants(c):
    """/participants lists handle, role and left, without a token"""
    m = c.main()
    ps = c.srv.get(f'/r/{m["id"]}/participants').json()['participants']
    for p in ps:
        eq(set(p), {'handle', 'role', 'left'}, 'participant fields')
    eq([p['role'] for p in ps][:2], ['host', 'guest'], 'roles')


# ---- ending a room -------------------------------------------------------------------------

@check('contract')
def close(c):
    """Closing makes the room read-only: posts and joins get 410, the log stays readable"""
    room = c.create()
    g = c.join(room['id'])
    eq(c.srv.post(f'/r/{room["id"]}/close', token=room['token']).json(), {'ok': True, 'status': 'closed'}, 'close response')
    is_error(c.say(room['id'], g['token'], 'too late'), 410, 'post after close')
    is_error(c.srv.form(f'/r/{room["id"]}/join', {'handle': 'late'}), 410, 'join after close')
    eq(c.srv.get(f'/r/{room["id"]}/logs').status, 200, 'logs after close')
    eq(c.read(room['id'], since=0).json()['status'], 'closed', 'status')
    ok('left:' not in footer(c.read(room['id'], since=0, format='text').text).group(0), 'a closed room still reports space left')


@check('contract')
def close_with_a_last_word_wakes_waiters_once(c):
    """A close with a body posts it as the host's last message; a waiting guest gets it, the close line and the closed status together"""
    room = c.create()
    g = c.join(room['id'])
    cur = c.cursor(room['id'])
    later(0.7, lambda: c.srv.post(f'/r/{room["id"]}/close', 'continued at https://example.invalid/r/next', token=room['token']))
    r = c.read(room['id'], g['token'], since=cur, wait=20, format='text')
    ok(r.elapsed < 3, f'woke after {r.elapsed:.2f} s')
    ok('host: continued at https://example.invalid/r/next' in r.text, 'the last word is not in the answer')
    ok('*: host closed the room' in r.text, 'the close line is not in the same answer')
    eq(footer(r.text).group(2), 'closed', 'status in the same answer')


@check('contract')
def purge(c):
    """A purge deletes the conversation and leaves a notice that says so"""
    room = c.create()
    c.say(room['id'], room['token'], 'soon gone')
    r = c.srv.post(f'/r/{room["id"]}/purge', token=room['token'])
    eq(r.status, 200, 'purge status')
    eq(r.json().get('status'), 'purged', 'purge response')
    for path in (f'/r/{room["id"]}', f'/r/{room["id"]}/logs'):
        t = c.srv.get(path)
        eq(t.status, 410, f'{path} status')
        ok(t.text.startswith(f'# Room {room["id"]} was purged') and 'soon gone' not in t.text, f'{path} is not the notice')
    is_error(c.read(room['id'], since=0), 410, 'messages after purge')
    is_error(c.say(room['id'], room['token'], 'x'), 410, 'post after purge')


# ============================================================================================
# limits tier: own servers, small limits (environment variable names are part of the contract)
# ============================================================================================
CAPS = {'MAX_BODY': '100', 'MAX_ROOM_BYTES': '400', 'MAX_MESSAGES': '0'}


@check('limits', CAPS)
def caps_space_left(c):
    """One maximum-size message is held back: a fresh room reports cap minus MAX_BODY; joins do not count"""
    room = c.create()
    eq(c.read(room['id'], since=0).header('x-room-bytes-left'), '300', 'bytes left in a fresh room')
    ok(c.read(room['id'], since=0).header('x-room-messages-left') is None, 'messages left reported with MAX_MESSAGES=0')
    c.join(room['id'])
    eq(c.read(room['id'], since=0).header('x-room-bytes-left'), '300', 'bytes left after a join')
    ok('Space left for posts: 300 bytes' in c.srv.get(f'/r/{room["id"]}').text, 'room page does not state the space left')


@check('limits', CAPS)
def caps_fit_and_full(c):
    """A post that does not fit says so with both numbers; a full room refuses everyone, host included"""
    room = c.create()
    g = c.join(room['id'])
    for n in (100, 100, 60):
        eq(c.say(room['id'], g['token'], 'a' * n).status, 201, f'{n}-byte post')
    r = c.say(room['id'], g['token'], 'b' * 50)
    is_error(r, 403, 'post that does not fit')
    ok('50 bytes; 40 remain' in r.json().get('hint', ''), f'hint does not give both numbers: {r.json()}')
    eq(c.say(room['id'], room['token'], 'c' * 40).status, 201, 'a post that fits exactly')
    for who, tok in (('guest', g['token']), ('host', room['token'])):
        r = c.say(room['id'], tok, 'x')
        is_error(r, 403, f'{who} post into a full room')
        eq(r.json()['error'], 'room is full', f'{who}: error')
    eq(c.srv.post(f'/r/{room["id"]}/close', 'continued elsewhere', token=room['token']).status, 200, 'close with a body on a full room')
    ok('host: continued elsewhere' in c.srv.get(f'/r/{room["id"]}/logs').text, 'the last word is not in the log')


@check('limits', {'MAX_MESSAGES': '4'})
def caps_message_count(c):
    """MAX_MESSAGES counts participants' messages only, and holds the last one back for the host"""
    room = c.create()
    g = c.join(room['id'])
    eq(c.read(room['id'], since=0).header('x-room-messages-left'), '3', 'messages left in a fresh room')
    for i in range(3):
        eq(c.say(room['id'], g['token'], f'm{i}').status, 201, f'post {i + 1}')
    is_error(c.say(room['id'], g['token'], 'm4'), 403, 'fourth post')
    eq(c.srv.post(f'/r/{room["id"]}/close', {'body': 'last word'}, token=room['token']).status, 200, 'close with a JSON body')
    msgs = [x for x in c.read(room['id'], since=0).json()['messages'] if x['kind'] == 'message']
    eq(len(msgs), 4, 'participant messages at the end')


@check('limits', {'MAX_BODY': '100'})
def max_body_413(c):
    """A body over MAX_BODY is a 413, and the room page states the limit"""
    room = c.create()
    eq(c.max_body(room['id']), 100, 'max_body on the room page')
    is_error(c.say(room['id'], room['token'], 'x' * 101), 413, '101-byte post')
    eq(c.say(room['id'], room['token'], 'x' * 100).status, 201, '100-byte post')


@check('limits', {'MAX_PARTICIPANTS': '2'})
def max_participants(c):
    """A room at MAX_PARTICIPANTS refuses joins with 403"""
    room = c.create()
    c.join(room['id'], 'second')
    r = c.srv.form(f'/r/{room["id"]}/join', {'handle': 'third'})
    is_error(r, 403, 'third participant')
    eq(r.json()['error'], 'room is full', 'error')


@check('limits', {'RATE_POST': '2'})
def rate_post(c):
    """Past RATE_POST a participant gets 429 with Retry-After; others are unaffected"""
    room = c.create()
    g = c.join(room['id'])
    for i in range(2):
        eq(c.say(room['id'], room['token'], f'p{i}').status, 201, f'post {i + 1}')
    r = c.say(room['id'], room['token'], 'p3')
    is_error(r, 429, 'third post in a minute')
    ok((r.header('retry-after') or '').isdigit(), 'no numeric Retry-After')
    eq(c.say(room['id'], g['token'], 'meanwhile').status, 201, 'another participant')


@check('limits', {'RATE_CREATE': '2'})
def rate_create(c):
    """Past RATE_CREATE a client gets 429 with Retry-After"""
    c.create(); c.create()
    r = c.srv.form('/', {'handle': 'h', 'topic': TOPIC})
    is_error(r, 429, 'third room in an hour')
    ok((r.header('retry-after') or '').isdigit(), 'no numeric Retry-After')


@check('limits', {'MAX_ROOMS': '2'})
def max_rooms(c):
    """At MAX_ROOMS, creating a room is a 503"""
    c.create(); c.create()
    is_error(c.srv.form('/', {'handle': 'h', 'topic': TOPIC}), 503, 'third room on the server')


@check('limits', {'MAX_WAIT': '2'})
def max_wait(c):
    """A wait above MAX_WAIT is cut to MAX_WAIT, and the room page states it"""
    room = c.create()
    ok('above 2 are clamped' in c.srv.get(f'/r/{room["id"]}').text, 'room page does not state max_wait')
    r = c.read(room['id'], room['token'], since=1, wait=30)
    ok(1.8 <= r.elapsed <= 3.5, f'held {r.elapsed:.2f} s')


@check('limits', {'MAX_WAITERS_PER_CLIENT': '1'})
def max_waiters_per_client(c):
    """Over MAX_WAITERS_PER_CLIENT, a wait is answered at once instead of held"""
    room = c.create()
    held = threading.Thread(target=lambda: c.read(room['id'], room['token'], since=1, wait=3))
    held.start()
    time.sleep(0.5)
    r = c.read(room['id'], room['token'], since=1, wait=3)
    ok(r.elapsed < 1, f'second wait was held {r.elapsed:.2f} s')
    held.join()


@check('limits', {'TRUST_PROXY': '1', 'RATE_CREATE': '1'})
def trust_proxy_rightmost(c):
    """With TRUST_PROXY=1 the client is the rightmost X-Forwarded-For entry; the rest is the client's word"""
    def make(xff):
        return c.srv.form('/', {'handle': 'h', 'topic': TOPIC}, headers={'X-Forwarded-For': xff})
    for r in (make('198.51.100.1, 203.0.113.1'), make('203.0.113.2')):
        eq(r.status, 201, 'first room from each client')
        j = r.json(); c.created.append((j['room_url'].rsplit('/', 1)[1], j['token']))
    is_error(make('198.51.100.99, 203.0.113.1'), 429, 'same rightmost client, different leftmost')


@check('limits', {'RATE_CREATE': '1'})
def xff_ignored_without_trust_proxy(c):
    """Without TRUST_PROXY, X-Forwarded-For is ignored"""
    c.create()
    is_error(c.srv.form('/', {'handle': 'h', 'topic': TOPIC}, headers={'X-Forwarded-For': '203.0.113.7'}), 429, 'second room, spoofed address')


TTL = {'TTL_MIN': '1', 'SWEEP_EVERY': '1'}


@check('limits', TTL)
def ttl_expiry(c):
    """A room nobody uses is deleted TTL after its last activity; anonymous reads do not keep it"""
    room = c.create({'ttl': '2'})
    eq(room['ttl'], 2, 'ttl')
    for _ in range(4):
        c.read(room['id'], since=0)          # anonymous: must not count
        time.sleep(1)
    is_error(c.srv.get(f'/r/{room["id"]}'), 404, 'room after 4 s of anonymous reads')


@check('limits', TTL)
def ttl_activity_keeps(c):
    """Any request with a token counts as activity and pushes deletion back"""
    room = c.create({'ttl': '2'})
    for _ in range(4):
        c.read(room['id'], room['token'], since=0)
        time.sleep(1)
    eq(c.srv.get(f'/r/{room["id"]}').status, 200, 'room after 4 s of authenticated reads')


@check('limits', {})
def survives_restart(c):
    """Rooms, messages and tokens survive a restart"""
    room = c.create()
    g = c.join(room['id'])
    c.say(room['id'], g['token'], 'before the restart')
    c.runner.restart()
    ok('before the restart' in c.srv.get(f'/r/{room["id"]}/logs').text, 'message lost')
    eq(c.say(room['id'], g['token'], 'after the restart').status, 201, 'guest token after the restart')


@check('limits', {})
def shutdown_answers_held_polls(c):
    """On SIGTERM every held wait is answered, not cut"""
    room = c.create()
    box = {}
    t = threading.Thread(target=lambda: box.update(r=c.read(room['id'], room['token'], since=1, wait=20)))
    t.start()
    time.sleep(0.7)
    c.runner.restart()
    t.join()
    ok('r' in box, 'the held wait raised instead of being answered')
    eq(box['r'].status, 200, 'held wait at shutdown')
    ok(box['r'].elapsed < 5, f'answered after {box["r"].elapsed:.2f} s')


# --------------------------------------------------------------------------------------------
# Running
# --------------------------------------------------------------------------------------------
class Runner:
    """Starts the server command with a profile's environment on a free port; restarts it on request."""

    def __init__(self, cmd, env):
        self.cmd, self.env, self.data = cmd, dict(env), tempfile.mkdtemp(prefix='parlor-conformance-')
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0))
            self.port = s.getsockname()[1]
        self.proc = None
        self.start()

    def start(self):
        env = {**os.environ, **self.env, 'PORT': str(self.port), 'HOST': '127.0.0.1', 'DATA_DIR': self.data}
        env.pop('PUBLIC_URL', None)
        self.proc = subprocess.Popen(shlex.split(self.cmd), cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        srv = Server(f'http://127.0.0.1:{self.port}')
        for _ in range(100):
            try:
                if srv.get('/', timeout=2).status == 200:
                    return srv
            except OSError:
                time.sleep(0.1)
        raise RuntimeError(f'server did not come up: {self.proc.stderr.read().decode()[:500] if self.proc.poll() is not None else "no answer"}')

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()

    def restart(self):
        self.stop()
        self.start()


def run(checks, srv_for, verbose_tier):
    """Checks on the same server share one context (its shared rooms); every room is purged at the end."""
    fails, ctxs = 0, {}
    for (tier, env, fn) in checks:
        srv, runner = srv_for(env)
        if env not in ctxs:
            ctxs[env] = Ctx(srv, runner)
        c = ctxs[env]
        c.srv = srv
        name = (fn.__doc__ or fn.__name__).strip()
        t = time.time()
        try:
            fn(c)
            print(f'  ok    {name}  ({time.time() - t:.1f} s)')
        except Failed as e:
            fails += 1
            print(f'  FAIL  {name}\n        {e}')
        except Exception as e:
            fails += 1
            print(f'  FAIL  {name}\n        {type(e).__name__}: {e}')
    for c in ctxs.values():
        c.cleanup()
    return fails


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--url', help='a running server: contract tier only')
    g.add_argument('--cmd', help='the command that starts a server: both tiers')
    ap.add_argument('-k', default='', help='only checks whose name or docstring contains this')
    a = ap.parse_args()
    pick = lambda tier: [x for x in CHECKS if x[0] == tier and (a.k in x[2].__name__ or a.k in (x[2].__doc__ or ''))]
    fails, total = 0, 0
    if a.url:
        srv = Server(a.url)
        print(f'contract tier against {srv.base}')
        chosen = pick('contract'); total += len(chosen)
        fails += run(chosen, lambda env: (srv, None), 'contract')
    else:
        runners = {}
        def srv_for(env):
            if env not in runners:
                for r in runners.values():
                    r.stop()
                runners.clear()
                runners[env] = Runner(a.cmd, dict(env))
            r = runners[env]
            return Server(f'http://127.0.0.1:{r.port}'), r
        try:
            print(f'contract tier against `{a.cmd}` (defaults)')
            chosen = pick('contract'); total += len(chosen)
            fails += run(chosen, srv_for, 'contract')
            print(f'limits tier against `{a.cmd}`')
            chosen = pick('limits'); total += len(chosen)
            fails += run(chosen, srv_for, 'limits')
        finally:
            for r in runners.values():
                r.stop()
    print(f'--- {total - fails} passed, {fails} failed')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
