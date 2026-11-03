#!/usr/bin/env python3
"""Foundry's bestiaries, as creatures a GM can add to an encounter.

Only creatures Foundry marks as Remaster and as published under the ORC licence are read
(`publication.remaster`, `publication.license`): the game does not use Legacy or OGL material, and a few
books written to the Remaster's rules, Rage of Elements among them, were still published under the OGL.
Each creature keeps the book it is from as `source`.

Every such `npc` actor in their packs is a full stat block as data: its defences, its Strikes with their
bonuses and damage, its abilities, its spellcasting. An encounter needs those numbers to resolve an action
against a creature, and a GM acting for one needs its attacks, so each is read into
`game/bestiary/<pack>.yml`, with `game/bestiary/index.yml` saying which file holds each name.

They live outside `game/config` because there are six thousand of them: config is read whole at startup
and before every database spec, and a creature is only read when a GM names it.

What is kept is what play reads. The prose of an ability is kept, shortened, because a GM reads it to run
the ability; the lore of the creature is not.

An ability's and a Strike's rule elements are kept too - an aura, fast healing, a bonus to its saves
against magic, extra damage on a Strike - through `import_foundry_rules.take`, the same gate every other
catalogue here goes through, so a creature's rules read the way a feat's do.

Usage: scripts/import_foundry_npcs.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ea_dragons  # noqa: E402
import foundry_source  # noqa: E402
import import_foundry_rules as rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BESTIARY = os.path.join(ROOT, 'game', 'bestiary')
INDEX = 'index.yml'
HOUSE = 'house.yml'
# An ability's words are kept whole: what it does is read from them - its save, its outcomes, an
# affliction's stages - and a stage cut off is a stage lost.
ABILITY_TEXT = None

SIZES = {'tiny': 'tiny', 'sm': 'small', 'med': 'medium', 'lg': 'large', 'huge': 'huge', 'grg': 'gargantuan'}
TYPES = {'action': 'action', 'reaction': 'reaction', 'free': 'free', 'passive': 'passive'}


def blobs(checkout, packs='packs/pf2e'):
    """Every JSON file in their packs, or in the one pack named, read in one pass through git rather than
    one process per file."""
    listed = subprocess.run(['git', '-C', checkout, 'ls-tree', '-r', 'HEAD', packs],
                            capture_output=True, text=True).stdout.splitlines()
    wanted = [(line.split()[2], line.split('\t', 1)[1]) for line in listed
              if line.endswith('.json') and not line.endswith('_folders.json')]

    batch = subprocess.Popen(['git', '-C', checkout, 'cat-file', '--batch'], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE)

    for sha, path in wanted:
        batch.stdin.write(f'{sha}\n'.encode())
        batch.stdin.flush()
        header = batch.stdout.readline().split()
        body = batch.stdout.read(int(header[2]))
        batch.stdout.read(1)

        yield path, body

    batch.stdin.close()
    batch.wait()


def titled(slug):
    return ' '.join(part.capitalize() for part in str(slug).split('-'))


def rules_of(item, refused, words):
    """The rule elements on one of the creature's items, as the rules catalogue writes them."""
    taken = []

    for rule in item['system'].get('rules') or []:
        if not isinstance(rule, dict):
            continue
        # A Strike an ability gives a creature is one of its Strikes (`granted_strikes`), not a rule.
        if granted(rule):
            continue
        if rule.get('key') not in rules.KINDS:
            refused[f"not read: {rule.get('key')}"] += 1
            continue

        row = rules.take(rule, refused)

        if row:
            taken.append(rules.worded(row, words))

    return taken


def granted(rule):
    return rule.get('key') == 'Strike' and 'attackModifier' in rule


def granted_strikes(items, words):
    """The Strikes a creature's abilities give it in one form or another - a werewolf's jaws and claws
    in hybrid and animal shape, its fist in humanoid - each with the predicate it is offered under."""
    strikes = []

    for item in items:
        if item['type'] != 'action':
            continue
        for rule in item['system'].get('rules') or []:
            if not isinstance(rule, dict) or not granted(rule):
                continue
            base = (rule.get('damage') or {}).get('base') or {}
            if not base.get('die'):
                continue

            modifier = int(base.get('modifier') or 0)
            formula = f"{base.get('dice') or 1}{base['die']}" + (f'{modifier:+d}' if modifier else '')
            label = rules.translated(rule.get('label'), words)
            name = label if isinstance(label, str) and not label.startswith('PF2E.') else titled(rule.get('slug') or 'strike')

            strike = {'name': name, 'bonus': rule['attackModifier'],
                      'damage': [[formula, base.get('damageType'), base.get('category')]],
                      'traits': rule.get('traits') or []}
            if rule.get('predicate'):
                strike['when'] = rule['predicate']
            strikes.append(strike)

    return strikes


