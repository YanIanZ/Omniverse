#!/usr/bin/env python3
"""Mission Control vertical slice against the packaged release: Claude hook -> MongoDB -> Vapor
WebSocket -> React bundle, plus office reuse, WebSocket guards and Redis on/off.
Uses its own temporary Redis server; never touches a user-managed Redis or MongoDB."""
import base64, json, os, pathlib, shutil, socket, subprocess, sys, tempfile, time, urllib.error, urllib.request

binary = os.path.abspath(sys.argv[1])
om = os.path.join(os.path.dirname(binary), 'om')
workspace = os.environ.get('OMNIMEM_TEST_ROOT', '/Volumes/Ext/DevCache/OmniMemo/test-workspaces')
mongo = os.environ.get('OMNIMEM_TEST_MONGO_URI', 'mongodb://127.0.0.1:27019/omnimemo_tests')
PORT = 18788
REDIS_PORT = 16399


def ws_open(path, origin, cookie=None):
    s = socket.create_connection(('127.0.0.1', PORT), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    lines = [f'GET {path} HTTP/1.1', f'Host: 127.0.0.1:{PORT}', 'Upgrade: websocket',
             'Connection: Upgrade', f'Sec-WebSocket-Key: {key}', 'Sec-WebSocket-Version: 13']
    if origin: lines.append(f'Origin: {origin}')
    if cookie: lines.append(f'Cookie: omnimemo_session_{PORT}={cookie}')
    s.sendall(('\r\n'.join(lines) + '\r\n\r\n').encode())
    head = b''
    while b'\r\n\r\n' not in head:
        chunk = s.recv(1)
        if not chunk: break
        head += chunk
    return s, int(head.split(b' ')[1]) if head else 0


def ws_recv(s):
    """Next text message; returns None on close frame."""
    while True:
        b1, b2 = s.recv(1)[0], s.recv(1)[0]
        n = b2 & 0x7F
        if n == 126: n = int.from_bytes(s.recv(2), 'big')
        elif n == 127: n = int.from_bytes(s.recv(8), 'big')
        data = b''
        while len(data) < n: data += s.recv(n - len(data))
        if b1 & 0x0F == 8: return None
        if b1 & 0x0F == 1: return json.loads(data)


with tempfile.TemporaryDirectory(prefix='office space ', dir=workspace) as folder:
    root = pathlib.Path(folder); project = root / 'project space'; data = root / 'memory'
    project.mkdir(); subprocess.run(['git', 'init', '-q', str(project)], check=True)
    base = [om, '--data-dir', str(data), '--project', str(project)]
    env = dict(os.environ); env.pop('OMNIMEM_REDIS_URL', None)

    def run(*args, stdin=None, extra_env=None, ok=True):
        p = subprocess.run(base + list(args), input=stdin, capture_output=True, text=True, timeout=60,
                           env={**env, **(extra_env or {})})
        assert (p.returncode == 0) == ok, (args, p.stdout[-500:], p.stderr[-500:])
        return p

    run('init', '--mongo-uri', mongo)
    # Bare `om` is status only and never starts a server.
    status = json.loads(run().stdout)
    assert status['office'].startswith('not running') and not list((data / 'servers').glob('*.json'))

    # Claude hook flow (stdin JSON as Claude Code sends it); fail-open on garbage.
    def hook(event, session='sess-1', **kw):
        payload = json.dumps({'hook_event_name': event, 'session_id': session, 'cwd': str(project), **kw})
        p = subprocess.run([om, '--data-dir', str(data), 'hook', 'claude'], input=payload,
                           capture_output=True, text=True, timeout=30, env=env)
        assert p.returncode == 0, p.stderr
        return p.stdout
    assert subprocess.run([om, 'hook', 'claude'], input=b'not json', capture_output=True, timeout=30).returncode == 0
    assert hook('SessionStart') == ''
    assert hook('UserPromptSubmit', prompt='hi') == '', 'empty project must inject nothing'
    run('memory', 'save', '--title', 'Stack decision', '--content', 'Swift core, Vapor server, React UI')
    first = hook('UserPromptSubmit', prompt='continue')
    assert first.startswith('OmniMemo project context') and 'Stack decision' in first, first
    assert hook('UserPromptSubmit', prompt='again') == '', 'unchanged capsule repeated'
    agents = json.loads(run('agents').stdout)
    assert [(a['agent'], a['status'], a['source']) for a in agents] == [('claude', 'working', 'claude_hook')]
    # A subagent is its own session, linked to the one that spawned it; its end is no session handoff.
    hook('SubagentStart', session='agent-1', spawned_by='sess-1', agent_type='Explore agent')
    sub = [a for a in json.loads(run('agents').stdout) if a['session_id'] == 'agent-1']
    assert sub and sub[0]['spawned_by'] == 'sess-1' and sub[0]['agent_type'] == 'Explore-agent', sub
    hook('SubagentStop', session='agent-1', spawned_by='sess-1')
    assert [a['status'] for a in json.loads(run('agents').stdout) if a['session_id'] == 'agent-1'] == ['offline']
    hook('SubagentStart', session='agent-2', spawned_by='sess-1')  # interrupted: never stops

    # Real Redis (temporary, isolated port) to prove the optional live signal works.
    redis = subprocess.Popen(['redis-server', '--port', str(REDIS_PORT), '--bind', '127.0.0.1', '--save', '',
                              '--appendonly', 'no'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(0.5)
        renv = {'OMNIMEM_REDIS_URL': f'redis://127.0.0.1:{REDIS_PORT}'}
        env.update(renv)
        office = json.loads(run('office', '--no-open', '--port', str(PORT)).stdout)
        again = json.loads(run('office', '--no-open', '--port', str(PORT)).stdout)
        assert office['reused'] == 'false' and again['reused'] == 'true' and office['pid'] == again['pid']
        token = (data / 'server-token').read_text()
        req = urllib.request.Request(f'http://127.0.0.1:{PORT}/api/v1/health', headers={'Authorization': 'Bearer ' + token})
        health = json.loads(urllib.request.urlopen(req, timeout=5).read())
        assert health['redis'] == 'connected', health

        # React production bundle is served by Vapor; client routes fall back to index.html.
        for path in ['/', '/office']:
            html = urllib.request.urlopen(f'http://127.0.0.1:{PORT}{path}', timeout=5).read().decode()
            assert '<div id="root">' in html, path
        assets = list((pathlib.Path(binary).parent / 'frontend/assets').glob('*.js'))
        bundle = ''.join(a.read_text() for a in assets)
        assert assets and token not in bundle and 'mongodb://' not in bundle and 'redis://' not in bundle

        # Sign in like the browser: /auth mints a session cookie that is not the server token.
        class Keep(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *a, **k): return None
        mint = urllib.request.Request(f'http://127.0.0.1:{PORT}/api/v1/login-code', method='POST', headers={'Authorization': 'Bearer ' + token})
        code = json.loads(urllib.request.urlopen(mint, timeout=5).read())['code']
        try: urllib.request.build_opener(Keep).open(f'http://127.0.0.1:{PORT}/auth?code={code}', timeout=5)
        except urllib.error.HTTPError as e: signin = e.headers.get('Set-Cookie', '')
        session = signin.split(f'omnimemo_session_{PORT}=', 1)[1].split(';', 1)[0]
        assert session and session != token, 'the browser cookie must not carry the server token'

        # WebSocket guards: bad origin, missing auth, the raw token as cookie, out-of-scope project.
        origin = f'http://127.0.0.1:{PORT}'
        _, code = ws_open('/ws/v1/live', origin, token); assert code == 401, code
        token = session
        _, code = ws_open('/ws/v1/live', 'http://evil.test', token); assert code == 403, code
        _, code = ws_open('/ws/v1/live', origin); assert code == 401, code
        _, code = ws_open('/ws/v1/live', None, token); assert code == 403, code
        s, code = ws_open('/ws/v1/live?project_id=other', origin, token); assert code == 101
        assert ws_recv(s) is None, 'out-of-scope project must be closed'

        # Live event: a CLI task transition reaches the browser socket via MongoDB (+Redis hint).
        s, code = ws_open('/ws/v1/live?project_id=' + health['project_id'], origin, token)
        assert code == 101 and ws_recv(s)['type'] == 'hello'
        started = time.time()
        task = json.loads(run('tasks', 'add', 'Wire the hook').stdout)
        event = ws_recv(s)
        latency = time.time() - started
        assert event['type'] == 'task.updated' and event['entity_id'] == task['id'], event
        run('tasks', 'move', task['id'], 'doing', '--revision', '1')
        assert ws_recv(s)['data']['status'] == 'doing'
        run('tasks', 'move', task['id'], 'done', '--revision', '1', ok=False)  # stale revision
        hook('SessionEnd')
        assert ws_recv(s)['data']['status'] == 'offline'
        s.close()
        assert [a['status'] for a in json.loads(run('agents').stdout) if a['session_id'] == 'agent-2'] == ['offline']
    finally:
        redis.terminate(); redis.wait(timeout=10)

    # Redis gone: durable writes and server still work (degraded to MongoDB polling).
    run('tasks', 'add', 'Works without Redis')
    assert len(json.loads(run('tasks').stdout)) == 2

    # The reported Redis state follows the real connection, and a restarted Redis is resubscribed.
    bearer = (data / 'server-token').read_text()
    def redis_state():
        req = urllib.request.Request(f'http://127.0.0.1:{PORT}/api/v1/health', headers={'Authorization': 'Bearer ' + bearer})
        return json.loads(urllib.request.urlopen(req, timeout=5).read())['redis']
    def wait_for(state, seconds):
        end = time.time() + seconds
        while time.time() < end and redis_state() != state: time.sleep(0.5)
        return redis_state()
    assert wait_for('unavailable', 5) == 'unavailable', 'a dropped Redis must not be reported as connected'
    redis = subprocess.Popen(['redis-server', '--port', str(REDIS_PORT), '--bind', '127.0.0.1', '--save', '',
                              '--appendonly', 'no'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for('connected', 20) == 'connected', 'a restarted Redis must be resubscribed'
    finally:
        redis.terminate(); redis.wait(timeout=10)
    # A second project gets its own server on the next free port; each serves only its own project.
    other = root / 'other project'; other.mkdir(); subprocess.run(['git', 'init', '-q', str(other)], check=True)
    second = json.loads(subprocess.run([om, '--data-dir', str(data), '--project', str(other), 'office', '--no-open',
                                        '--port', str(PORT)], capture_output=True, text=True, timeout=60, env=env,
                                       check=True).stdout)
    first = json.loads(run('office', '--no-open', '--port', str(PORT)).stdout)
    assert first['reused'] == 'true' and second['reused'] == 'false' and second['url'] != first['url'], (first, second)
    def health_of(url):
        req = urllib.request.Request(url + 'api/v1/health', headers={'Authorization': 'Bearer ' + bearer})
        return json.loads(urllib.request.urlopen(req, timeout=5).read())
    assert health_of(first['url'])['project_name'] == 'project space'
    assert health_of(second['url'])['project_name'] == 'other project'
    stop = json.loads(run('stop', '--all').stdout)
    assert stop['server'] == 'stopped' and len(stop['pid'].split(',')) == 2, stop
    assert not list((data / 'servers').glob('*.json'))
    assert json.loads(run('stop').stdout)['server'] == 'not running'

print(f'PASS: Claude hook wake/first-prompt once/end; subagent session; office reuse; React served by Vapor; '
      f'WS origin/auth/scope guards; live task event ({latency:.2f}s with Redis); CAS conflict; '
      f'Redis outage keeps MongoDB writes; Redis state honest and resubscribed; one server per project; om stop --all')
