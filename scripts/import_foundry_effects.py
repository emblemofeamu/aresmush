#!/usr/bin/env python3
"""Foundry's effects, as a catalogue of things a character can be under for a while.

An effect is what a spell, a feat, an item or a creature leaves behind: Heroism's status bonus for ten
minutes, Rage until the end of the encounter, a potion's resistance for an hour, a creature aura's hold
on whoever stands in it. Each carries rules in the same vocabulary our other catalogues use, and a
duration.

The rules go through `import_foundry_rules.take` - the same gate every other catalogue here was
imported through - so a rule this engine cannot read is refused and counted rather than flattened.
An effect is kept even when none of its rules survive: it is still a thing someone can be under, and a
grant elsewhere may name it.

A grant naming another effect by its compendium id is rewritten to name it, because a name is what
our catalogue is keyed by and what a player types.

Usage: scripts/import_foundry_effects.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ea_dragons  # noqa: E402
import foundry_source  # noqa: E402
import import_foundry_rules as rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
OUT = 'pf2e_effects.yml'

# The packs of effects a character or a creature can be under. `bestiary-effects` is what a creature's
# auras and abilities put on whoever they reach: Harmonizing Aura's hold on allies and on enemies.
# Campaign effects are one adventure's, and belong with it if they are ever wanted.
PACKS = ['spell-effects', 'feat-effects', 'equipment-effects', 'other-effects', 'bestiary-effects']
CREATURE_PACK = 'bestiary-effects'
CREATURE_SUFFIX = ' (Creature)'

# The packs a grant may name by id, so an id can be turned into the name our catalogues use.
NAMED_BY_ID = PACKS + ['conditionitems']

# Long enough to say what the effect does; the full text belongs to the spell or the feat.
DESCRIPTION = 600


def documents(checkout, pack):
    base = os.path.join(checkout, 'packs', 'pf2e', pack)

    for path in sorted(glob.glob(os.path.join(base, '**', '*.json'), recursive=True)):
        try:
            doc = json.load(open(path))
        except Exception:
            continue

        if isinstance(doc, dict) and doc.get('name'):
            yield doc


def by_id(checkout):
    """Compendium id -> name, for the packs a grant may name that way."""
    found = {}

    for pack in NAMED_BY_ID:
        for doc in documents(checkout, pack):
            found[(pack, doc.get('_id'))] = doc['name']

    return found


def named(rule, ids):
    """A grant naming its target by id, rewritten to name it."""
    if rule.get('key') != 'GrantItem':
        return rule

    found = rules.GRANT_UUID.match(str(rule.get('uuid') or ''))

    if found and (found.group(1), found.group(2)) in ids:
        rule = dict(rule, uuid=f'Compendium.pf2e.{found.group(1)}.Item.{ids[(found.group(1), found.group(2))]}')

    return rule


def entry_of(doc, pack, ids, refused, unread, words):
    system = doc.get('system') or {}
    duration = system.get('duration') or {}
    badge = system.get('badge') or {}
    taken = []

    for rule in system.get('rules') or []:
        if not isinstance(rule, dict):
            continue
        if rule.get('key') not in rules.KINDS:
            unread[rule.get('key')] += 1
            continue

        row = rules.take(named(rule, ids), refused)

        if row:
            taken.append(rules.worded(row, words))

    entry = {
        'pack': pack,
        'level': (system.get('level') or {}).get('value', 1),
        'duration': {'unit': duration.get('unit', 'unlimited'), 'value': duration.get('value', -1),
                     'expiry': duration.get('expiry'), 'sustained': bool(duration.get('sustained'))},
        'traits': (system.get('traits') or {}).get('value') or [],
        'description': rules.plain(system.get('description', {}).get('value'), DESCRIPTION),
    }

    # A counter is how many of something the effect holds - a stack, a number of rounds of rage - and
    # whoever applies it says how many.
    if badge.get('type') == 'counter':
        entry['badge'] = {'type': 'counter', 'value': badge.get('value', 1), 'max': badge.get('max')}

    if taken:
        entry['rules'] = taken

    return entry


def value(held):
    if isinstance(held, bool):
        return 'true' if held else 'false'
    if held is None:
        return 'null'
    if isinstance(held, (int, float)):
        return str(held)

    return json.dumps(held, ensure_ascii=False)


def rendered(entries):
    lines = ['---', 'pf2e_effects:']

    for name, entry in sorted(entries.items()):
        lines.append(f'  {json.dumps(name, ensure_ascii=False)}:')

        for field in ('pack', 'level', 'duration', 'traits', 'badge', 'description'):
            if field in entry:
                lines.append(f'    {field}: {value(entry[field])}')

        if entry.get('rules'):
            lines.append('    rules:')

            for row in entry['rules']:
                first = True

                for field, held in row.items():
                    lead = '  - ' if first else '    '
                    lines.append(f'    {lead}{field}: {value(held)}')
                    first = False

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    ids = by_id(args.checkout)
    words = rules.strings(args.checkout)
    rules.effect_ids(args.checkout)
    refused = collections.Counter()
    unread = collections.Counter()
    entries = {}
    per_pack = collections.Counter()

    for pack in PACKS:
        for doc in documents(args.checkout, pack):
            # A creature's effect can share a name with a player's - a champion's Aura of Righteousness
            # and a creature's. The player's keeps the name; the creature's is `<name> (Creature)`, and
            # a reference into bestiary-effects finds it there (`Pf2e::Grants.target`).
            name = doc['name']
            if pack == CREATURE_PACK and name in entries:
                name = f'{name}{CREATURE_SUFFIX}'

            entries[name] = entry_of(doc, pack, ids, refused, unread, words)
            per_pack[pack] += 1

    if args.write:
        open(os.path.join(CONFIG, OUT), 'w').write(ea_dragons.dragon_form(rendered(entries)))
        foundry_source.record(args.checkout, __file__, [os.path.join(CONFIG, OUT)])

    carrying = sum(1 for entry in entries.values() if entry.get('rules'))
    rows = sum(len(entry.get('rules') or []) for entry in entries.values())

    print('written' if args.write else 'dry run')
    for pack in PACKS:
        print(f'  {pack}: {per_pack[pack]}')
    print(f'  {len(entries)} effects, {carrying} of them carrying {rows} rules')

    print('\nkinds of rule nothing here reads:')
    for kind, count in unread.most_common(12):
        print(f'  {count:5d}  {kind}')

    print('\nrules refused rather than flattened:')
    for why, count in refused.most_common(15):
        print(f'  {count:5d}  {why}')


if __name__ == '__main__':
    main()