# What a shape-changer's ability says it gives up in a shape: `In animal shape, ... it loses its weapon
# Strikes`, `In humanoid shape, ... loses its jaws and claws Strikes`. Its paragraphs are joined by `%r`,
# so `In` has no word boundary before it.
LOSES = re.compile(r'In (\w+) shape\b[^.]*?\bloses its ([\w ,]+?) Strikes', re.I)


def shaped(strikes, abilities):
    """Each Strike its abilities' words say it gives up in a shape, offered unless it is in that shape."""
    for ability in abilities:
        shapes = {one.get('value'): rule['option'] for rule in ability.get('rules') or []
                  if rule.get('key') == 'RollOption' for one in rule.get('suboptions') or []}

        for shape, named in LOSES.findall(ability.get('text') or ''):
            option = shapes.get(shape.lower())
            if not option:
                continue
            words = [one.strip().lower() for one in re.split(r',|\band\b|\bor\b', named) if one.strip()]
            unless = {'not': f'{option}:{shape.lower()}'}

            for strike in strikes:
                name = strike['name'].lower()
                weapon = 'unarmed' not in (strike.get('traits') or [])
                if ('weapon' in words and weapon) or name in words or f'{name}s' in words:
                    held = strike.setdefault('when', [])
                    if unless not in held:
                        held.append(unless)


def valued(one):
    """A weakness's or resistance's value, or - where it excepts something, or doubles against
    something - the value with what it excepts and doubles against, each by its name."""
    named = lambda held: [entry if isinstance(entry, str) else (entry.get('label') or '').split('.')[-1]
                          for entry in held or []]
    excepted, doubled = named(one.get('exceptions')), named(one.get('doubleVs'))

    if not excepted and not doubled:
        return one.get('value')

    held = {'value': one.get('value')}
    if excepted:
        held['except'] = excepted
    if doubled:
        held['double'] = doubled
    return held


# A damage formula as the game reads it. Foundry's text sometimes writes a minus as an en dash or a
# minus sign, which the game would read as no dice at all.
def formula_of(text):
    return text.replace('\u2013', '-').replace('\u2212', '-').replace(' ', '')


def strike_of(item, refused, words):
    system = item['system']
    rolls = system.get('damageRolls') or {}
    ranged = system.get('range') or {}
    traits = (system.get('traits') or {}).get('value') or []

    strike = {'name': item['name'], 'bonus': (system.get('bonus') or {}).get('value', 0),
              'damage': [[formula_of(one.get('damage')), one.get('damageType'), one.get('category')]
                         for one in rolls.values() if one.get('damage')],
              'traits': traits}

    if isinstance(ranged, dict) and ranged.get('increment'):
        strike['range'] = ranged['increment']
    effects = (system.get('attackEffects') or {}).get('value') or []
    if effects:
        strike['effects'] = [titled(one) for one in effects]
    taken = rules_of(item, refused, words)
    if taken:
        strike['rules'] = taken

    return strike


def ability_of(item, refused, words):
    system = item['system']
    kind = ((system.get('actionType') or {}).get('value')) or 'passive'
    cost = (system.get('actions') or {}).get('value')

    ability = {'name': item['name'], 'type': TYPES.get(kind, 'passive'),
               'traits': (system.get('traits') or {}).get('value') or []}

    if cost:
        ability['cost'] = cost
    text = rules.plain((system.get('description') or {}).get('value'), ABILITY_TEXT)
    if text:
        ability['text'] = text
    taken = rules_of(item, refused, words)
    if taken:
        ability['rules'] = taken

    return ability


