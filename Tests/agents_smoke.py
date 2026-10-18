#!/usr/bin/env python3
"""Host adapters without paid sessions: MCP presence (clientInfo), Codex/Gemini/OpenCode hook
payloads in each host's documented shape, approvals requested by an agent."""
import json, os, pathlib, signal, subprocess, sys, tempfile, time
from mcp_smoke import Session

binary = os.path.abspath(sys.argv[1])
workspace = os.environ.get('OMNIMEM_TEST_ROOT', '/Volumes/Ext/DevCache/OmniMemo/test-workspaces')
mongo = os.environ.get('OMNIMEM_TEST_MONGO_URI', 'mongodb://127.0.0.1:27019/omnimemo_tests')

with tempfile.TemporaryDirectory(prefix='agents space ', dir=workspace) as folder:
    root = pathlib.Path(folder); project = root / 'project'; data = root / 'data'
    project.mkdir(); subprocess.run(['git', 'init', '-q', str(project)], check=True)
    base = [binary, '--data-dir', str(data), '--project', str(project)]
    def om(*args):
        p = subprocess.run(base + list(args), capture_output=True, text=True, timeout=60)
        assert p.returncode == 0, (args, p.stderr)
        return json.loads(p.stdout) if p.stdout.strip() else None
    def sessions():
        return {(a['agent'], a['source']): a['status'] for a in om('agents')}
    def hook(host, event, session, **extra):
        payload = json.dumps({'hook_event_name': event, 'session_id': session, 'cwd': str(project), **extra})
        p = subprocess.run([binary, '--data-dir', str(data), 'hook', host], input=payload,
                           capture_output=True, text=True, timeout=30)
        assert p.returncode == 0, p.stderr
        return p.stdout
    om('init', '--mongo-uri', mongo)
    om('memory', 'save', '--title', 'Build command', '--content', 'Use scripts/package.sh for releases')

    # MCP first use: the client names itself in initialize; tool use marks it active.
    codex = Session(binary, data, project, 'codex-mcp-client')
    assert sessions()[('codex', 'mcp')] == 'waiting'
    codex.tool('memory_checkpoint', {'done': ['Read the build notes'], 'next': ['Package']})
    assert sessions()[('codex', 'mcp')] == 'working'
    events = om('tasks') is not None and om('agents')  # keep the CLI warm
    codex.close()
    assert sessions()[('codex', 'mcp')] == 'offline', 'stdin EOF must record disconnect'
    # A host stopping the server with SIGTERM still records the disconnect.
    gem = Session(binary, data, project, 'gemini-cli-mcp-client')
    gem.proc.send_signal(signal.SIGTERM); gem.proc.wait(timeout=10)
    assert sessions()[('gemini', 'mcp')] == 'offline', 'SIGTERM must record disconnect'

    # Codex hooks.json events (Claude-compatible stdin): plain-text context once per change.
    assert hook('codex', 'SessionStart', 'cx-1') == ''
    first = hook('codex', 'UserPromptSubmit', 'cx-1', prompt='package it')
    assert first.startswith('OmniMemo project context') and 'Build command' in first
    assert hook('codex', 'UserPromptSubmit', 'cx-1', prompt='again') == ''
    hook('codex', 'Stop', 'cx-1')
    assert sessions()[('codex', 'codex_hook')] == 'waiting'

    # Gemini CLI reads JSON hookSpecificOutput.additionalContext.
    hook('gemini', 'SessionStart', 'gm-1')
    reply = json.loads(hook('gemini', 'BeforeAgent', 'gm-1', prompt='hi'))
    assert 'Build command' in reply['hookSpecificOutput']['additionalContext']
    assert reply['hookSpecificOutput']['hookEventName'] == 'BeforeAgent'
    hook('gemini', 'SessionEnd', 'gm-1')
    assert sessions()[('gemini', 'gemini_hook')] == 'offline'

    # OpenCode plugin events: presence only, never stdout (the plugin cannot inject text).
    assert hook('opencode', 'session.created', 'ses_1') == ''
    assert hook('opencode', 'chat.message', 'ses_1') == ''
    assert sessions()[('opencode', 'opencode_hook')] == 'working'
    hook('opencode', 'session.deleted', 'ses_1')
    assert sessions()[('opencode', 'opencode_hook')] == 'offline'
    assert hook('cursor', 'SessionStart', 'x') == '' and ('cursor', 'cursor_hook') not in sessions()

    # Agents may request approvals; the CLI offers no way to decide them.
    req = om('--agent', 'codex', 'approvals', 'request', 'Push main to origin', '--reason', 'release')
    assert req['status'] == 'pending' and req['requested_by'] == 'codex'
    assert om('approvals', 'show', req['id'])['id'] == req['id']
    help_text = subprocess.run([binary, 'approvals', '--help'], capture_output=True, text=True).stdout
    assert 'decide' not in help_text.lower().split('subcommands')[-1]
print('PASS: MCP clientInfo presence (ready/active/EOF/SIGTERM); Codex hook text capsule once; '
      'Gemini JSON additionalContext; OpenCode plugin events presence-only; unknown host ignored; agent approval request')
