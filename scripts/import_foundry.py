#!/usr/bin/env python3
"""Every import from Foundry's pf2e system, in order, from one commit.

The importers were run by hand, one at a time, from whatever checkout was to hand, and nothing said
which commit a catalogue came from. This runs all of them from one commit of foundryvtt/pf2e, so the
same commit gives the same catalogues, and each importer records what it read in
`game/config/pf2e_foundry_source.yml` (see `foundry_source.py`).

    scripts/import_foundry.py --check                 # which commit each import read, and what has
                                                      # changed by hand since
    scripts/import_foundry.py                         # import again from the pinned commit
    scripts/import_foundry.py --commit <sha>          # import from another commit, and pin it
    scripts/import_foundry.py --latest                # import from Foundry's default branch, and pin it
    scripts/import_foundry.py --only effects,actions  # some of the steps

The checkout is kept in `~/.cache/tenebrae/foundry-pf2e` (or `--checkout DIR`) and fetched to the commit
asked for, one commit deep. What each importer prints - what it took, and what it refused or left out
and why - is kept in `scripts/foundry_reports/<step>.txt`, so a new import's diff shows what changed in
those counts as well as in the data.

An importer that writes a whole file replaces whatever is in it. So before any of them runs, each file
a step would replace is compared with the hash its last import recorded, and if it was changed by hand
since, or has no recorded import at all, nothing runs: carry the hand edit over (it would otherwise be
lost), then pass `--overwrite-edits`. Files an importer only writes into (`rules:` blocks in the feat
catalogues, a consumable's `heal:`) keep their hand edits and are not checked.
"""

import argparse
import glob
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import foundry_source  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = foundry_source.ROOT
CONFIG = os.path.join(ROOT, 'game', 'config')
BESTIARY = os.path.join(ROOT, 'game', 'bestiary')
REPORTS = os.path.join(HERE, 'foundry_reports')
CACHE = os.path.join(os.path.expanduser('~'), '.cache', 'tenebrae', 'foundry-pf2e')


def bestiary():
    return sorted(path for path in glob.glob(os.path.join(BESTIARY, '*.yml'))
                  if os.path.basename(path) != 'house.yml')


# In the order they must run: actions and consumables name effects, so effects come first; the rules
# importer fills the actions catalogue, so it follows the actions importer. `whole` is what a step
# replaces outright; `checkout` is the checkout path, or the file under it, the importer is given.
STEPS = [
    {'name': 'effects', 'script': 'import_foundry_effects.py',
     'whole': lambda: [os.path.join(CONFIG, 'pf2e_effects.yml')]},
    {'name': 'actions', 'script': 'import_foundry_actions.py',
     'whole': lambda: [os.path.join(CONFIG, 'pf2e_actions.yml')]},
    {'name': 'consumables', 'script': 'import_foundry_consumables.py', 'whole': lambda: []},
    {'name': 'runes', 'script': 'import_foundry_runes.py',
     'whole': lambda: [os.path.join(CONFIG, 'pf2e_runes.yml')]},
    {'name': 'rules', 'script': 'import_foundry_rules.py',
     'whole': lambda: [os.path.join(CONFIG, 'pf2e_class_features.yml')]},
    {'name': 'spells', 'script': 'import_foundry_spells.py',
     'whole': lambda: [os.path.join(CONFIG, 'pf2e_spell_mechanics.yml')]},
    {'name': 'npcs', 'script': 'import_foundry_npcs.py', 'whole': bestiary},
    {'name': 'renames', 'script': 'import_remaster_renames.py', 'write': [],
     'checkout': 'packs/pf2e/journals/remaster-changes.json',
     'whole': lambda: [os.path.join(CONFIG, 'pf2e_renames.yml')]},
]


def git(checkout, *args, quiet=False):
    subprocess.run(['git', '-C', checkout, *args], check=True,
                   stdout=subprocess.DEVNULL if quiet else None)


def fetch(checkout, commit):
    """`checkout` at `commit` (a sha, or None for the default branch), one commit deep. A checkout of
    someone's own, named with --checkout, is used as it is and never fetched into or reset."""
    if checkout != CACHE:
        at = foundry_source.describe(checkout)
        if not at['commit'] or not commit or not at['commit'].startswith(commit):
            raise SystemExit(f"{checkout} is at {at['commit'] or 'no commit'}, not {commit or 'the latest'}: "
                             'check that out there, or leave out --checkout to use a cached one')
        if at['dirty']:
            raise SystemExit(f'{checkout} has local changes under packs/, src/ or static/')
        return at

    if not os.path.isdir(os.path.join(checkout, '.git')):
        os.makedirs(checkout, exist_ok=True)
        git(checkout, 'init', '-q')
        git(checkout, 'remote', 'add', 'origin', foundry_source.REPOSITORY)

    git(checkout, 'fetch', '-q', '--depth', '1', 'origin', commit or 'HEAD')
    git(checkout, 'checkout', '-q', '--force', '--detach', 'FETCH_HEAD')

    return foundry_source.describe(checkout)


