#!/usr/bin/env python3
"""Foundry's property runes, as a catalogue of `rules:` like every other catalogue here.

A property rune is the one piece of their mechanics that does not live in their packs: the packs carry
a rune as an item with an empty `rules` array, and what the rune *does* is a table in their code
(`src/module/item/physical/runes.ts`). So this reads that table and writes the same rule elements the
rest of our catalogues carry, which is what makes a *flaming* rune add its 1d6 fire rather than being a
word on an item sheet.

The table is TypeScript rather than JSON, so it is evaluated by node after the type annotations and the
handful of function-valued fields are taken out. Nothing is translated on the way through: a rune's
`damage.additional` is what Foundry turns into damage dice (`getPropertyRuneDamage`), and it becomes a
`DamageDice` row with the same fields. What we cannot read is refused and counted, never flattened.

Selectors are `{item|id}-…`, because a rune belongs to the weapon it is etched on: `Pf2e::Effects`
builds one source per rune per weapon and the weapon's own damage domain is the one it reaches.

Usage: scripts/import_foundry_runes.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import foundry_source  # noqa: E402
import import_foundry_rules as wording  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
SOURCE = 'src/module/item/physical/runes.ts'
OUT = 'pf2e_runes.yml'

# Their price is in gold; this game counts copper.
GOLD = 100

# What a rune may do that we can read, and what each becomes. Everything else is refused below.
#
#   damage.additional  -> DamageDice, or FlatModifier where it is a flat amount
#   attack.dosAdjustments -> AdjustDegreeOfSuccess
#   attack.notes, damage.notes -> Note, in English, keeping the effects its text links
#
# The rest is named in REFUSALS with the reason.
REFUSALS = {
    'ignoredResistances': 'ignores a resistance, which is the target\'s and not reachable from here',
    'adjustments': 'adjusts a modifier by way of a function rather than a value',
    'strikeAdjustments': 'changes the weapon itself by way of a function',
}

# Foundry's own spelling of an outcome, onto the spelling their packs use - which is the one
# `Pf2e::Degree` reads.
OUTCOMES = {'criticalSuccess': 'to-critical-success', 'success': 'to-success',
            'failure': 'to-failure', 'criticalFailure': 'to-critical-failure'}

DEGREES = {'criticalSuccess', 'success', 'failure', 'criticalFailure'}


def source_text(checkout):
    """The rune table, from a working tree that has it or from the checkout's own history."""
    path = os.path.join(checkout, SOURCE)

    if os.path.exists(path):
        return open(path).read()

    found = subprocess.run(['git', '-C', checkout, 'show', f'HEAD:{SOURCE}'],
                           capture_output=True, text=True)

    if found.returncode != 0:
        raise SystemExit(f'no {SOURCE} in {checkout}')

    return found.stdout


