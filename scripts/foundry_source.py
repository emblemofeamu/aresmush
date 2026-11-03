"""Which Foundry pf2e commit each import read, and what it wrote.

Every importer that reads a checkout of foundryvtt/pf2e calls `record` after it writes. The record is
`game/config/pf2e_foundry_source.yml`: per importer, the commit, the system version and when that commit
was made; per file written, which importer wrote it last and a hash of it as written. A file whose hash
no longer matches was changed by hand after the import, and the next import would undo the change.
`scripts/import_foundry.py` reads the record to say so before it overwrites anything.
"""

import hashlib
import json
import os
import subprocess

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECORD = os.path.join(ROOT, 'game', 'config', 'pf2e_foundry_source.yml')
SECTION = 'pf2e_foundry_source'
REPOSITORY = 'https://github.com/foundryvtt/pf2e'

HEADER = """\
# Which Foundry VTT pf2e commit each import last read, and each file it wrote, hashed as written.
# Written by the importers through scripts/foundry_source.py; `scripts/import_foundry.py --check`
# compares the files with it. `pin` is the commit `scripts/import_foundry.py` imports by default.
"""


def git(path, *args):
    found = subprocess.run(['git', '-C', path, *args], capture_output=True, text=True)

    return found.stdout.strip() if found.returncode == 0 else None


def version(top):
    """The system's version as its manifest gives it: `system.pf2e.json` since the pf2e and sf2e systems
    shared a repository, `system.json` before."""
    for name in ('system.pf2e.json', 'system.json', 'static/system.json', 'package.json'):
        path = os.path.join(top, name)
        if os.path.exists(path):
            held = json.load(open(path)).get('version')
            if held:
                return str(held)
        shown = git(top, 'show', f'HEAD:{name}')
        if shown:
            held = json.loads(shown).get('version')
            if held:
                return str(held)

    return None


def describe(path):
    """The commit a checkout (or a file inside one) is at, its version and date, and whether the files the
    importers read differ from that commit."""
    start = path if os.path.isdir(path) else os.path.dirname(os.path.abspath(path))
    top = git(start, 'rev-parse', '--show-toplevel')

    if not top:
        return {'commit': None, 'version': None, 'committed': None, 'dirty': False}

    changed = git(top, 'status', '--porcelain', '--untracked-files=no', '--', 'packs', 'src', 'static')

    return {'commit': git(top, 'rev-parse', 'HEAD'),
            'version': version(top),
            'committed': git(top, 'log', '-1', '--format=%cI', 'HEAD'),
            'dirty': bool(changed)}


def digest(path):
    hashed = hashlib.sha256()
    with open(path, 'rb') as handle:
        for block in iter(lambda: handle.read(1 << 20), b''):
            hashed.update(block)

    return hashed.hexdigest()


def relative(path):
    return os.path.relpath(os.path.abspath(path), ROOT).replace(os.sep, '/')


def load(at=None):
    at = at or RECORD
    if not os.path.exists(at):
        return {'repository': REPOSITORY, 'pin': None, 'imports': {}, 'files': {}}

    held = (yaml.safe_load(open(at)) or {}).get(SECTION) or {}
    held.setdefault('repository', REPOSITORY)
    held.setdefault('pin', None)
    held['imports'] = held.get('imports') or {}
    held['files'] = held.get('files') or {}

    return held


def save(held, at=None):
    at = at or RECORD
    # The commits first, then the files, each in name order, so a re-import's diff is only what changed.
    ordered = {'repository': held['repository'], 'pin': held['pin'],
               'imports': {name: held['imports'][name] for name in sorted(held['imports'])},
               'files': {name: held['files'][name] for name in sorted(held['files'])}}
    body = yaml.safe_dump({SECTION: ordered}, sort_keys=False, default_flow_style=False, width=1000)
    with open(at, 'w') as handle:
        handle.write('---\n' + HEADER + body)


def record(checkout, script, written, removed=(), at=None):
    """Note that `script` read `checkout` and wrote the files in `written`, and that the files in
    `removed` are gone. Prints what it noted, so a hand run says which commit it read."""
    source = describe(checkout)
    name = os.path.splitext(os.path.basename(script))[0]
    held = load(at)

    held['imports'][name] = {key: source[key] for key in ('commit', 'version', 'committed')}
    if source['dirty']:
        held['imports'][name]['dirty'] = True

    for path in removed:
        held['files'].pop(relative(path), None)
    for path in written:
        held['files'][relative(path)] = {'by': name, 'sha256': digest(path)}

    save(held, at)

    if not source['commit']:
        print(f'  recorded {name}: {checkout} is not a git checkout, so no commit could be recorded')
    else:
        print(f"  recorded {name}: foundryvtt/pf2e {source['version'] or '(no version)'} at {source['commit']}"
              + (', with local changes' if source['dirty'] else ''))

    return held
