#!/usr/bin/env python3
"""Ea's dragons, applied to what the Foundry importers write.

`game/config/pf2e_dragons.yml` says which of Pathfinder's dragons Ea keeps and what each becomes. Dragon Form's
and Dragon Instinct's choices and the bestiary's names are generated files, so the importers call this on what
they write, and running this script applies it to the files as they stand. Running it twice changes nothing.

Usage: scripts/ea_dragons.py [--write]
"""

import argparse
import glob
import json
import os
import re

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
BESTIARY = os.path.join(ROOT, 'game', 'bestiary')
HOUSE = 'house.yml'

PHYSICAL = {'bludgeoning', 'piercing', 'slashing'}


def table():
    held = yaml.safe_load(open(os.path.join(CONFIG, 'pf2e_dragons.yml'), encoding='utf-8'))

    return held['pf2e_dragons']['replaces']


def row_for(name):
    """The table's row for a dragon by its Pathfinder name, or by its Ea one where it has already been renamed."""
    rows = table()

    return rows.get(name) or next((row for row in rows.values() if row['name'] == name), None)


def renamed(choice, suffix):
    row = row_for(choice['label'].replace(' Dragon', ''))

    if not row:
        return None

    return {'label': f"{row['name']}{suffix}", 'value': dict(choice['value'], dragonType=row['name'].lower())}


def choices(line, suffix):
    indent, _, held = line.partition('choices: ')
    kept = [one for one in (renamed(choice, suffix) for choice in json.loads(held)) if one]

    return f"{indent}choices: {json.dumps(sorted(kept, key=lambda one: one['label']), ensure_ascii=False)}"


def breath_traits(line, text):
    """A dragon whose damage is physical adds no trait to its breath, which is who this predicate leaves out."""
    indent, _, held = line.partition('predicate: ')
    damage = {}
    forms = json.loads(text.split('"Spell Effect: Dragon Form":', 1)[1].split('choices: ', 1)[1].split('\n', 1)[0])

    for form in forms:
        row = row_for(form['label'].replace(' Dragon', ''))

        if row:
            damage[row['name'].lower()] = row.get('damage') or form['value']['damageType']

    left = sorted(f'dragon-form:{name}' for name, kind in damage.items() if kind in PHYSICAL)

    return f"{indent}predicate: {json.dumps([{'nor': left}], ensure_ascii=False)}"


def in_entry(text, header, change):
    """Each line of one entry of a catalogue, as `change` leaves it."""
    lines = text.split('\n')
    at = lines.index(next(line for line in lines if line.rstrip('\r') == header))

    for index in range(at + 1, len(lines)):
        line = lines[index]

        if re.match(r'  \S', line):
            break

        end = '\r' if line.endswith('\r') else ''
        lines[index] = change(line.rstrip('\r')) + end

    return '\n'.join(lines)


def dragon_form(text):
    def change(line):
        if line.lstrip().startswith('choices: ') and '"dragonType"' in line:
            return choices(line, ' Dragon')
        if '"nor"' in line and 'dragon-form:' in line:
            return breath_traits(line, text)

        return line

    return in_entry(text, '  "Spell Effect: Dragon Form":', change)


def dragon_instinct(text):
    """Labelled as a barbarian's pick is recorded: `Terra`."""
    def change(line):
        return choices(line, '') if line.lstrip().startswith('choices: ') and '"dragonType"' in line else line

    return in_entry(text, '  "Dragon Instinct":', change)


def creature_name(name):
    """What a creature in the bestiary is called in Ea."""
    found = re.match(r'(\w+) (Dragon|Archdragon)\b(.*)', name, re.S)
    row = table().get(found.group(1)) if found else None

    return f'{row["name"]} {found.group(2)}{found.group(3)}' if row else name


def bestiary_names(text):
    return re.sub(r'^"([^"]+)":', lambda line: f'{json.dumps(creature_name(line.group(1)), ensure_ascii=False)}:', text,
                  flags=re.M)


def rewrite(path, change, write):
    before = open(path, encoding='utf-8', newline='').read()
    after = change(before)

    if write and after != before:
        open(path, 'w', encoding='utf-8', newline='').write(after)

    return after != before


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    changed = [rewrite(os.path.join(CONFIG, 'pf2e_effects.yml'), dragon_form, args.write) and 'pf2e_effects.yml',
               rewrite(os.path.join(CONFIG, 'pf2e_class_features.yml'), dragon_instinct, args.write) and 'pf2e_class_features.yml']

    for path in sorted(glob.glob(os.path.join(BESTIARY, '*.yml'))):
        if os.path.basename(path) != HOUSE:
            changed.append(rewrite(path, bestiary_names, args.write) and os.path.basename(path))

    print('written' if args.write else 'dry run')
    print('\n'.join(f'  {name}' for name in changed if name) or '  nothing to change')


if __name__ == '__main__':
    main()