def literal(text, name):
    """The object literal assigned to `name`, as source."""
    start = text.index(f'const {name}')
    # The declaration carries a type of its own, which is braces too: the value is after the `=`.
    opening = text.index('{', text.index('=', start))
    depth = 0

    for i in range(opening, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[opening:i + 1]

    raise SystemExit(f'{name} is not closed')


def without_functions(block, dropped):
    """The literal with its function-valued fields taken out, and their names recorded.

    Eight fields in the table are arrow functions - "double the critical specialization effect for a
    pick" and the like. A function is behaviour we cannot carry across as data, so the field is removed
    and the rune keeps whatever else it has.
    """
    out = []
    i = 0
    # `key: (args) => …` or `key: (args): Type => …`
    pattern = re.compile(r'(\w+):\s*(?=\()')

    while i < len(block):
        found = pattern.search(block, i)

        if not found:
            out.append(block[i:])
            break

        after = skip_arrow(block, found.end())

        if after is None:
            out.append(block[i:found.end()])
            i = found.end()
            continue

        dropped[found.group(1)] += 1
        out.append(block[i:found.start()])
        i = after

    return ''.join(out)


def skip_arrow(text, start):
    """The index past an arrow function beginning at `start`, or None if that is not one."""
    end = matching(text, start, '(', ')')

    if end is None:
        return None

    rest = text[end:]
    arrow = re.match(r'\s*(?::\s*[\w<>|\[\] ]+)?\s*=>\s*', rest)

    if not arrow:
        return None

    body = end + arrow.end()

    if text[body] == '{':
        closing = matching(text, body, '{', '}')
        return past_comma(text, closing)

    # An expression body, which runs to the comma that ends the field.
    depth = 0

    for i in range(body, len(text)):
        if text[i] in '([{':
            depth += 1
        elif text[i] in ')]}':
            if depth == 0:
                return i
            depth -= 1
        elif text[i] == ',' and depth == 0:
            return i + 1

    return len(text)


def matching(text, start, opener, closer):
    depth = 0

    for i in range(start, len(text)):
        if text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return i + 1

    return None


def past_comma(text, index):
    rest = re.match(r'\s*,', text[index:])

    return index + rest.end() if rest else index


def evaluated(block):
    """The literal as data. Node reads it, because it is JavaScript and not JSON."""
    # `new Predicate([…])` is a predicate written the long way; the argument is the predicate.
    block = re.sub(r'new Predicate\(', '(', block)
    # Numeric separators and Infinity are JavaScript's, and JSON has neither.
    block = re.sub(r'(\d)_(\d)', r'\1\2', block)
    block = block.replace('Infinity', '1e999')

    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as handle:
        handle.write(f'console.log(JSON.stringify({block}));\n')
        script = handle.name

    try:
        found = subprocess.run(['node', script], capture_output=True, text=True)

        if found.returncode != 0:
            raise SystemExit(f'node could not read the table: {found.stderr.strip()[:400]}')

        return json.loads(found.stdout)
    finally:
        os.unlink(script)


def titled(slug):
    """`greaterAnchoring` as a player would type it."""
    spaced = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', slug)

    return spaced[0].upper() + spaced[1:]


def dice_row(entry, slug):
    """One of a rune's extra damage dice, as a `DamageDice`."""
    row = {'key': 'DamageDice', 'selector': '{item|id}-damage', 'slug': slug,
           'diceNumber': entry.get('diceNumber', 1), 'dieSize': entry.get('dieSize', 'd6')}

    for field, key in (('damageType', 'damageType'), ('category', 'category'),
                       ('damageCategory', 'category'), ('critical', 'critical'),
                       ('predicate', 'predicate')):
        if entry.get(field) is not None:
            row[key] = entry[field]

    return row


def flat_row(entry, slug):
    """A rune's extra damage that is an amount rather than dice."""
    row = {'key': 'FlatModifier', 'selector': '{item|id}-damage', 'slug': slug,
           'value': entry['modifier']}

    for field, key in (('type', 'type'), ('damageType', 'damageType'),
                       ('damageCategory', 'damageCategory'), ('category', 'damageCategory'),
                       ('critical', 'critical'), ('predicate', 'predicate')):
        if entry.get(field) is not None:
            row[key] = entry[field]

    return row


def outcome_row(entry, slug, refused):
    """A rune that turns one outcome into another: *keen* makes a near miss a critical hit."""
    named = entry.get('adjustments')

    if not isinstance(named, dict) or not named:
        refused['a degree adjustment that is not a mapping'] += 1
        return None

    adjustment = {}

    for outcome, change in named.items():
        amount = (change or {}).get('amount')

        if outcome not in DEGREES or amount not in OUTCOMES:
            refused[f'a degree adjustment of {amount!r}'] += 1
            return None

        adjustment[outcome] = OUTCOMES[amount]

    row = {'key': 'AdjustDegreeOfSuccess', 'selector': '{item|id}-attack', 'slug': slug,
           'adjustment': adjustment}

    if entry.get('predicate'):
        row['predicate'] = entry['predicate']

    return row


def note_row(entry, slug, roll, found):
    """A rune's words for a roll: *crushing*'s clumsy and enfeebled on a critical hit. `roll` is attack or
    damage, which is the domain the note is shown with. The title and text are their localisation keys,
    read in English as the rules importer reads a pack's notes."""
    row = {'key': 'Note', 'selector': f'{{item|id}}-{roll}', 'slug': slug}

    for field in ('outcome', 'predicate', 'title', 'text'):
        if entry.get(field):
            row[field] = entry[field]

    return wording.worded(row, found)


def rules_of(rune, slug, refused, found=None):
    """Everything this rune does that we can read."""
    rows = []
    damage = rune.get('damage') or {}
    attack = rune.get('attack') or {}

    for entry in damage.get('additional') or []:
        rows.append(flat_row(entry, slug) if 'modifier' in entry else dice_row(entry, slug))

    for entry in attack.get('dosAdjustments') or []:
        row = outcome_row(entry, slug, refused)

        if row:
            rows.append(row)

    for roll, holder in (('attack', attack), ('damage', damage)):
        for entry in holder.get('notes') or []:
            rows.append(note_row(entry, slug, roll, found or {}))

    for holder, field in ((damage, 'ignoredResistances'), (damage, 'adjustments')):
        for _ in holder.get(field) or []:
            refused[REFUSALS[field]] += 1

    return rows


def entry_of(slug, rune, kind, refused, found=None):
    rules = rules_of(rune, slug, refused, found) if kind == 'weapon' else []

    return {'slug': slug, 'kind': kind, 'level': rune.get('level', 1),
            'price': int(rune.get('price', 0) * GOLD), 'rarity': rune.get('rarity', 'common'),
            'traits': rune.get('traits') or [], 'rules': rules}


def yaml_value(value, indent):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)

    return json.dumps(value)


