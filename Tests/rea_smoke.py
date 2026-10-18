#!/usr/bin/env python3
"""Exercise the complete real REA catalog and built-in analysis through OmniMemo."""
import json,os,pathlib,subprocess,sys,tempfile
from mcp_smoke import Session

binary=os.path.abspath(sys.argv[1]);repo=pathlib.Path(__file__).resolve().parent.parent
identity=json.loads((repo/'Sources/OmniMemoCore/REA/provenance.json').read_text())
status=json.loads(subprocess.run([binary,'rea','status'],check=True,capture_output=True,text=True).stdout)
assert status['identity']==identity
manifest=json.loads(pathlib.Path(status['runtimeManifest']).read_text())
root=pathlib.Path('/Volumes/Ext/DevCache/OmniMemo/test-workspaces');root.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='rea fixture ',dir=root) as folder:
    project=pathlib.Path(folder);app=project/'app ; literal';app.mkdir()
    (app/'package.json').write_text(json.dumps({'name':'rea-fixture','version':'1.0.0','main':'main.js'}))
    (app/'main.js').write_text('const helper = require("./helper"); module.exports = function search(q) { return helper(q); };\n')
    (app/'helper.js').write_text('module.exports = q => q.toLowerCase();\n')
    command=[binary,'--project',str(project),'rea','mcp']
    session=Session(binary,None,project,'omnimemo-rea-fixture',command=command)
    try:
        tools=[];cursor=None
        while True:
            page=session.request('tools/list',{} if cursor is None else {'cursor':cursor});tools.extend(page['tools']);cursor=page.get('nextCursor')
            if not cursor:break
        assert len(tools)==identity['tool_count'] and len({t['name'] for t in tools})==len(tools)
        prompts=session.request('prompts/list',{})['prompts'];assert len(prompts)==identity['prompt_count']
        required={'analyze_javascript_application','inspect_managed_artifact','inspect_go_binary','inspect_android_package','inspect_wasm_artifact','inspect_evm_interface','inspect_firmware_regions'}
        assert required.issubset({t['name'] for t in tools})
        result=session.tool('analyze_javascript_application',{'input_path':str(app)})
        assert not result.get('isError'),str(result)[:300]
        text='\n'.join(c.get('text','') for c in result.get('content',[]))
        assert 'main.js' in text and 'helper.js' in text,text[:300]
        (project/'rea-evidence.json').write_text(text)
        schema=next(t for t in tools if t['name']=='analyze_javascript_application')['inputSchema']
        assert schema['type']=='object' and 'input_path' in schema.get('properties',{})
    finally:session.close()
    # Evidence from REA can be retained as a source for the existing memory/handoff API.
    data_root=project/'memory'
    subprocess.run([binary,'--data-dir',str(data_root),'--project',str(project),'init','--mongo-uri','mongodb://127.0.0.1:27019/omnimemo_rea_tests'],check=True,capture_output=True)
    writer=Session(binary,data_root,project,'rea-memory-writer')
    try:
        saved_result=writer.tool('memory_save',{'kind':'insight','title':'REA JavaScript evidence','content':'Static inspection found main.js and helper.js in the application.','sources':['rea-evidence.json']})
        assert not saved_result.get('isError'),saved_result
        saved=json.loads(saved_result['content'][0]['text'])
    finally:writer.close()
    reader=Session(binary,data_root,project,'rea-handoff-reader')
    try:
        record=json.loads(reader.tool('memory_get',{'id':saved['id']})['content'][0]['text'])
        assert record['state']=='active' and record['sources'][0]['path']=='rea-evidence.json'
    finally:reader.close()
    # Direct and wrapped CLI behavior/exit code agree, including arguments containing shell punctuation.
    upstream=[manifest['node_path'],str(pathlib.Path(manifest['package_root'])/'scripts/rea.mjs')]
    args=['analyze-javascript-application',str(app),'--json']
    wrapped=subprocess.run([binary,'--project',str(project),'rea','run','--']+args,capture_output=True,text=True,timeout=60)
    direct=subprocess.run(upstream+args,cwd=project,capture_output=True,text=True,timeout=60)
    assert wrapped.returncode==direct.returncode==0,(wrapped.stderr,direct.stderr)
    for output in [wrapped.stdout,direct.stdout]:
        data=json.loads(output);assert 'main.js' in json.dumps(data)
    invalid=['unknown-rea-command']
    wrapped_error=subprocess.run([binary,'rea','run','--']+invalid,capture_output=True,text=True,timeout=30)
    direct_error=subprocess.run(upstream+invalid,capture_output=True,text=True,timeout=30)
    assert wrapped_error.returncode==direct_error.returncode!=0
    before=set(project.iterdir())
    preview=json.loads(subprocess.run([binary,'--data-dir',str(data_root),'--project',str(project),'install','--with-rea'],check=True,capture_output=True,text=True).stdout)
    assert set(project.iterdir())==before and preview['profile']=='memory+rea'
    subprocess.run([binary,'--data-dir',str(data_root),'--project',str(project),'install','--with-rea','--apply'],check=True,capture_output=True)
    subprocess.run([binary,'--data-dir',str(data_root),'--project',str(project),'install','--with-rea','--apply'],check=True,capture_output=True)
    config=json.loads((project/'.mcp.json').read_text());assert len(config['mcpServers'])==2
    # Launch both exact generated registrations, not just hand-built commands.
    for name,entry in config['mcpServers'].items():
        registered=Session(binary,data_root,project,'registered-fixture',command=[entry['command']]+entry['args'])
        try:
            advertised=registered.request('tools/list',{})['tools']
            assert len(advertised)==(identity['tool_count'] if name.startswith('rea_') else 4)
        finally:registered.close()
    custom=subprocess.run([binary,'rea','run','--runtime-manifest',status['runtimeManifest'],'--','--version'],capture_output=True,text=True,timeout=30)
    assert custom.returncode==0 and identity['version'] in custom.stdout,custom.stderr
    assert len(list((project/'.agents/skills/reverse-engineer-anything/references').glob('*.md')))==6
    subprocess.run([binary,'--project',str(project),'uninstall','--apply'],check=True,capture_output=True)
    assert not (project/'.mcp.json').exists()
print(f"PASS: real REA {identity['tool_count']} tools/{identity['prompt_count']} prompts, static JS, CLI pass-through/exit, full skill profile roundtrip, evidence-to-memory handoff")
