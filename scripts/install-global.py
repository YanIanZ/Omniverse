#!/usr/bin/env python3
"""Merge supported user-level MCP configurations with private backups and owned uninstall."""
import argparse, copy, hashlib, json, os, pathlib, re, shlex, shutil, subprocess, sys, tempfile, time, tomllib

ROOT = pathlib.Path(__file__).resolve().parents[1]
BEGIN = '# BEGIN OmniMemo global installer v1\n'
END = '# END OmniMemo global installer v1\n'

def digest(body): return hashlib.sha256(body).hexdigest()
def encoded(value): return (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode()
def read(path): return path.read_bytes() if path.exists() else None

def atomic(path, body, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.omnimemo-', dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'wb') as stream: stream.write(body)
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)

def hosts(home):
    apps = [pathlib.Path('/Applications'), home/'Applications']
    app = lambda name: any((base/(name+'.app')).is_dir() for base in apps)
    found = []
    for name, command, folder in [('codex','codex','.codex'),('claude','claude','.claude'),
            ('gemini','gemini','.gemini'),('opencode','opencode','.config/opencode')]:
        if shutil.which(command) or (home/folder).exists(): found.append(name)
    for name, appname, config in [('vscode','Visual Studio Code','.vscode'),
            ('antigravity','Antigravity','.gemini/config/mcp_config.json'),
            ('cursor','Cursor','.cursor/mcp.json'),('windsurf','Windsurf','.codeium/windsurf/mcp_config.json'),
            ('copilot-xcode','GitHub Copilot for Xcode','.config/github-copilot/xcode/mcp.json')]:
        if app(appname) or (home/config).exists(): found.append(name)
    if app('IntelliJ IDEA') or (home/'.ai/mcp/mcp.json').exists():found.append('jetbrains')
    if app('Xcode'): found += ['xcode-codex','xcode-claude']
    return found

def locations(home, custom_home, layout):
    codex = home/'.codex' if custom_home else pathlib.Path(os.environ.get('CODEX_HOME', str(home/'.codex')))
    config = home/'.config' if custom_home else pathlib.Path(os.environ.get('XDG_CONFIG_HOME', str(home/'.config')))
    antigravity = home/'.gemini/config/mcp_config.json'
    legacy = home/'.gemini/antigravity/mcp_config.json'
    if legacy.exists() and not antigravity.exists(): antigravity = legacy
    xcode = home/'Library/Developer/Xcode/CodingAssistant'
    return {
        'codex':(codex/'config.toml','toml',()),
        'claude':(home/'.claude.json','json',('mcpServers',)),
        'gemini':(home/'.gemini/settings.json','json',('mcpServers',)),
        'opencode':(config/'opencode/opencode.json','json',('mcp','servers') if layout=='v2' else ('mcp',)),
        'vscode':(home/'Library/Application Support/Code/User/mcp.json','json',('servers',)),
        'antigravity':(antigravity,'json',('mcpServers',)),
        'cursor':(home/'.cursor/mcp.json','json',('mcpServers',)),
        # The Global destination displayed by the installed JetBrains AI Assistant UI.
        'jetbrains':(home/'.ai/mcp/mcp.json','json',('mcpServers',)),
        'windsurf':(home/'.codeium/windsurf/mcp_config.json','json',('mcpServers',)),
        'copilot-xcode':(home/'.config/github-copilot/xcode/mcp.json','json',('servers',)),
        'xcode-codex':(xcode/'codex/config.toml','toml',()),
        'xcode-claude':(xcode/'ClaudeAgentConfig/.claude.json','json',('mcpServers',)),
    }

def servers(host, binary, data, launcher, rea):
    result = {}
    for name, mode in [('omnimemo','memory')] + ([('omnimemo-rea','rea')] if rea else []):
        entry = {'command':str(launcher),'args':[str(binary),str(data),mode]}
        if host=='opencode': entry = {'type':'local','command':[entry['command'],*entry['args']]}
        elif host=='vscode': entry.update(type='stdio',cwd='${workspaceFolder}')
        result[name] = entry
    return result

# Each host's own documented lifecycle events; every command fails open and never blocks a prompt.
HOOK_EVENTS={
    'claude':('SessionStart','UserPromptSubmit','Stop','SessionEnd'),
    'codex':('SessionStart','UserPromptSubmit','Stop'),
    'gemini':('SessionStart','BeforeAgent','AfterAgent','SessionEnd'),
}

def host_hooks(host, binary, data):
    command=shlex.quote(str(binary))+' --data-dir '+shlex.quote(str(data))+' hook '+host
    return {event:{'hooks':[{'type':'command','command':command,'timeout':10}]} for event in HOOK_EVENTS[host]}

def opencode_plugin(binary, data, layout='v2'):
    # OpenCode exposes lifecycle events only to plugins; this one forwards them to `om hook opencode`.
    head=('// Installed by the OmniMemo global installer; uninstall with its --uninstall.\n'
          'import { spawn } from "node:child_process";\n'
          'const BIN = '+json.dumps(str(binary))+';\nconst DATA = '+json.dumps(str(data))+';\n'
          'function send(event, sessionID, directory) {\n'
          '  if (!sessionID || !directory) return;\n'
          '  try {\n'
          '    const child = spawn(BIN, ["--data-dir", DATA, "hook", "opencode"], { stdio: ["pipe", "ignore", "ignore"] });\n'
          '    child.on("error", () => {});\n'
          '    child.stdin.end(JSON.stringify({ hook_event_name: event, session_id: sessionID, cwd: directory }));\n'
          '  } catch {}\n'
          '}\n')
    if layout=='v1':
        return head+('export const OmniMemoPresence = async ({ directory }) => ({\n'
                     '  event: async ({ event }) => {\n'
                     '    const type = event?.type;\n'
                     '    if (type === "session.created" || type === "session.deleted") send(type, event.properties?.info?.id, directory);\n'
                     '    else if (type === "session.idle") send(type, event.properties?.sessionID, directory);\n'
                     '  },\n'
                     '  "chat.message": async (input) => send("chat.message", input?.sessionID, directory),\n'
                     '});\n')
    # OpenCode 2.x: default export with id + setup(api); events carry their own location.
    return head+('const field = (e, k) => e?.[k] ?? e?.data?.[k] ?? e?.properties?.[k];\n'
                 'const sessionOf = (e) => field(e, "sessionID") ?? field(e, "info")?.id ?? field(e, "id");\n'
                 'const dirOf = (e) => field(e, "location")?.directory ?? e?.location?.directory ?? field(e, "directory");\n'
                 'const dirs = new Map();\n'
                 'export default {\n'
                 '  id: "omnimemo-presence",\n'
                 '  setup(api) {\n'
                 '    // subscribe() can run for the life of the stream: never make setup wait on it.\n'
                 '    const running = api.event.subscribe((e) => {\n'
                 '      const id = sessionOf(e);\n'
                 '      if (!id) return;\n'
                 '      const dir = dirOf(e) ?? dirs.get(id);\n'
                 '      if (dir) dirs.set(id, dir);\n'
                 '      const status = field(e, "status")?.type;\n'
                 '      if (e?.type === "session.created") send("session.created", id, dir);\n'
                 '      else if (e?.type === "session.status" && status === "busy") send("chat.message", id, dir);\n'
                 '      else if (e?.type === "session.idle" || (e?.type === "session.status" && status === "idle")) send("session.idle", id, dir);\n'
                 '      else if (e?.type === "session.deleted" || e?.type === "session.removed") { send("session.deleted", id, dir); dirs.delete(id); }\n'
                 '    });\n'
                 '    if (typeof running === "function") return running;\n'
                 '    Promise.resolve(running).catch(() => {});\n'
                 '  },\n'
                 '};\n')

def plan_file(path, original, expected, uninstall):
    body=expected.encode()
    if uninstall:
        if original!=body:raise ValueError('Managed file changed or missing: '+str(path))
        return path, original, None
    if original is not None and original!=body:raise ValueError('Existing file needs review: '+str(path))
    return path, original, body

def plan_hooks(path, original, expected, uninstall):
    obj=json.loads((original or b'{}').decode() or '{}')
    if not isinstance(obj,dict) or not isinstance(obj.setdefault('hooks',{}),dict):
        raise ValueError('Unexpected Claude settings schema: '+str(path))
    hooks=obj['hooks']
    for event, group in expected.items():
        groups=hooks.setdefault(event,[])
        if not isinstance(groups,list):raise ValueError('Unexpected Claude hook schema: '+str(path))
        ours=[g for g in groups if ' hook ' in json.dumps(g) and json.dumps(group['hooks'][0]['command']) in json.dumps(g)]
        if uninstall:
            if ours!=[group]:raise ValueError('Managed Claude hook changed or missing: '+str(path))
            groups.remove(group)
            if not groups:del hooks[event]
        elif ours and ours!=[group]:raise ValueError('Existing OmniMemo Claude hook needs review: '+str(path))
        elif not ours:groups.append(group)
    if not hooks:del obj['hooks']
    if original is not None and json.loads(original)==obj:return path, original, original
    return path, original, encoded(obj)

def plan_entry(path, kind, keys, expected, uninstall, original=...):
    # Intentional host-directory symlinks (e.g. ~/.claude -> Ext) are preserved.
    path = path.resolve()
    if original is ...: original = read(path)
    if kind=='hooks':return plan_hooks(path, original, expected, uninstall)
    if kind=='file':return plan_file(path, original, expected, uninstall)
    text = (original or b'').decode()
    if kind=='toml':
        parsed = tomllib.loads(text)
        current = parsed.get('mcp_servers',{})
        if uninstall:
            for name, entry in expected.items():
                if current.get(name)!=entry: raise ValueError('Managed TOML entry changed or missing: '+str(path))
            start=text.find(BEGIN);end=text.find(END)
            if start<0 or end<start: raise ValueError('Managed TOML block missing: '+str(path))
            block=BEGIN
            for name, entry in expected.items():
                block+='[mcp_servers.'+json.dumps(name)+']\n'
                block+='command = '+json.dumps(entry['command'])+'\nargs = '+json.dumps(entry['args'])+'\n'
            if text[start:end+len(END)]!=block+END:raise ValueError('Managed TOML block was edited: '+str(path))
            new=text[:start]+text[end+len(END):]
        else:
            if all(current.get(n)==e for n,e in expected.items()):return path, original, original
            if BEGIN in text or any(n in current for n in expected):raise ValueError('Existing OmniMemo TOML entry needs review: '+str(path))
            block=BEGIN
            for name, entry in expected.items():
                block+='[mcp_servers.'+json.dumps(name)+']\n'
                block+='command = '+json.dumps(entry['command'])+'\nargs = '+json.dumps(entry['args'])+'\n'
            new=text+('' if not text or text.endswith('\n') else '\n')+block+END
        tomllib.loads(new)
        return path, original, new.encode()
    obj=json.loads(text or '{}')
    if not isinstance(obj,dict):raise ValueError('Expected config object: '+str(path))
    target=obj
    for key in keys:
        if key not in target:target[key]={}
        target=target[key]
        if not isinstance(target,dict):raise ValueError('Unexpected config schema: '+str(path))
    for name, entry in expected.items():
        if uninstall:
            if target.get(name)!=entry:raise ValueError('Managed JSON entry changed or missing: '+str(path))
            del target[name]
        else:
            if name in target and target[name]!=entry:raise ValueError('Existing OmniMemo JSON entry needs review: '+str(path))
            target[name]=entry
    if original is not None and json.loads(text)==obj:return path, original, original
    return path, original, encoded(obj)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--binary',type=pathlib.Path)
    p.add_argument('--data-dir',type=pathlib.Path)
    p.add_argument('--state-dir',type=pathlib.Path,required=True)
    p.add_argument('--home',type=pathlib.Path,help='Explicit alternate home (fixtures/staging).')
    p.add_argument('--hosts',default='auto')
    p.add_argument('--opencode-layout',choices=['auto','v1','v2'],default='auto')
    p.add_argument('--with-rea',action='store_true')
    p.add_argument('--install-skills',action='store_true')
    p.add_argument('--with-hooks',action='store_true',help='Also add Claude Code session/prompt hooks (opt-in).')
    p.add_argument('--uninstall',action='store_true')
    p.add_argument('--apply',action='store_true',help='Apply; otherwise preview without writes.')
    args=p.parse_args()
    home=(args.home or pathlib.Path.home()).resolve();state=args.state_dir.resolve()
    if args.apply and str(state).startswith('/Volumes/Ext/') and not os.path.ismount('/Volumes/Ext'):
        raise ValueError('External disk is unavailable; refusing shadow state.')
    manifest_path=state/'manifest.json'
    manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else None
    launcher=state/'launch-mcp.sh'
    if args.uninstall:
        if not manifest:raise ValueError('No managed global installation manifest.')
        entries=manifest['entries']
    else:
        if not args.binary or not args.data_dir:raise ValueError('--binary and --data-dir are required.')
        binary=args.binary.absolute();data=args.data_dir.absolute()
        if not binary.is_file():raise ValueError('Installed executable is missing.')
        selected=hosts(home) if args.hosts=='auto' else args.hosts.split(',')
        layout=args.opencode_layout
        if layout=='auto':
            if 'opencode' in selected:
                version=subprocess.check_output(['opencode','--version'],text=True,timeout=10)
                match=re.search(r'(?:^|\s)v?(\d+)\.',version)
                if not match:raise ValueError('Unknown OpenCode version; select layout explicitly.')
                layout='v2' if int(match[1])>=2 else 'v1'
            else:layout='v1'
        available=locations(home,args.home is not None,layout)
        entries=[]
        for host in selected:
            if host not in available:raise ValueError('Unsupported host: '+host)
            path,kind,keys=available[host]
            expected=servers(host,binary,data,launcher,args.with_rea)
            entries.append({'host':host,'path':str(path.resolve()),'kind':kind,'keys':keys,'servers':expected})
        if args.with_hooks:
            claude_dir=home/'.claude' if args.home else pathlib.Path(os.environ.get('CLAUDE_CONFIG_DIR',str(home/'.claude')))
            codex_dir=home/'.codex' if args.home else pathlib.Path(os.environ.get('CODEX_HOME',str(home/'.codex')))
            config_dir=home/'.config' if args.home else pathlib.Path(os.environ.get('XDG_CONFIG_HOME',str(home/'.config')))
            hook_files={'claude':claude_dir/'settings.json','codex':codex_dir/'hooks.json','gemini':home/'.gemini/settings.json'}
            # Hooks are added only for hosts already selected for MCP, plus Claude as before.
            for host in ['claude']+[h for h in ('codex','gemini') if h in selected]:
                entries.append({'host':host+'-hooks','path':str(hook_files[host].resolve()),'kind':'hooks','keys':['hooks'],'servers':host_hooks(host,binary,data)})
            # OpenCode 2.x: any plugin using api.event.subscribe stalled sessions in 2.0.31 (verified),
            # so presence comes from the MCP connection only; the event plugin ships for 1.x.
            if 'opencode' in selected and layout=='v1':
                entries.append({'host':'opencode-plugin','path':str((config_dir/'opencode/plugins/omnimemo.js').resolve()),'kind':'file','keys':[],'servers':opencode_plugin(binary,data,layout)})
        if manifest and any(previous not in json.loads(json.dumps(entries)) for previous in manifest['entries']):
            raise ValueError('Global installation profile changed; uninstall the previous profile first.')
    # Entries sharing one file (e.g. Gemini MCP + hooks) are planned as a chain on that file.
    chained={}
    for e in entries:
        path=pathlib.Path(e['path']).resolve()
        start=chained[path][1] if path in chained else read(path)
        _,_,new=plan_entry(path,e['kind'],e['keys'],e['servers'],args.uninstall,original=start)
        chained[path]=(chained[path][0] if path in chained else read(path),new)
    planned=[(path,old,new) for path,(old,new) in chained.items()]
    print(json.dumps({'apply':args.apply,'uninstall':args.uninstall,'hosts':[e['host'] for e in entries],
          'files_to_change':[str(path) for path,old,new in planned if old!=new],
          'project_scope':'launch Git root or explicit OMNIMEM_PROJECT; no fallback project',
          'manual_imports':['Other/older JetBrains profiles may require a Global import','Sublime Text requires an MCP-capable agent/plugin'],
          'state_dir':str(state)},indent=2))
    if not args.apply:return
    state.mkdir(parents=True,exist_ok=True,mode=0o700);state.chmod(0o700)
    lock=state/'.lock'
    try:lock.mkdir()
    except FileExistsError:raise ValueError('Another global installation is active; review its lock.')
    changed=[]
    try:
        backups=state/'backups';backups.mkdir(exist_ok=True,mode=0o700);backups.chmod(0o700)
        for path,old,new in planned:
            if read(path)!=old:raise ValueError('Config changed after preview; retry: '+str(path))
        if not args.uninstall:
            atomic(launcher,(ROOT/'scripts/global-mcp.sh').read_bytes(),0o700)
        for path,old,new in planned:
            if old==new:continue
            if read(path)!=old:raise ValueError('Config changed during installation; retry: '+str(path))
            if old is not None:atomic(backups/(str(time.time_ns())+'-'+digest(str(path).encode())[:12]),old)
            if new is None:path.unlink()
            else:atomic(path,new)
            changed.append((path,old,new))
        if args.uninstall:
            manifest_path.unlink()
        else:
            atomic(manifest_path,encoded({'schema_version':1,'entries':entries}))
            portable=servers('claude',args.binary.absolute(),args.data_dir.absolute(),launcher,args.with_rea)
            atomic(state/'jetbrains-global-import.json',encoded({'mcpServers':portable}))
            atomic(state/'copilot-global-import.json',encoded({'servers':portable}))
    except Exception:
        for path,old,new in reversed(changed):
            if read(path)==new:
                if old is None:path.unlink(missing_ok=True)
                else:atomic(path,old)
        raise
    finally:lock.rmdir()
    if args.install_skills and not args.uninstall:
        mapping={'codex':'codex','claude':'claude-code','gemini':'gemini-cli','opencode':'opencode',
                 'vscode':'github-copilot','antigravity':'antigravity','cursor':'cursor','windsurf':'windsurf','copilot-xcode':'github-copilot'}
        agents=sorted({mapping[e['host']] for e in entries if e['host'] in mapping})
        if (home/'.continue').exists():agents.append('continue')
        skill_env=dict(os.environ)
        if args.home:
            skill_env.update(HOME=str(home),CODEX_HOME=str(home/'.codex'),XDG_CONFIG_HOME=str(home/'.config'),CLAUDE_CONFIG_DIR=str(home/'.claude'))
        # Refuse local skill edits before invoking the standard installer.
        canonical=home/'.agents/skills'
        for source in (ROOT/'Sources/OmniMemoCore/Skills').iterdir():
            target=canonical/source.name
            if target.exists():
                def tree(folder):return {str(x.relative_to(folder)):digest(x.read_bytes()) for x in folder.rglob('*') if x.is_file()}
                if tree(target)!=tree(source):raise ValueError('Existing canonical skill differs; review before replacing: '+source.name)
        subprocess.run([str(ROOT/'scripts/install-skills.sh'),'--global','--agent',*agents,'--skill','*','--yes'],env=skill_env,check=True)
        # Native Xcode agent profiles are separate from the terminal-agent homes.
        xcode=home/'Library/Developer/Xcode/CodingAssistant'
        for host,folder in [('xcode-codex','codex'),('xcode-claude','ClaudeAgentConfig')]:
            if any(e['host']==host for e in entries):
                dest=xcode/folder/'skills';dest.mkdir(parents=True,exist_ok=True)
                for skill in canonical.iterdir():
                    if skill.name not in ['omnimem-recall','omnimem-handoff','reverse-engineer-anything']:continue
                    link=dest/skill.name
                    if link.is_symlink() and link.resolve()==skill.resolve():continue
                    if link.exists() or link.is_symlink():raise ValueError('Existing Xcode skill needs review: '+str(link))
                    link.symlink_to(skill,target_is_directory=True)

if __name__=='__main__':
    try:main()
    except (ValueError,OSError,subprocess.SubprocessError,tomllib.TOMLDecodeError) as error:
        # Do not print arbitrary config content, subprocess output or credentials.
        print('OmniMemo global installer: '+(str(error) if isinstance(error,ValueError) and not isinstance(error,tomllib.TOMLDecodeError) else type(error).__name__),file=sys.stderr)
        sys.exit(1)
