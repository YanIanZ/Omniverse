#!/usr/bin/env python3
"""Real npx skills discovery/global install in an isolated home; no agent authentication."""
import os,pathlib,subprocess,tempfile
repo=pathlib.Path(__file__).resolve().parents[1]
workspace=pathlib.Path(os.environ.get('OMNIMEM_TEST_ROOT','/Volumes/Ext/DevCache/OmniMemo/test-workspaces'))
with tempfile.TemporaryDirectory(prefix='skills home ',dir=workspace) as folder:
    home=pathlib.Path(folder)
    env=dict(os.environ,HOME=str(home),CODEX_HOME=str(home/'.codex'),CLAUDE_CONFIG_DIR=str(home/'.claude'),XDG_CONFIG_HOME=str(home/'.config'),DISABLE_TELEMETRY='1')
    def run(*args):
        return subprocess.run([str(repo/'scripts/install-skills.sh'),*args],cwd=home,env=env,capture_output=True,text=True,timeout=120)
    listed=run('--list');assert listed.returncode==0,listed.stderr
    for name in ['omnimem-recall','omnimem-handoff','reverse-engineer-anything']:assert name in listed.stdout
    installed=run('--global','--agent','codex','claude-code','opencode','gemini-cli','antigravity','github-copilot','cursor','continue','--skill','*','--yes')
    assert installed.returncode==0,installed.stdout[-1500:]+installed.stderr[-1500:]
    canonical=home/'.agents/skills'
    for skill in ['omnimem-recall','omnimem-handoff','reverse-engineer-anything']:
        assert (canonical/skill/'SKILL.md').is_file(),skill
        assert (canonical/skill/'LICENSE').is_file(), 'standalone skill license missing: '+skill
    assert len(list((canonical/'reverse-engineer-anything/references').glob('*.md')))==6
    # Universal hosts use ~/.agents/skills; Claude and Continue receive host links.
    for directory in [canonical, home/'.claude/skills', home/'.continue/skills']:
        assert (directory/'omnimem-recall/SKILL.md').is_file(),directory
print('PASS: real pinned npx CLI discovers three skills; global installs for eight hosts; all six REA references retained; isolated home')
