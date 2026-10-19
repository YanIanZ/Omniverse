#!/usr/bin/env python3
"""Build exactly the REA fork/revision bundled with OmniMemo; no host setup or engine install."""
import argparse,hashlib,json,os,pathlib,shutil,subprocess

REPO='https://github.com/YanIanZ/rea.git'
REV='94153f1c757e07a6d092e00903aa8b125d4a0afa'
VERSION='6.4.0'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def tree(root,folder):
    """Mirrors REARuntime.treeDigest: sorted 'path NUL sha256 LF' lines over regular files."""
    lines=[]
    for item in folder.rglob('*'):
        if item.is_symlink():raise SystemExit('REA dist contains a symlink; refusing to fingerprint it.')
        if item.is_file():lines.append((str(item.relative_to(root)).encode(),sha(item)))
    return hashlib.sha256(b''.join(p+b'\0'+h.encode()+b'\n' for p,h in sorted(lines))).hexdigest()

def prepare(base,node,vendor=False):
    base=base.resolve();source=base/'upstream/rea';source.parent.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,HUSKY='0',DO_NOT_TRACK='1',TURBO_TELEMETRY_DISABLED='1',npm_config_cache=str(base/'npm'))
    if not source.exists():
        subprocess.run(['git','clone','--no-checkout',REPO,str(source)],check=True)
        try:subprocess.run(['git','-C',str(source),'checkout','--detach',REV],check=True)
        except subprocess.CalledProcessError:
            # A clone without the pinned revision would block every later run; it is ours to remove.
            shutil.rmtree(source);raise
    actual=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
    if actual!=REV:raise SystemExit('REA checkout revision mismatch; preserve it and review before replacing.')
    if subprocess.check_output(['git','-C',str(source),'status','--porcelain','--untracked-files=no'],text=True).strip():raise SystemExit('REA checkout has tracked edits; refusing to build modified source.')
    package=json.loads((source/'package.json').read_text())
    if package['version']!=VERSION:raise SystemExit('REA package version mismatch')
    actual_node=subprocess.check_output([node,'--version'],text=True).strip();major,minor=map(int,actual_node.lstrip('v').split('.')[:2])
    if not ((major==22 and minor>=19) or (major==24 and minor>=11) or major>=26):raise SystemExit('REA needs Node 22.19+, 24.11+ or 26+')
    subprocess.run(['npm','ci','--cache',str(base/'npm')],cwd=source,env=env,check=True)
    subprocess.run(['npm','run','build:cached'],cwd=source,env=env,check=True)
    counts=json.loads(subprocess.check_output([node,'--input-type=module','-e','import {CATALOG_IDENTITY} from "./dist/catalogIdentity.js"; console.log(JSON.stringify(CATALOG_IDENTITY.counts));'],cwd=source,text=True))
    bundle={'source_url':REPO,'commit':REV,'version':VERSION,'entrypoint_sha256':sha(source/'scripts/rea.mjs'),'lock_sha256':sha(source/'package-lock.json'),'catalog_sha256':sha(source/'dist/catalogIdentity.js'),'mcp_sha256':sha(source/'dist/mcp/main.js'),'dist_sha256':tree(source,source/'dist'),'tool_count':counts['mcp_tools'],'cli_count':counts['cli_commands'],'prompt_count':counts['mcp_prompts']}
    expected_path=pathlib.Path(__file__).resolve().parent.parent/'Sources/OmniMemoCore/REA/provenance.json'
    if not vendor and expected_path.exists() and json.loads(expected_path.read_text())!=bundle:
        raise SystemExit('Built REA differs from bundled provenance; preserve the current runtime manifest and review/re-vendor explicitly.')
    manifest=dict(identity=bundle,schema_version=1,package_root=str(source),node_path=str(pathlib.Path(node).absolute()),temp_directory=str(base/'rea-tmp'))
    target=base/'integrations/rea-runtime.json';target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    target.write_text(json.dumps(manifest,indent=2)+'\n');target.chmod(0o600)
    print('Runtime manifest:',target)
    return source,bundle

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=pathlib.Path,default=pathlib.Path('/Volumes/Ext/DevCache/OmniMemo'));parser.add_argument('--node',default=shutil.which('node'));parser.add_argument('--vendor',action='store_true',help='Refresh versioned skill/provenance resources from the matching built source.')
    args=parser.parse_args()
    if not args.node:raise SystemExit('Node is not installed; install a supported version explicitly.')
    source,bundle=prepare(args.base,args.node,args.vendor)
    if args.vendor:
        root=pathlib.Path(__file__).resolve().parent.parent
        dest=root/'Sources/OmniMemoCore/Skills/reverse-engineer-anything'
        if dest.exists():shutil.rmtree(dest)
        shutil.copytree(source/'skills/reverse-engineer-anything',dest)
        shutil.copy2(source/'LICENSE',dest/'LICENSE')
        resources=root/'Sources/OmniMemoCore/REA';resources.mkdir(exist_ok=True)
        for name in ['LICENSE','THIRD_PARTY_NOTICES.md']:shutil.copy2(source/name,resources/name)
        (resources/'provenance.json').write_text(json.dumps(bundle,indent=2)+'\n')
        print('Vendored the complete matching REA skill and references.')