def rendered(entries):
    lines = ['---', 'pf2e_runes:']

    for name, entry in sorted(entries.items()):
        lines.append(f'  {name}:')

        for field in ('slug', 'kind', 'level', 'price', 'rarity'):
            lines.append(f'    {field}: {yaml_value(entry[field], 4)}')

        lines.append('    traits:')
        lines.extend(f'      - {yaml_value(trait, 6)}' for trait in entry['traits'])

        if not entry['rules']:
            continue

        lines.append('    rules:')

        for row in entry['rules']:
            first = True

            for field, value in row.items():
                lead = '  - ' if first else '    '
                lines.append(f'    {lead}{field}: {yaml_value(value, 4)}')
                first = False

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    text = source_text(args.checkout)
    found = wording.strings(args.checkout)
    wording.effect_ids(args.checkout)
    dropped = collections.Counter()
    refused = collections.Counter()
    entries = {}

    for name, kind in (('WEAPON_PROPERTY_RUNES', 'weapon'), ('ARMOR_PROPERTY_RUNES', 'armor')):
        table = evaluated(without_functions(literal(text, name), dropped))

        for slug, rune in table.items():
            entries[titled(slug)] = entry_of(slug, rune, kind, refused, found)

    text = rendered(entries)
    path = os.path.join(CONFIG, OUT)

    if args.write:
        open(path, 'w').write(text)
        foundry_source.record(args.checkout, __file__, [path])

    carrying = sum(1 for entry in entries.values() if entry['rules'])
    rows = sum(len(entry['rules']) for entry in entries.values())

    print('written' if args.write else 'dry run')
    print(f'  {len(entries)} runes, {carrying} of them carrying {rows} rules')
    print('\nwhat a rune does that is not read:')

    for why, count in refused.most_common(10):
        print(f'  {count:5d}  {why}')

    for field, count in dropped.most_common(10):
        print(f'  {count:5d}  {field}, which is a function in their table')


if __name__ == '__main__':
    main()
