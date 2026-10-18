#!/usr/bin/env python3
"""Exercise the real installer in isolated paths, including repeat setup and conflicts."""
import json, os, pathlib, subprocess, tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
installer = repo / 'install.sh'
assert installer.is_file(), 'automatic installer is missing'
env = dict(os.environ)
workspace = pathlib.Path(env.get('OMNIMEM_TEST_ROOT', '/Volumes/Ext/DevCache/OmniMemo/test-workspaces'))
workspace.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='install space ', dir=workspace) as folder:
    root = pathlib.Path(folder)
    prefix = root / 'prefix space'
    data = root / 'data'
    project = root / 'project space'
    project.mkdir()
    (project / 'source.swift').write_text('let value = 42\n')
    args = ['--prefix', str(prefix), '--data-dir', str(data), '--project', str(project),
            '--mongo-uri', env.get('OMNIMEM_TEST_MONGO_URI', 'mongodb://127.0.0.1:27019/omnimemo_install_tests')]
    def run(*extra, ok=True):
        p = subprocess.run(['bash', str(installer), *args, *extra], env=env, text=True,
                           capture_output=True, timeout=600)
        assert (p.returncode == 0) == ok, p.stdout[-2000:] + p.stderr[-2000:]
        return p
    run('--setup', '--with-rea', '--dry-run')
    assert not prefix.exists() and not data.exists() and not (project / '.mcp.json').exists()
    run('--unknown', ok=False)
    run('--prefix','/Volumes/OmniMemo-unmounted-installer-fixture/prefix','--dry-run',ok=False)
    assert not prefix.exists()
    # Existing unrelated executable must survive without a build or partial install.
    (prefix / 'bin').mkdir(parents=True)
    launcher = prefix / 'bin/omnimem'
    launcher.write_text('unrelated file\n')
    run(ok=False)
    assert launcher.read_text() == 'unrelated file\n'
    launcher.unlink()
    run('--setup')
    assert launcher.is_file()
    binary = [str(launcher), '--data-dir', str(data), '--project', str(project)]
    def cli(*args):
        return subprocess.check_output(binary + list(args), text=True)
    assert cli('--version').strip() == '0.2.0'
    assert (project / '.mcp.json').is_file()
    assert (project / '.codex/config.toml').is_file()
    saved = json.loads(cli('memory', 'save', '--title', 'Installer persistence', '--content', 'Keep this record', '--source', 'source.swift'))
    # Repeat installation must preserve data and registered executable paths.
    config = (project / '.mcp.json').read_bytes()
    run('--setup')
    assert (project / '.mcp.json').read_bytes() == config
    assert json.loads(cli('memory', 'show', saved['id']))['id'] == saved['id']
    cli('uninstall', '--apply')
    # Environment-provided MongoDB addresses must initialize the same database later reads use.
    env_project=root/'environment project';env_project.mkdir()
    env_data=root/'environment data'
    env['OMNIMEM_MONGO_URI']='mongodb://127.0.0.1:27019/omnimemo_install_env_tests'
    run('--setup','--project',str(env_project),'--data-dir',str(env_data))
    assert json.loads((env_data/'meta.json').read_text())['mongo_uri']=='mongodb://127.0.0.1:27019/omnimemo_install_env_tests', 'environment database was not selected'
    env.pop('OMNIMEM_MONGO_URI')
    subprocess.run([str(launcher),'--data-dir',str(env_data),'--project',str(env_project),'status'],check=True,capture_output=True)

    # The sqlite profile needs no database server: setup creates db/memory.sqlite only.
    lite_project=root/'lite project';lite_project.mkdir();lite_data=root/'lite data'
    subprocess.run(['git','init','-q',str(lite_project)],check=True)
    p=subprocess.run(['bash',str(installer),'--prefix',str(prefix),'--data-dir',str(lite_data),'--project',str(lite_project),
                      '--backend','sqlite','--setup'],env=env,text=True,capture_output=True,timeout=600)
    assert p.returncode==0,p.stdout[-1500:]+p.stderr[-1500:]
    assert json.loads((lite_data/'meta.json').read_text())['backend']=='sqlite'
    assert (lite_data/'db/memory.sqlite').is_file()
    lite=[str(launcher),'--data-dir',str(lite_data),'--project',str(lite_project)]
    subprocess.run(lite+['memory','save','--title','Lite','--content','No server needed'],check=True,capture_output=True)
    assert json.loads(subprocess.check_output(lite+['status'],text=True))['backend']=='SQLite'

print('PASS: sqlite profile setup without a server; dry-run has no writes; invalid flags/conflicts fail; real packaged CLI; setup; repeated install preserves memory/config; paths with spaces')
