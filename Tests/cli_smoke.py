#!/usr/bin/env python3
"""Real CLI subprocesses, MongoDB, and independent config parsing."""
import concurrent.futures,json,os,pathlib,subprocess,sys,tempfile
import tomllib

binary=os.path.abspath(sys.argv[1])
workspace='/Volumes/Ext/DevCache/OmniMemo/test-workspaces'
with tempfile.TemporaryDirectory(prefix='cli space ',dir=workspace) as folder:
    root=pathlib.Path(folder);project=root/'project space';project.mkdir();data=root/'memory'
    subprocess.run(['git','init','-b','main',str(project)],check=True,capture_output=True)
    (project/'main.swift').write_text('let answer = 42\n')
    base=[binary,'--data-dir',str(data),'--project',str(project)]
    def command(*args,expected=True):
        result=subprocess.run(base+list(args),capture_output=True,text=True,timeout=30)
        if expected:assert result.returncode==0,result.stderr[:400]
        else:assert result.returncode!=0
        return result
    command('init','--mongo-uri','mongodb://127.0.0.1:27019/omnimemo_cli_tests')
    def save(_):return json.loads(command('memory','save','--title','Parallel decision','--content','One shared result','--idempotency-key','parallel').stdout)['id']
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        ids=list(pool.map(save,range(4)))
    assert len(set(ids))==1,ids
    status=json.loads(command('status').stdout);assert status['records']==1
    command('checkpoint','--done','CLI saves work','--next','Continue in another agent','--changed-file','main.swift')
    command('context','unmatched task','--max-tokens','1000')
    output=root/'export.jsonl';command('memory','export','--output-file',str(output));assert len(output.read_text().splitlines())==2
    before=json.loads(command('status').stdout)['records'];command('cache','clear');assert json.loads(command('status').stdout)['records']==before
    preview=json.loads(command('install','--agents','codex,claude').stdout)
    assert not (project/'.mcp.json').exists()
    command('install','--agents','codex,claude','--apply');command('install','--agents','codex,claude','--apply')
    config=tomllib.loads((project/'.codex/config.toml').read_text())
    entry=config['mcp_servers'][preview['server_id']]
    assert entry['command']==binary and str(project) in entry['args']
    json_config=json.loads((project/'.mcp.json').read_text())
    assert entry['args']==json_config['mcpServers'][preview['server_id']]['args']
    command('uninstall','--apply');command('uninstall','--apply')
    assert not (project/'.mcp.json').exists()
    assert not (project/'.codex/config.toml').exists()
    missing=root/'missing'
    result=subprocess.run([binary,'--data-dir',str(missing),'--project',str(project),'status'],capture_output=True,text=True,timeout=30)
    assert result.returncode!=0 and 'storage_unavailable' in result.stderr
    assert not missing.exists()
print('PASS: CLI persistence; 4 process writers; cache/export; valid TOML; installer roundtrip; missing storage')
