#!/usr/bin/env python3
"""Independent MCP wire client. No model/API calls or private agent history."""
import argparse,json,os,pathlib,selectors,subprocess,tempfile,time

class Session:
    def __init__(self,binary,data,project,agent):
        self.proc=subprocess.Popen([binary,'--data-dir',str(data),'--project',str(project),'--agent',agent,'mcp','serve','--stdio'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
        self.counter=0
        self.request('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':agent,'version':'test'}})
        self.notify('notifications/initialized',{})
    def notify(self,method,params):
        self.proc.stdin.write(json.dumps({'jsonrpc':'2.0','method':method,'params':params})+'\n');self.proc.stdin.flush()
    def request(self,method,params):
        self.counter+=1
        self.proc.stdin.write(json.dumps({'jsonrpc':'2.0','id':self.counter,'method':method,'params':params})+'\n');self.proc.stdin.flush()
        selector=selectors.DefaultSelector();selector.register(self.proc.stdout,selectors.EVENT_READ)
        try:
            deadline=time.monotonic()+20
            while time.monotonic()<deadline:
                if not selector.select(timeout=max(0,deadline-time.monotonic())):raise AssertionError('MCP response timed out')
                raw=self.proc.stdout.readline()
                assert raw,'MCP process exited before response'
                message=json.loads(raw)  # Any stdout logging fails this test.
                if message.get('id')==self.counter:
                    assert 'error' not in message, message
                    self.last_wire=raw.encode()
                    return message['result']
            raise AssertionError('MCP response timed out')
        finally:selector.close()
    def tool(self,name,args):
        return self.request('tools/call',{'name':name,'arguments':args})
    def close(self):
        self.proc.stdin.close()
        try:self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.terminate();self.proc.wait(timeout=5)
        assert self.proc.returncode in [0,-15],self.proc.stderr.read()[:200]
        self.proc.stdout.close();self.proc.stderr.close()

def text(result):
    assert not result.get('isError'),result
    return json.loads(result['content'][0]['text'])

def run(binary,uri,workspace):
    with tempfile.TemporaryDirectory(dir=workspace,prefix='wire-') as folder:
        root=pathlib.Path(folder);project=root/'repo';project.mkdir();data=root/'store'
        (project/'main.swift').write_text('let storage = "MongoDB"\n')
        subprocess.run([binary,'--data-dir',str(data),'--project',str(project),'init','--mongo-uri',uri],check=True,capture_output=True)
        first=Session(binary,data,project,'codex-wire-fixture')
        try:
            tools=first.request('tools/list',{})['tools'];names={t['name'] for t in tools}
            assert names=={'memory_save','memory_get','memory_context','memory_checkpoint'},names
            saved=text(first.tool('memory_save',{'kind':'decision','title':'Swift MongoDB decision','content':'Simpan memory lintas agent di MongoDB.','sources':['main.swift'],'idempotency_key':'wire-decision'}))
            checkpoint=text(first.tool('memory_checkpoint',{'done':['Swift core implemented'],'next':['Verify handoff'],'changed_files':['main.swift']}))
            secret=first.tool('memory_save',{'kind':'fact','title':'rejected','content':'password=synthetic-never-store'})
            assert secret.get('isError') and 'synthetic-never-store' not in json.dumps(secret)
            spoof=first.tool('memory_get',{'id':saved['id'],'project_id':'another-project'})
            assert spoof.get('isError')
        finally:first.close()
        second=Session(binary,data,project,'claude-wire-fixture')
        try:
            retrieved=text(second.tool('memory_get',{'id':saved['id']}));assert retrieved['agent']=='codex-wire-fixture'
            assert text(second.tool('memory_get',{'id':checkpoint['id']}))['kind']=='checkpoint'
            for budget in [500,700,1000,2000]:
                context=text(second.tool('memory_context',{'task':'MongoDB','max_tokens':budget}))
                assert context['estimated_tokens']<=budget
                assert len(second.last_wire.rstrip(b'\n'))<=budget,(budget,len(second.last_wire))
            too_small=second.tool('memory_context',{'task':'memory','max_tokens':100});assert too_small.get('isError')
            (project/'main.swift').write_text('let changed = true\n')
            assert text(second.tool('memory_get',{'id':saved['id']}))['state']=='stale'
        finally:second.close()
        other=root/'other';other.mkdir();third=Session(binary,data,other,'other-project')
        try:
            assert third.tool('memory_get',{'id':saved['id']}).get('isError')
        finally:third.close()
    print('PASS: four tools; SDK handshake; restarted-client handoff; secret/scope rejection; wire budgets; stale evidence')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('binary');parser.add_argument('--uri',default='mongodb://127.0.0.1:27019/omnimemo_wire_tests');parser.add_argument('--workspace',default='/Volumes/Ext/DevCache/OmniMemo/test-workspaces')
    args=parser.parse_args();run(os.path.abspath(args.binary),args.uri,args.workspace)
