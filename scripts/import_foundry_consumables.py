#!/usr/bin/env python3
"""What a consumable does when it is used, from Foundry's equipment pack, onto our catalogue.

`pf2e_consumables.yml` held what an item costs and weighs and nothing of what it does, so a healing
potion drunk in a fight healed nothing. Foundry's pack holds three things that answer that:

  heal     a consumable whose `system.damage.kind` is `healing`: the Hit Points it restores, as a
           formula (`1d8`), and `heal_type` where it heals only the living (`vitality`) or only the
           undead (`void`). Healing potions, elixirs of life, oils of unlife.
  effect   the `Effect: …` its description links to in the equipment-effects pack, by name, where our
           `pf2e_effects.yml` holds one of that name: a mutagen's bonuses and drawbacks.
  bomb     an alchemical bomb, which their pack keeps as a weapon: its dice, its persistent and splash
           damage, its item bonus to hit and its range increment.

        bomb:
          dice: 1             # how many of `die`; with no die, a flat amount
          die: d8
          damage_type: fire
          persistent: 1d6     # or a flat number, or nothing
          persistent_type: fire
          splash: 1
          bonus: 1
          range: 20

Each entry is matched by name. Only these keys are written; everything else on an entry is
left as it is, and an item Foundry does not have is reported and left alone.

Usage: scripts/import_foundry_consumables.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import json
import os
import re
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import foundry_source  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
OUT = 'pf2e_consumables.yml'
SECTION = 'pf2e_consumables'

EFFECT_LINK = re.compile(r'@UUID\[Compendium\.pf2e\.equipment-effects\.Item\.([^\]]+)\]')


def pack(checkout):
    """Every equipment item by name."""
    out = {}

    for path in glob.glob(os.path.join(checkout, 'packs', 'pf2e', 'equipment', '**', '*.json'), recursive=True):
        doc = json.load(open(path))

        if isinstance(doc, dict) and doc.get('name'):
            out[doc['name']] = doc

    return out


def heal(system):
    damage = system.get('damage') or {}

    return damage.get('formula') if damage.get('kind') == 'healing' else None


def heal_type(system):
    """Vitality heals the living, void the undead; untyped heals either."""
    damage = system.get('damage') or {}

    return damage.get('type') if damage.get('kind') == 'healing' and damage.get('type') != 'untyped' else None


def effect(system, effects):
    found = EFFECT_LINK.findall((system.get('description') or {}).get('value') or '')
    named = [one for one in found if one in effects]

    return named[0] if named else None


def dice(number, faces):
    if not number:
        return None

    return f'{number}d{faces}' if faces else number


def bomb(doc):
    system = doc['system']

    if doc.get('type') != 'weapon' or system.get('group') != 'bomb':
        return None

    damage = system.get('damage') or {}
    persistent = damage.get('persistent') or {}
    die = damage.get('die') or None

    out = {
        'dice': damage.get('dice') or 0,
        'die': die,
        'damage_type': damage.get('damageType'),
        'persistent': dice(persistent.get('number'), persistent.get('faces')),
        'persistent_type': persistent.get('type'),
        'splash': (system.get('splashDamage') or {}).get('value') or 0,
        'bonus': (system.get('bonus') or {}).get('value') or 0,
        'range': system.get('range') or 0,
    }

    return {key: value for key, value in out.items() if value not in (None, 0, '')} | {'dice': out['dice']}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    path = os.path.join(CONFIG, OUT)
    text = open(path).read()
    catalogue = yaml.safe_load(text)[SECTION]
    effects = yaml.safe_load(open(os.path.join(CONFIG, 'pf2e_effects.yml')))['pf2e_effects']
    items = pack(args.checkout)

    counts = collections.Counter()
    found = {}

    for name in catalogue:
        doc = items.get(name)

        if not doc:
            counts['not in their pack'] += 1
            continue

        system = doc['system']
        held = {key: value for key, value in (('heal', heal(system)), ('heal_type', heal_type(system)),
                                              ('effect', effect(system, effects)), ('bomb', bomb(doc))) if value}

        for key in held:
            counts[key] += 1

        if held:
            found[name] = held

    for key, count in sorted(counts.items()):
        print(f'{count:5d}  {key}')

    if not args.write:
        return

    # Written into the file as text, entry by entry, so its order, comments and quoting are kept.
    lines = text.split('\n')
    out = []
    current = None
    skipping = False

    for line in lines:
        entry = re.match(r'^  (?! )("?)(.+?)\1:\s*$', line)

        if entry:
            if current in found:
                out.extend(rendered(found[current]))
            current = yaml.safe_load(f'x: {line.strip()[:-1]}')['x'] if entry.group(1) else entry.group(2)
            skipping = False
            out.append(line)
            continue

        if current and re.match(r'^    (heal|heal_type|effect|bomb):', line):
            skipping = True
            continue

        if skipping and re.match(r'^      ', line):
            continue

        skipping = False

        if current and not line.startswith('    ') and current in found:
            out.extend(rendered(found[current]))
            current = None

        out.append(line)

    if current in found:
        out.extend(rendered(found[current]))

    open(path, 'w').write('\n'.join(out))
    foundry_source.record(args.checkout, __file__, [path])


def rendered(held):
    dumped = yaml.safe_dump(held, sort_keys=False, default_flow_style=False, allow_unicode=True, width=1000)

    return ['    ' + line for line in dumped.rstrip('\n').split('\n')]


if __name__ == '__main__':
    main()