def casting_of(item, spells):
    """A spellcasting entry: its spells by rank, and how often each may be cast.

    A prepared caster's are what it has in its slots, so one prepared twice is listed twice and one
    prepared in a higher slot is listed at that rank. A spontaneous caster's slots are counted by rank
    (`slots`), and an innate spell cast more than once a day says how often (`uses`)."""
    system = item['system']
    dc = system.get('spelldc') or {}
    kind = (system.get('prepared') or {}).get('value')
    own = [one for one in spells if (one['system'].get('location') or {}).get('value') == item['_id']]
    by_id = {one['_id']: one for one in own}
    slots = system.get('slots') or {}
    ranks = collections.defaultdict(list)
    prepared = {rank[4:]: [by_id[one['id']]['name'] for one in (held or {}).get('prepared') or [] if one.get('id') in by_id]
                for rank, held in slots.items()}

    if kind == 'prepared' and any(prepared.values()):
        for rank, names in prepared.items():
            ranks[rank].extend(names)
    else:
        for spell in own:
            location = spell['system'].get('location') or {}
            traits = (spell['system'].get('traits') or {}).get('value') or []
            rank = 0 if 'cantrip' in traits else (location.get('heightenedLevel') or
                                                  (spell['system'].get('level') or {}).get('value') or 1)
            ranks[str(rank)].append(spell['name'])

    entry = {'name': item['name'], 'tradition': (system.get('tradition') or {}).get('value'),
             'type': kind,
             'dc': dc.get('dc'), 'attack': dc.get('value'),
             'spells': {rank: sorted(names) for rank, names in sorted(ranks.items(), key=lambda one: int(one[0])) if names}}

    if kind == 'spontaneous':
        counted = {rank[4:]: int((held or {}).get('max') or 0) for rank, held in slots.items()}
        entry['slots'] = {rank: count for rank, count in sorted(counted.items(), key=lambda one: int(one[0])) if count and rank != '0'}

    if kind == 'innate':
        uses = {one['name']: int(((one['system'].get('location') or {}).get('uses') or {}).get('max') or 0) for one in own}
        uses = {name: count for name, count in sorted(uses.items()) if count > 1}
        if uses:
            entry['uses'] = uses

    return entry


# What a reinforcing rune adds to a shield's Hardness and Hit Points, and the most it brings them to
# (`item/physical/runes.ts`).
REINFORCING = {1: ((3, 8), (44, 64)), 2: ((3, 10), (52, 80)), 3: ((3, 13), (64, 104)), 4: ((5, 15), (80, 120)),
               5: ((5, 17), (84, 136)), 6: ((7, 20), (108, 160))}


def reinforced(base, rune):
    increase, most = rune
    return max(base, most) if base + increase > most else base + increase


def shield_of(item):
    system = item['system']
    hardness = system.get('hardness') or 0
    hp = (system.get('hp') or {}).get('max') or 0
    rune = REINFORCING.get((system.get('runes') or {}).get('reinforcing') or 0)

    if rune:
        hardness, hp = reinforced(hardness, rune[0]), reinforced(hp, rune[1])

    return {'name': item['name'], 'hardness': hardness, 'hp': hp, 'ac': system.get('acBonus') or 0}


def npc_of(doc, pack, refused, words):
    system = doc['system']
    attributes = system.get('attributes') or {}
    traits = system.get('traits') or {}
    items = doc.get('items') or []
    speed = attributes.get('speed') or {}

    npc = {'pack': pack,
           'source': (((system.get('details') or {}).get('publication')) or {}).get('title'),
           'level': ((system.get('details') or {}).get('level') or {}).get('value', 0),
           'size': SIZES.get((traits.get('size') or {}).get('value'), 'medium'),
           'rarity': traits.get('rarity', 'common'),
           'traits': traits.get('value') or [],
           'ac': (attributes.get('ac') or {}).get('value'),
           'hp': (attributes.get('hp') or {}).get('max'),
           'perception': (system.get('perception') or {}).get('mod'),
           'saves': {name: (held or {}).get('value') for name, held in (system.get('saves') or {}).items()},
           'abilities': {name: (held or {}).get('mod') for name, held in (system.get('abilities') or {}).items()},
           'speeds': {'land': speed.get('value', 0)}}

    for other in speed.get('otherSpeeds') or []:
        npc['speeds'][other.get('type')] = other.get('value')

    hardness = (attributes.get('hardness') or {}).get('value')
    if hardness:
        npc['hardness'] = hardness

    hp_details = (attributes.get('hp') or {}).get('details')
    if hp_details:
        npc['hp_details'] = hp_details
    senses = [one.get('type') for one in (system.get('perception') or {}).get('senses') or [] if one.get('type')]
    if senses:
        npc['senses'] = senses

    skills = {titled(name): (held or {}).get('base') for name, held in (system.get('skills') or {}).items()}
    skills.update({one['name']: ((one['system'].get('mod') or {}).get('value')) for one in items if one['type'] == 'lore'})
    if skills:
        npc['skills'] = skills

    immunities = [one.get('type') for one in attributes.get('immunities') or [] if one.get('type')]
    if immunities:
        npc['immunities'] = immunities
    for field in ('weaknesses', 'resistances'):
        held = {one.get('type'): valued(one) for one in attributes.get(field) or [] if one.get('type')}
        if held:
            npc[field] = held

    shields = [shield_of(one) for one in items if one['type'] == 'shield']
    if shields:
        npc['shield'] = shields[0]

    strikes = [strike_of(one, refused, words) for one in items if one['type'] == 'melee']
    own = {one['name'].lower() for one in strikes}
    strikes += [one for one in granted_strikes(items, words) if one['name'].lower() not in own]
    abilities = [ability_of(one, refused, words) for one in items if one['type'] == 'action']
    shaped(strikes, abilities)
    if strikes:
        npc['strikes'] = strikes
    if abilities:
        npc['actions'] = abilities

    spells = [one for one in items if one['type'] == 'spell']
    casting = [casting_of(one, spells) for one in items if one['type'] == 'spellcastingEntry']
    casting = [one for one in casting if one['dc'] or one['spells']]
    if casting:
        npc['spellcasting'] = casting

    return npc


