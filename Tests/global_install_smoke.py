#!/usr/bin/env python3
"""Global config fixtures: preserve unrelated settings, repeat safely, refuse edited entries."""
import json, os, pathlib, shlex, subprocess, sys, tempfile, tomllib
repo = pathlib.Path(__file__).resolve().parents[1]
script = repo/'scripts/install-global.py'
assert script.is_file(), 'global installer is missing'
workspace = pathlib.Path(os.environ.get('OMNIMEM_TEST_ROOT','/Volumes/Ext/DevCache/OmniMemo/test-workspaces'))
with tempfile.TemporaryDirectory(prefix='global fixture ',dir=workspace) as folder:
    root=pathlib.Path(folder);home=root/'home';home.mkdir();state=root/'state'
    os.environ.update(HOME=str(home), CLAUDE_CONFIG_DIR=str(home/'.claude'), CODEX_HOME=str(home/'.codex'), XDG_CONFIG_HOME=str(home/'.config'))
    binary=root/"om binary's fixture";binary.write_text('fixture only; never executed\n')
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
          '--binary',str(binary),'--data-dir',str(root/'data'),
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
    # Opt-in lifecycle: hooks for Codex and Gemini only. Claude Code gets the plugin instead, so its
    # settings (and the user's own hooks there) are never written.
    hstate=root/'hook-state';settings=home/'.claude/settings.json';settings.parent.mkdir(exist_ok=True)
    mine={'hooks':[{'type':'command','command':'echo user-hook'}]}
    settings.write_text(json.dumps({'theme':'dark','hooks':{'UserPromptSubmit':[mine]}}))
    before=json.loads(settings.read_text())
    gemini_before=json.loads(paths['gemini'].read_text())
    hargs=[sys.executable,str(script),'--home',str(home),'--hosts','codex,gemini,opencode','--opencode-layout','v2','--with-hooks',
           '--binary',str(binary),'--data-dir',str(root/'data space'),
           '--state-dir',str(hstate)]
    p=subprocess.run(hargs,text=True,capture_output=True,timeout=30);assert p.returncode==0,p.stderr
    assert json.loads(settings.read_text())==before, 'preview must not write'
    p=subprocess.run(hargs+['--apply'],text=True,capture_output=True,timeout=30);assert p.returncode==0,p.stderr
    assert json.loads(settings.read_text())==before, 'Claude settings hooks are not installed'
    codex_hooks=json.loads((home/'.codex/hooks.json').read_text())['hooks']
    assert sorted(codex_hooks)==['PostToolUse','PreToolUse','SessionStart','Stop','UserPromptSubmit']
    assert codex_hooks['Stop'][0]['hooks'][0]['command'].endswith(' hook codex')
    # Gemini MCP entry and hooks share settings.json; both must land and unrelated keys survive.
    gem=json.loads(paths['gemini'].read_text())
    assert 'omnimemo' in gem['mcpServers'] and gem['keep']=={'value':42}
    assert sorted(gem['hooks'])==['AfterAgent','AfterTool','BeforeAgent','BeforeTool','SessionEnd','SessionStart']
    # OpenCode 2.x plugin: tool/session hooks and a detached event stream (never a callback subscribe).
    plugin=(home/'.config/opencode/plugins/omnimemo.js').read_text()
    assert 'ctx.tool.hook("execute.before"' in plugin and 'ctx.tool.hook("execute.after"' in plugin
    assert 'for await (const ev of ctx.event.subscribe' in plugin and 'api.event' not in plugin
    command=codex_hooks['SessionStart'][0]['hooks'][0]['command']
    assert command.endswith(' hook codex') and "'"+str(root/'data space')+"'" in command
    applied_hooks=(home/'.codex/hooks.json').read_bytes()
    p=subprocess.run(hargs+['--apply'],text=True,capture_output=True,timeout=30);assert p.returncode==0,p.stderr
    assert (home/'.codex/hooks.json').read_bytes()==applied_hooks
    p=subprocess.run([sys.executable,str(script),'--home',str(home),'--state-dir',str(hstate),'--uninstall','--apply'],
                     text=True,capture_output=True,timeout=30);assert p.returncode==0,p.stderr
    assert json.loads(settings.read_text())==before
    assert json.loads(paths['gemini'].read_text())==gemini_before
    assert not (home/'.config/opencode/plugins/omnimemo.js').exists()
    # Status-line opt-in shares the hook settings file and uses shell-safe paths.
    sstate=root/'statusline-state'
    sargs=[sys.executable,str(script),'--home',str(home),'--hosts','claude','--with-hooks','--with-statusline',
           '--binary',str(binary),'--data-dir',str(root/"data's space"),'--state-dir',str(sstate)]
    def statusline_run(*extra):
        result=subprocess.run(sargs+list(extra),text=True,capture_output=True,timeout=30)
        assert result.returncode==0,result.stdout+result.stderr
        return result
    expected={'type':'command','command':shlex.quote(str(binary))+' --data-dir '+shlex.quote(str(root/"data's space"))+' statusline claude'}
    settings_before=settings.read_bytes()
    statusline_run()
    assert settings.read_bytes()==settings_before and not sstate.exists()
    statusline_run('--apply')
    installed=settings.read_bytes()
    assert json.loads(installed)['statusLine']==expected
    assert any(p.read_bytes()==settings_before for p in (sstate/'backups').iterdir())
    statusline_run('--apply')
    assert settings.read_bytes()==installed
    statusline_run('--uninstall','--apply')
    assert json.loads(settings.read_text())==before
    # A pre-existing user status line is neither replaced nor claimed, even if identical.
    for existing in [{'type':'command','command':'echo user-status'}, expected, None]:
        settings.write_text(json.dumps({**before,'statusLine':existing}))
        original_statusline=settings.read_bytes()
        result=statusline_run('--apply')
        assert 'manually' in result.stdout and 'statusline claude' in result.stdout
        assert json.loads(settings.read_text())['statusLine']==existing
        assert not any(e['kind']=='statusline' for e in json.loads((sstate/'manifest.json').read_text())['entries'])
        statusline_run('--uninstall','--apply')
        assert json.loads(settings.read_text())==json.loads(original_statusline)
    # Standalone opt-in leaves an edited or removed statusLine untouched on uninstall.
    for replacement in [{'type':'command','command':'echo replacement'}, None]:
        settings.write_text(json.dumps(before))
        statusline_run('--apply')
        obj=json.loads(settings.read_text())
        if replacement is None:del obj['statusLine']
        else:obj['statusLine']=replacement
        obj['unrelated']='preserved'
        settings.write_text(json.dumps(obj))
        statusline_run('--uninstall','--apply')
        assert json.loads(settings.read_text())=={**before,**({'statusLine':replacement} if replacement else {}),'unrelated':'preserved'}
    # Status-line-only installation also works without hooks or a settings file.
    settings.unlink()
    sargs.remove('--with-hooks')
    statusline_run('--apply')
    statusline_run('--uninstall','--apply')
    assert 'statusLine' not in json.loads(settings.read_text())
# The Codex desktop app (~/.codex) is its own host only when the CLI's CODEX_HOME is elsewhere.
import importlib.util
spec=importlib.util.spec_from_file_location('installer',script);installer=importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)
with tempfile.TemporaryDirectory(dir=workspace) as folder:
    h=pathlib.Path(folder);(h/'.codex').mkdir();(h/'cli').mkdir()
    os.environ['CODEX_HOME']=str(h/'cli');assert installer.codex_app_home(h,False)==h/'.codex'
    assert 'codex-app' in installer.locations(h,False,'v2')
    os.environ['CODEX_HOME']=str(h/'.codex');assert installer.codex_app_home(h,False) is None
    assert installer.codex_app_home(h,True) is None, 'fixture homes never add the app host'
print('PASS: global config schemas, hooks and status-line opt-in; preview; quoting; backups; repeat apply; preserve existing/edited status lines; owned uninstall; Codex app home as its own host')
