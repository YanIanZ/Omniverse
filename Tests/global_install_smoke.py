#!/usr/bin/env python3
"""Global config fixtures: preserve unrelated settings, repeat safely, refuse edited entries."""
import json, os, pathlib, subprocess, sys, tempfile, tomllib
repo = pathlib.Path(__file__).resolve().parents[1]
script = repo/'scripts/install-global.py'
assert script.is_file(), 'global installer is missing'
workspace = pathlib.Path(os.environ.get('OMNIMEM_TEST_ROOT','/Volumes/Ext/DevCache/OmniMemo/test-workspaces'))
with tempfile.TemporaryDirectory(prefix='global fixture ',dir=workspace) as folder:
    root=pathlib.Path(folder);home=root/'home';home.mkdir();state=root/'state'
    paths={
      'claude':home/'.claude.json', 'gemini':home/'.gemini/settings.json',
      'opencode':home/'.config/opencode/opencode.json',
      'vscode':home/'Library/Application Support/Code/User/mcp.json',
      'antigravity':home/'.gemini/config/mcp_config.json','cursor':home/'.cursor/mcp.json',
      'windsurf':home/'.codeium/windsurf/mcp_config.json',
      'jetbrains':home/'.ai/mcp/mcp.json',
    }
    for name,p in paths.items():
        p.parent.mkdir(parents=True,exist_ok=True)
        p.write_text(json.dumps({'keep':{'value':42},'mcpServers':{'other':{'command':'unchanged'}}}))
    codex=home/'.codex/config.toml';codex.parent.mkdir();codex.write_text('model = "keep-me"\n[mcp_servers.other]\ncommand = "unchanged"\n')
    original={p:p.read_bytes() for p in [codex,*paths.values()]}
    args=[sys.executable,str(script),'--home',str(home),'--hosts','codex,'+','.join(paths),
          '--binary','/Volumes/Ext/DevCache/OmniMemo/dist/0.3.0/omnimem','--data-dir',str(root/'data'),
          '--state-dir',str(state),'--opencode-layout','v2']
    def run(*extra,ok=True):
        p=subprocess.run(args+list(extra),text=True,capture_output=True,timeout=30)
        assert (p.returncode==0)==ok,p.stdout+p.stderr
        return p
    run()
    assert not state.exists() and all(p.read_bytes()==body for p,body in original.items())
    run('--apply')
    parsed=tomllib.loads(codex.read_text());assert parsed['model']=='keep-me'
    assert parsed['mcp_servers']['other']['command']=='unchanged'
    for name,p in paths.items():
        obj=json.loads(p.read_text());assert obj['keep']=={'value':42}
        if name=='opencode':entry=obj['mcp']['servers']['omnimemo']
        elif name=='vscode':entry=obj['servers']['omnimemo']
        else:entry=obj['mcpServers']['omnimemo']
        assert '--project' not in entry.get('args',[]) # No globally fixed project root.
    applied={p:p.read_bytes() for p in original}
    run('--apply');assert all(p.read_bytes()==body for p,body in applied.items())
    backups=list((state/'backups').iterdir());assert backups
    assert all(p.stat().st_mode & 0o077==0 for p in backups)
    # New detected hosts may be added without rewriting existing host entries.
    run('--hosts', 'codex,'+','.join(paths)+',xcode-codex', '--apply')
    assert all(p.read_bytes()==body for p,body in applied.items())
    assert (home/'Library/Developer/Xcode/CodingAssistant/codex/config.toml').exists()
    run('--with-rea','--apply',ok=False)
    # Reject the entire uninstall before touching another host when a managed entry was edited.
    obj=json.loads(paths['gemini'].read_text());obj['mcpServers']['omnimemo']['args'].append('edited')
    paths['gemini'].write_text(json.dumps(obj))
    run('--uninstall','--apply',ok=False)
    assert codex.read_bytes()==applied[codex]
    paths['gemini'].write_bytes(applied[paths['gemini']])
    # An unrelated setting added after installation must survive uninstall.
    obj=json.loads(paths['claude'].read_text());obj['new_setting']='preserve';paths['claude'].write_text(json.dumps(obj))
    run('--uninstall','--apply')
    assert 'omnimemo' not in tomllib.loads(codex.read_text())['mcp_servers']
    assert json.loads(paths['claude'].read_text())['new_setting']=='preserve'
    assert all(json.loads(p.read_text())['keep']=={'value':42} for p in paths.values())
    # Opt-in Claude hooks merge beside existing user hooks and uninstall only their own entries.
    hstate=root/'hook-state';settings=home/'.claude/settings.json';settings.parent.mkdir(exist_ok=True)
    mine={'hooks':[{'type':'command','command':'echo user-hook'}]}
    settings.write_text(json.dumps({'theme':'dark','hooks':{'UserPromptSubmit':[mine]}}))
    before=json.loads(settings.read_text())
    gemini_before=json.loads(paths['gemini'].read_text())
    hargs=[sys.executable,str(script),'--home',str(home),'--hosts','codex,gemini,opencode','--opencode-layout','v2','--with-hooks',
           '--binary','/Volumes/Ext/DevCache/OmniMemo/dist/0.3.0/omnimem','--data-dir',str(root/'data space'),
           '--state-dir',str(hstate)]
    p=subprocess.run(hargs,text=True,capture_output=True,timeout=30);assert p.returncode==0,p.stderr
    assert json.loads(settings.read_text())==before, 'preview must not write'
    p=subprocess.run(hargs+['--apply'],text=True,capture_output=True,timeout=30);assert p.returncode==0,p.stderr
    hooks=json.loads(settings.read_text())['hooks']
    assert sorted(hooks)==['SessionEnd','SessionStart','Stop','UserPromptSubmit'] and hooks['UserPromptSubmit'][0]==mine
    codex_hooks=json.loads((home/'.codex/hooks.json').read_text())['hooks']
    assert sorted(codex_hooks)==['SessionStart','Stop','UserPromptSubmit']
    assert codex_hooks['Stop'][0]['hooks'][0]['command'].endswith(' hook codex')
    # Gemini MCP entry and hooks share settings.json; both must land and unrelated keys survive.
    gem=json.loads(paths['gemini'].read_text())
    assert 'omnimemo' in gem['mcpServers'] and gem['keep']=={'value':42}
    assert sorted(gem['hooks'])==['AfterAgent','BeforeAgent','SessionEnd','SessionStart']
    # OpenCode 2.x gets no event plugin (its subscribe API stalls sessions); MCP gives presence.
    assert not (home/'.config/opencode/plugins/omnimemo.js').exists()
    command=hooks['SessionStart'][0]['hooks'][0]['command']
    assert command.endswith(' hook claude') and "'"+str(root/'data space')+"'" in command
    applied_hooks=settings.read_bytes()
    p=subprocess.run(hargs+['--apply'],text=True,capture_output=True,timeout=30);assert p.returncode==0,p.stderr
    assert settings.read_bytes()==applied_hooks
    p=subprocess.run([sys.executable,str(script),'--home',str(home),'--state-dir',str(hstate),'--uninstall','--apply'],
                     text=True,capture_output=True,timeout=30);assert p.returncode==0,p.stderr
    assert json.loads(settings.read_text())==before
    assert json.loads(paths['gemini'].read_text())==gemini_before
    assert not (home/'.config/opencode/plugins/omnimemo.js').exists()
print('PASS: global preview; Claude hooks opt-in merge/uninstall; all config schemas; unrelated settings; no fixed project; repeat apply; private backups; edited-entry refusal; preserving uninstall')