def rendered(entries):
    lines = ['---']

    for name, entry in sorted(entries.items()):
        lines.append(f'{json.dumps(name, ensure_ascii=False)}:')
        for field, held in entry.items():
            lines.append(f'  {field}: {json.dumps(held, ensure_ascii=False)}')

    return '\n'.join(lines) + '\n'


def indexed(by_pack, commit):
    """Which file holds each creature, with what a search filters on, and the Foundry commit read, so the
    next import can begin from the same one and change only what it means to."""
    lines = [f'# Imported from foundryvtt/pf2e at {commit}.', '---']

    for pack, entries in sorted(by_pack.items()):
        for name, entry in sorted(entries.items()):
            lines.append(f'{json.dumps(name, ensure_ascii=False)}: ' + json.dumps(
                {'pack': pack, 'level': entry['level'], 'traits': entry['traits']}, ensure_ascii=False))

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    by_pack = collections.defaultdict(dict)
    repeated = 0
    legacy = 0
    ogl = collections.Counter()
    refused = collections.Counter()
    words = rules.strings(args.checkout)

    for path, body in blobs(args.checkout):
        if b'"type": "npc"' not in body and b'"type":"npc"' not in body:
            continue

        try:
            doc = json.loads(body)
        except json.JSONDecodeError:
            continue

        if doc.get('type') != 'npc' or not isinstance(doc.get('system'), dict):
            continue

        # Only what Foundry marks as Remaster: the game plays by the ORC-licensed books, and a creature
        # from a Legacy one, which Archives of Nethys marks so too, is left out. So is one from a book
        # that follows the Remaster's rules and was still published under the OGL.
        publication = ((doc['system'].get('details') or {}).get('publication')) or {}
        if not publication.get('remaster'):
            legacy += 1
            continue
        if publication.get('license') != 'ORC':
            ogl[publication.get('title') or '(no book named)'] += 1
            continue

        pack = path.split('/')[2]
        name = doc['name']

        # The same creature appears in more than one adventure; the first of its name is kept, and the
        # packs are read in order, so a bestiary's own copy wins over an adventure's.
        if any(name in held for held in by_pack.values()):
            repeated += 1
            continue

        by_pack[pack][ea_dragons.creature_name(name)] = npc_of(doc, pack, refused, words)

    if args.write:
        os.makedirs(BESTIARY, exist_ok=True)
        # The house bestiary is the game's own creatures, which the game writes; it is not Foundry's.
        removed = []
        for old in os.listdir(BESTIARY):
            if old.endswith('.yml') and old != HOUSE:
                removed.append(os.path.join(BESTIARY, old))
                os.remove(removed[-1])
        written = []
        for pack, entries in by_pack.items():
            written.append(os.path.join(BESTIARY, f'{pack}.yml'))
            open(written[-1], 'w').write(rendered(entries))
        commit = subprocess.run(['git', '-C', args.checkout, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
        written.append(os.path.join(BESTIARY, INDEX))
        open(written[-1], 'w').write(indexed(by_pack, commit or 'an unknown commit'))
        foundry_source.record(args.checkout, __file__, sorted(written), removed)

    if args.write:
        print('Run `bundle exec rake pf2e:creature_clashes` for saved creatures whose names this import has taken.')

    total = sum(len(one) for one in by_pack.values())
    print('written' if args.write else 'dry run')
    print(f'  {total} creatures in {len(by_pack)} packs; {repeated} repeats of a name already read; '
          f'{legacy} from Legacy books left out')
    print(f'  {sum(ogl.values())} from Remaster books under the OGL left out: '
          + ', '.join(f'{many} {title}' for title, many in ogl.most_common()))
    for pack, entries in sorted(by_pack.items(), key=lambda one: -len(one[1]))[:12]:
        print(f'  {len(entries):5d}  {pack}')

    kept = sum(len(one.get('rules', [])) for entries in by_pack.values() for entry in entries.values()
               for one in entry.get('actions', []) + entry.get('strikes', []))
    print(f'\n  {kept} rules kept on abilities and Strikes; not kept:')
    for why, count in refused.most_common(12):
        print(f'  {count:6d}  {why}')


if __name__ == '__main__':
    main()