def edited(steps, held):
    """Each file the steps would replace that differs from its recorded import, with why."""
    found = []

    for step in steps:
        for path in step['whole']():
            name = foundry_source.relative(path)
            known = held['files'].get(name)
            if not os.path.exists(path):
                continue
            if not known:
                found.append((name, 'no import of it is recorded'))
            elif foundry_source.digest(path) != known['sha256']:
                found.append((name, f"changed since {known['by']} wrote it"))

    return found


def check(held):
    print(f"pin: {held['pin'] or '(none)'}")
    print('imports:')
    for step in STEPS:
        name = os.path.splitext(step['script'])[0]
        got = held['imports'].get(name)
        if got:
            stale = '' if got['commit'] == held['pin'] else '  (not the pin)'
            print(f"  {step['name']:12s} {got.get('version') or '?':8s} {got['commit']}{stale}")
        else:
            print(f"  {step['name']:12s} not recorded")

    changed = [(name, known) for name, known in sorted(held['files'].items())
               if not os.path.exists(os.path.join(ROOT, name))
               or foundry_source.digest(os.path.join(ROOT, name)) != known['sha256']]
    print('changed by hand since imported:' if changed else 'every recorded file is as imported')
    for name, known in changed:
        print(f"  {name} (written by {known['by']})")

    blocked = edited(STEPS, held)
    if blocked:
        print('an import would overwrite:')
        for name, why in blocked:
            print(f'  {name}: {why}')

    return 1 if blocked else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--check', action='store_true', help='say what was imported from where; fetch nothing')
    which = parser.add_mutually_exclusive_group()
    which.add_argument('--commit', help='a foundryvtt/pf2e commit to import from, which becomes the pin')
    which.add_argument('--latest', action='store_true', help="import from Foundry's default branch, and pin it")
    parser.add_argument('--checkout', default=CACHE, help=f'where to keep the Foundry checkout (default {CACHE})')
    parser.add_argument('--only', help='comma-separated steps: ' + ', '.join(step['name'] for step in STEPS))
    parser.add_argument('--overwrite-edits', action='store_true',
                        help='replace files changed by hand since their import, or with no import recorded')
    args = parser.parse_args()
    # The steps' output is echoed here, and a console's code page can't always show it.
    sys.stdout.reconfigure(errors='replace')

    held = foundry_source.load()

    if args.check:
        return check(held)

    steps = STEPS
    if args.only:
        wanted = args.only.split(',')
        unknown = set(wanted) - {step['name'] for step in STEPS}
        if unknown:
            parser.error('no step named ' + ', '.join(sorted(unknown)))
        steps = [step for step in STEPS if step['name'] in wanted]

    commit = args.commit or (None if args.latest else held['pin'])
    if not commit and not args.latest:
        parser.error('nothing is pinned yet: pass --commit <sha> or --latest')

    blocked = edited(steps, held)
    if blocked and not args.overwrite_edits:
        print('Not importing. These would be replaced, losing what was changed by hand:')
        for name, why in blocked:
            print(f'  {name}: {why}')
        print('Carry the changes over (git log -p the file), then run again with --overwrite-edits.')
        return 1

    source = fetch(args.checkout, commit)
    print(f"foundryvtt/pf2e {source['version']} at {source['commit']} ({source['committed']})")
    os.makedirs(REPORTS, exist_ok=True)

    for step in steps:
        given = os.path.join(args.checkout, step['checkout']) if step.get('checkout') else args.checkout
        command = [sys.executable, os.path.join(HERE, step['script']), given] + step.get('write', ['--write'])
        print(f"== {step['name']}")
        # UTF-8 mode, so a step that prints a name outside the Windows code page doesn't fail on it.
        ran = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding='utf-8',
                             env=dict(os.environ, PYTHONUTF8='1'))
        sys.stdout.write(ran.stdout + ran.stderr)
        if ran.returncode != 0:
            print(f"{step['name']} failed; the steps after it were not run")
            return ran.returncode
        with open(os.path.join(REPORTS, f"{step['name']}.txt"), 'w', encoding='utf-8', newline='\n') as handle:
            handle.write(ran.stdout + ran.stderr)

    # Some of the steps from the pin leave the pin where it is; a commit asked for becomes it.
    if args.commit or args.latest or not args.only:
        held = foundry_source.load()
        held['pin'] = source['commit']
        foundry_source.save(held)
        print(f"pinned {source['commit']}")
    print('Review the diff, then commit the catalogues with game/config/pf2e_foundry_source.yml and '
          'scripts/foundry_reports/.')

    return 0


if __name__ == '__main__':
    sys.exit(main())
