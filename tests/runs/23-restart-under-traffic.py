#!/usr/bin/env python3
# TESTLOG 23. usage: 23-restart-under-traffic.py BASE_URL 'RESTART COMMAND'
# e.g. http://127.0.0.1:8840 'systemctl --user restart parlor-sa'  or  https://parlor.sh 'ssh HOST sudo systemctl restart parlor'
"""Traffic through a restart: a steady stream of fresh-connection requests, plus two waiting agents
that re-poll the instant their poll returns. Counts every answer and every failure."""
import json, subprocess, sys, threading, time, urllib.request, urllib.error
base, restart = sys.argv[1].rstrip('/'), sys.argv[2]
def post(path, data, tok=None):
    h = {'Authorization': f'Bearer {tok}'} if tok else {}
    return json.loads(urllib.request.urlopen(urllib.request.Request(base + path, data=data.encode(), headers=h), timeout=10).read())
room = post('/', 'handle=host'); rid = room['room_url'].rsplit('/', 1)[1]
toks = [room['token'], post(f'/r/{rid}/join', 'handle=guest')['token']]
res, lock, stop = {}, threading.Lock(), time.time() + 7
def note(k):
    with lock: res[k] = res.get(k, 0) + 1
def call(url, h=None, timeout=10):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=h or {}), timeout=timeout) as r: r.read(); return str(r.status)
    except urllib.error.HTTPError as e: return str(e.code)
    except Exception as e: return type(getattr(e, 'reason', e)).__name__
def stream():
    while time.time() < stop:
        note('stream ' + call(base + '/')); time.sleep(0.01)
def agent(tok):
    while time.time() < stop:
        note('agent poll ' + call(f'{base}/r/{rid}/messages?since=99&wait=30', {'Authorization': f'Bearer {tok}'}, timeout=40))
ts = [threading.Thread(target=stream) for _ in range(3)] + [threading.Thread(target=agent, args=(t,)) for t in toks]
[t.start() for t in ts]
time.sleep(2); t0 = time.time()
subprocess.run(restart, shell=True, check=True)
restart_ms = int((time.time() - t0) * 1000)
[t.join() for t in ts]
print(f'{restart}: restart took {restart_ms} ms; ' + ', '.join(f'{k}: {v}' for k, v in sorted(res.items())))
