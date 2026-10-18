#!/usr/bin/env python3
"""Launch the global MCP command in two Git roots and verify shared-store isolation."""
import json, os, pathlib, subprocess, sys, tempfile
from mcp_smoke import Session, text
repo=pathlib.Path(__file__).resolve().parents[1]
binary=os.path.abspath(sys.argv[1])
workspace=os.environ.get('OMNIMEM_TEST_ROOT','/Volumes/Ext/DevCache/OmniMemo/test-workspaces')
with tempfile.TemporaryDirectory(prefix='global wire ',dir=workspace) as folder:
    root=pathlib.Path(folder);data=root/'data'
    projects=[root/'project one',root/'project two']
    for project in projects:
        project.mkdir();subprocess.run(['git','init','-q',str(project)],check=True)
        (project/'source.swift').write_text('let value = 42\n')
    subprocess.run([binary,'--data-dir',str(data),'--project',str(projects[0]),'init','--mongo-uri',os.environ.get('OMNIMEM_TEST_MONGO_URI','mongodb://127.0.0.1:27019/omnimemo_global_wire')],check=True,capture_output=True)
    command=[str(repo/'scripts/global-mcp.sh'),binary,str(data),'memory']
    before=os.getcwd()
    old_project=os.environ.pop('OMNIMEM_PROJECT',None)
    def session(project):
        os.chdir(project)
        try:return Session(binary,data,project,'global-wire-fixture',command=command)
        finally:os.chdir(before)
    try:
        first=session(projects[0])
        try:
            assert len(first.request('tools/list',{})['tools'])==4
            saved=text(first.tool('memory_save',{'kind':'fact','title':'Global launch scope','content':'Only project one may retrieve this record','sources':['source.swift']}))
        finally:first.close()
        second=session(projects[1])
        try:assert second.tool('memory_get',{'id':saved['id']}).get('isError')
        finally:second.close()
        again=session(projects[0])
        try:assert text(again.tool('memory_get',{'id':saved['id']}))['id']==saved['id']
        finally:again.close()
        p=subprocess.run(command,cwd=root,text=True,capture_output=True,timeout=10)
        assert p.returncode!=0 and not p.stdout and 'No default project' in p.stderr
        absent=root/'missing'
        p=subprocess.run([str(repo/'scripts/global-mcp.sh'),binary,str(absent),'memory'],cwd=projects[0],text=True,capture_output=True,timeout=10)
        assert p.returncode!=0 and not absent.exists() and not p.stdout
    finally:
        os.chdir(before)
        if old_project is not None:os.environ['OMNIMEM_PROJECT']=old_project
print('PASS: global launcher actual MCP handshake; launch Git root; cross-project isolation; same-project recall; no fallback project or replacement storage')
