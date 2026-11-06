#!/usr/bin/env python3
"""Foundry's actions, as a catalogue of things a character can do.

Two kinds of thing are actions. Their `actions` pack holds the basic, skill and class actions - Take
Cover, Rage, Hunt Prey. And a great many feats are themselves actions - a stance, a reaction - which our
feat catalogue already holds, so only what makes them actions is added here: what they cost, and the
effect they put on the one who uses them.

That effect is Foundry's `selfEffect`: using Rage puts you under Effect: Rage. It names an effect in
`pf2e_effects.yml`, and using the action is what applies it.

An action that rolls a check against someone carries what Foundry's action macro
(`src/module/system/action-macros/`) says about that check: the statistic it rolls, the defence it is
against or the DC it sets, the options it declares (`action:trip`, `inflicts:prone`), the modifiers it
carries, and the note for each outcome. The macros are code, but every one hands the same object literal
to `SingleCheckAction`, so the literal is read as data.

What an outcome does to someone - Trip's success knocks the target prone - is in the note as words, and
the words are not regular enough to act on: Grapple's critical failure lets the target choose. So what
the engine applies lives in `game/config/pf2e_action_consequences.yml`, written from those notes, where a
GM can change it without running this.

A reaction that is a Strike - Reactive Strike's "Make a melee Strike against the triggering creature" -
says so under `strike`: `melee` where only a melee Strike will do, `any` otherwise. An action that is
several Strikes - Flurry of Blows' "Make two unarmed Strikes." - says how many under `strikes`, and
`attack` where they must be unarmed, melee or ranged; an action that is a Strike and something more -
Deadly Aim's "Make a ranged Strike" - is one. Using either rolls the Strikes.

The rules an action carries for as long as a character owns it are counted here and written by
`import_foundry_rules.py --only actions`, which runs after this.

Usage: scripts/import_foundry_actions.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import foundry_source  # noqa: E402
import import_foundry_rules as rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
OUT = 'pf2e_actions.yml'
DESCRIPTION = 1200

# What an action costs, in Foundry's own words.
TYPES = {'action', 'reaction', 'free', 'passive'}


# Their actions pack is filed by whose an action is: these folders are everyone's, and any other - a
# class, an archetype, an ancestry, a heritage - belongs to whoever has the feat or feature of its name.
COMMON = {'basic', 'skill', 'exploration', 'downtime'}

# The books the game takes its actions from (`publication.title`). An action from any other is left out.
PUBLICATIONS = {'Pathfinder Player Core', 'Pathfinder Player Core 2', 'Pathfinder GM Core'}

# Actions Foundry files under an older book that a book the game uses reprints, by the book that does.
REPRINTED = {
    'Flurry of Blows': 'Pathfinder Player Core 2',
    'Rampaging Ferocity': 'Pathfinder Player Core',
    'Soaring Flight': 'Pathfinder Player Core 2',
    'The Bigger They Are': 'Pathfinder Player Core 2',
}

# Actions Emblem of Ea calls by a name of its own, as its arvek's Manabane heritage calls Elfbane's.
RENAMED = {'Resist Elf Magic': 'Resist Magic'}

# Downtime activities from those books the game does not run, and why: each is done outside a scene.
LEFT_OUT = {
    'Earn Income': 'not run in the game',
    'Long-Term Rest': "the GM's encounter/rest",
    'Retraining': 'done through requests, not in a scene',
}

# A reaction whose effect is a Strike at whoever triggered it, and whether it has to be a melee one.
STRIKES = re.compile(r'[Mm]ake an? (melee )?Strike against the triggering (?:creature|foe)')
SEVERAL = re.compile(r'[Mm]ake (two|three) (unarmed )?Strikes\.')
COUNTS = {'two': 2, 'three': 3}

# An action that is a Strike and something more - Combat Assessment, Deadly Aim, a finisher - is one
# Strike of the kind it names, made with the action's own rules on.
ONE = re.compile(r'\b(?:[Mm]ake|can make) an? ((?:(?!two\b|three\b|Strike\b)[\w-]+ ){0,4})Strike\b')
NOT_ONE = re.compile(r'\b(?:two|three) (?:\w+ )?Strikes\b|Strike twice')


MACROS = 'src/module/system/action-macros'

OUTCOMES = ['criticalSuccess', 'success', 'failure', 'criticalFailure']


def macro_sources(checkout):
    listed = subprocess.run(['git', '-C', checkout, 'ls-tree', '-r', '--name-only', 'HEAD', MACROS],
                            capture_output=True, text=True).stdout.split()

    for path in listed:
        if path.endswith('.ts'):
            yield path, subprocess.run(['git', '-C', checkout, 'show', f'HEAD:{path}'],
                                       capture_output=True, text=True).stdout


def literal(text, start):
    """The object literal opening at `start`, to its matching brace."""
    depth = 0

    for index in range(start, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]

    return None


def as_json(source, constants):
    """A TypeScript object literal as JSON: template strings filled from the file's constants, keys
    quoted, trailing commas dropped. Anything that is an expression rather than data comes back None."""
    source = re.sub(r'(?m)(?:^|\s)//[^\n]*', '', source)
    source = re.sub(r'`([^`]*)`', lambda found: json.dumps(
        re.sub(r'\$\{(\w+)\}', lambda one: constants.get(one.group(1), ''), found.group(1))), source)
    source = re.sub(r'([{,]\s*)([A-Za-z_]\w*)\s*:', r'\1"\2":', source)
    source = re.sub(r',(\s*[}\]])', r'\1', source)

    try:
        return json.loads(source)
    except json.JSONDecodeError:
        return None


def checks(checkout, found):
    """Every check action a macro declares, by its English name."""
    out = {}

    for path, text in macro_sources(checkout):
        # A `SimpleAction` - Stand, Drop Prone - rolls nothing; what it does is in
        # `pf2e_action_consequences.yml` under `always`.
        if 'SingleCheckAction' not in text and 'simpleRollActionCheck' not in text:
            continue

        constants = dict(re.findall(r'const (\w+) = "([^"]*)"', text))
        opened = re.search(r'(?:new SingleCheckAction\(|super\()\s*\{', text)
        data = as_json(literal(text, opened.end() - 1), constants) if opened else legacy(text, constants)

        if not data or 'name' not in data:
            continue

        weapons = re.search(r'getBestEquippedItemForAction\([^,]+,\s*(\[[^\]]*\])', text)
        name = rules.translated(data['name'], found)
        out[name] = check_of(data, found, json.loads(weapons.group(1)) if weapons else [])

    return out


def listed(found):
    """A list literal as a list, or nothing where it holds an expression rather than words."""
    if not found:
        return []

    try:
        return json.loads(re.sub(r',(\s*\])', r'\1', found.group(1)))
    except json.JSONDecodeError:
        return []


def legacy(text, constants):
    """A macro older than `SingleCheckAction` hands the same facts to `simpleRollActionCheck` as
    separate expressions: the skill and the DC as defaults, the options as a constant, a note per
    outcome by its key."""
    if 'simpleRollActionCheck' not in text:
        return None

    title = re.search(r'title:\s*"([^"]+)"', text)
    skill = re.search(r'options\?\.skill \?\? "([^"]+)"', text)
    dc = re.search(r'options\.difficultyClass \?\? "([^"]+)"', text)
    options = re.search(r'const rollOptions = (\[[^\]]*\])', text)
    traits = re.search(r'traits:\s*(\[[^\]]*\])', text)
    notes = re.findall(r'note\(selector,\s*"([^"]+)",\s*"(\w+)"\)', text)

    if not title:
        return None

    slug = re.search(r'"action:([\w-]+)"', options.group(1)) if options else None
    declared = listed(options)

    return {'name': title.group(1), 'slug': slug.group(1) if slug else None,
            'statistic': skill.group(1) if skill else None,
            'difficultyClass': dc.group(1) if dc else None,
            'traits': listed(traits),
            'rollOptions': [one for one in declared if not one.startswith('action:')],
            'notes': [{'outcome': [outcome], 'text': f'{prefix}.Notes.{outcome}'} for prefix, outcome in notes]}


def check_of(data, found, weapon_traits):
    statistic = data.get('statistic')
    dc = data.get('difficultyClass')
    check = {'slug': data.get('slug'),
             'statistic': statistic if isinstance(statistic, list) else (statistic or None),
             'options': [f"action:{data.get('slug')}"] + list(data.get('rollOptions') or [])}

    if isinstance(dc, dict):
        check['dc'] = dc.get('value')
    elif dc:
        check['against'] = dc
    if weapon_traits:
        check['weapon_traits'] = weapon_traits
    if data.get('modifiers'):
        check['modifiers'] = [{'label': rules.translated(one.get('label'), found), 'value': one.get('modifier'),
                               'type': one.get('type', 'untyped'), 'predicate': one.get('predicate')}
                              for one in data['modifiers']]

    notes = notes_of(data.get('notes'), found)
    if notes:
        check['notes'] = notes

    variants = {}
    for variant in data.get('variants') or []:
        own = {'name': rules.translated(variant.get('name'), found)}
        if variant.get('statistic'):
            own['statistic'] = variant['statistic']
        if notes_of(variant.get('notes'), found):
            own['notes'] = notes_of(variant.get('notes'), found)
        variants[variant.get('slug')] = own
    if variants:
        check['variants'] = variants

    return check


def notes_of(notes, found):
    out = {}

    for note in notes or []:
        text = rules.translated(note.get('text'), found)
        text = re.sub(r'\A(?:Critical Success|Critical Failure|Success|Failure)\s+', '', text or '')
        for outcome in note.get('outcome') or []:
            out[outcome] = text

    return {outcome: out[outcome] for outcome in OUTCOMES if outcome in out}


def documents(checkout, pack):
    base = os.path.join(checkout, 'packs', 'pf2e', pack)

    for path in sorted(glob.glob(os.path.join(base, '**', '*.json'), recursive=True)):
        try:
            doc = json.load(open(path))
        except Exception:
            continue

        if isinstance(doc, dict) and isinstance(doc.get('system'), dict) and doc.get('name'):
            doc['_folders'] = os.path.relpath(os.path.dirname(path), base).split(os.sep)
            yield doc


def effect_names():
    import yaml

    return set((yaml.safe_load(open(os.path.join(CONFIG, 'pf2e_effects.yml'))) or {}).get('pf2e_effects', {}))


def stocked_feats():
    import yaml

    names = set()

    for path in glob.glob(os.path.join(CONFIG, 'pf2e_feat_*.yml')):
        for block in (yaml.safe_load(open(path)) or {}).values():
            if isinstance(block, dict):
                names |= set(block)

    return names


def attack_kind(words):
    """The kind of attack "Make a ranged weapon Strike" asks for: unarmed, ranged or melee, or any for
    "a weapon or unarmed Strike" and a Strike named for its attack - "a tiger claw Strike"."""
    said = words.lower().split()
    if 'or' in said:
        return None
    if 'unarmed' in said:
        return 'unarmed'
    if {'ranged', 'thrown', 'firearm'} & set(said):
        return 'ranged'
    return 'melee' if 'melee' in said else None


def entry_of(doc, source, effects, counted):
    system = doc['system']
    kind = (system.get('actionType') or {}).get('value') or 'passive'
    cost = (system.get('actions') or {}).get('value')
    effect = (system.get('selfEffect') or {}).get('name')

    for rule in system.get('rules') or []:
        if isinstance(rule, dict):
            counted[rule.get('key')] += 1

    entry = {'from': source, 'type': kind if kind in TYPES else 'passive',
             'traits': (system.get('traits') or {}).get('value') or []}

    # Whose it is: everyone's, or what kind of thing grants it - a class, an archetype, a heritage.
    if source == 'action':
        folders = doc.get('_folders') or ['']
        entry['for'] = 'everyone' if folders[0] in COMMON else folders[0]

    if cost:
        entry['cost'] = cost
    if system.get('category'):
        entry['category'] = system['category']
    if system.get('frequency'):
        entry['frequency'] = {'max': system['frequency'].get('max', 1), 'per': system['frequency'].get('per')}
    if effect:
        entry['self_effect'] = effect if effect in effects else None
        if effect not in effects:
            counted[f'a self-effect our catalogue lacks: {effect}'] += 1
    text = rules.plain((system.get('description') or {}).get('value'), DESCRIPTION)
    entry['_text'] = text
    struck = STRIKES.search(text) if kind == 'reaction' else None
    if struck:
        entry['strike'] = 'melee' if struck.group(1) else 'any'
    several = SEVERAL.search(text) if kind == 'action' else None
    if several:
        entry['strikes'] = {'count': COUNTS[several.group(1)], **({'attack': 'unarmed'} if several.group(2) else {})}
    if source == 'action':
        entry['description'] = text

    return entry


def value(held):
    if isinstance(held, bool):
        return 'true' if held else 'false'
    if held is None:
        return 'null'
    if isinstance(held, (int, float)):
        return str(held)

    return json.dumps(held, ensure_ascii=False)


# What the rules give everyone to do that their packs hold no item for. Retching is in the words of the
# sickened condition: a Fortitude save against the DC of what sickened you (`dc_from`). An assisted
# recovery is in those of persistent damage.
OWN = {
    'Assisted Recovery': {
        'from': 'action', 'for': 'everyone', 'type': 'action', 'cost': 2, 'category': 'basic', 'traits': [],
        'description': 'You take steps to help yourself or an ally recover from persistent damage - dousing a flame, '
                       'washing off acid - which allows an additional flat check at once. The GM may lower the DC to 10 '
                       'for help that is particularly appropriate.'},
    'Retch': {
        'from': 'action', 'for': 'everyone', 'type': 'action', 'cost': 1, 'category': 'basic', 'traits': [],
        'check': {'slug': 'retch', 'statistic': ['fortitude'], 'options': ['action:retch'], 'dc_from': 'Sickened',
                  'notes': {'criticalSuccess': 'You reduce your sickened value by 2.',
                            'success': 'You reduce your sickened value by 1.'}},
        'description': 'You spend an action retching in an attempt to recover from being Sickened: a Fortitude save '
                       'against the DC of the effect that made you sickened.%rCritical Success You reduce your '
                       'sickened value by 2.%rSuccess You reduce your sickened value by 1.'},
}


def rendered(entries):
    lines = ['---', 'pf2e_actions:']

    for name, entry in sorted(entries.items()):
        lines.append(f'  {json.dumps(name, ensure_ascii=False)}:')

        for field in ('from', 'source', 'for', 'type', 'cost', 'category', 'traits', 'frequency', 'self_effect',
                      'strike', 'strikes', 'check', 'description'):
            if field in entry and entry[field] is not None:
                lines.append(f'    {field}: {value(entry[field])}')

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    effects = effect_names()
    feats = stocked_feats()
    counted = collections.Counter()
    entries = {}
    found = rules.strings(args.checkout)

    other_books = collections.Counter()
    for doc in documents(args.checkout, 'actions'):
        book = REPRINTED.get(doc['name']) or (doc['system'].get('publication') or {}).get('title')
        if book not in PUBLICATIONS:
            other_books[book or '(no book named)'] += 1
            continue
        if doc['name'] in LEFT_OUT:
            continue
        name = RENAMED.get(doc['name'], doc['name'])
        entries[name] = entry_of(doc, 'action', effects, counted)
        entries[name]['source'] = book

    # A feat that is an action - a stance, a reaction - is one because of what it costs; the feat itself
    # stays where it is.
    feat_actions = 0
    for doc in documents(args.checkout, 'feats'):
        kind = ((doc['system'].get('actionType') or {}).get('value'))
        if doc['name'] in feats and kind in ('action', 'reaction', 'free') and doc['name'] not in entries:
            entries[doc['name']] = entry_of(doc, 'feat', effects, collections.Counter())
            feat_actions += 1

    # A check belongs to the action of its name, wherever the action came from.
    declared = checks(args.checkout, found)
    by_lower = {name.lower(): name for name in entries}
    unmatched = sorted(name for name in declared if name.lower() not in by_lower)
    for name, check in declared.items():
        if name.lower() in by_lower:
            entries[by_lower[name.lower()]]['check'] = check

    for entry in entries.values():
        text = entry.pop('_text', '')
        if entry['type'] != 'action' or any(entry.get(field) for field in ('check', 'self_effect', 'strike', 'strikes')):
            continue
        one = ONE.search(text)
        if one and not NOT_ONE.search(text):
            kind = attack_kind(one.group(1))
            entry['strikes'] = {'count': 1, **({'attack': kind} if kind else {})}

    for name, entry in OWN.items():
        entries.setdefault(name, entry)

    if args.write:
        open(os.path.join(CONFIG, OUT), 'w').write(rendered(entries))
        foundry_source.record(args.checkout, __file__, [os.path.join(CONFIG, OUT)])

    selves = sum(1 for entry in entries.values() if entry.get('self_effect'))

    print('written' if args.write else 'dry run')
    print(f'  {len(entries)} actions: {len(entries) - feat_actions} from their actions, {feat_actions} feats')
    print(f'  {sum(other_books.values())} from books the game does not use left out: '
          f'{", ".join(f"{book} {count}" for book, count in other_books.most_common())}')
    print(f'  {selves} put an effect on whoever uses them')
    print(f'  {len(declared) - len(unmatched)} roll a check; macros naming no action we hold: {unmatched}')
    print('\nwhat their actions carry that is not read yet:')
    for why, count in counted.most_common(20):
        print(f'  {count:5d}  {why}')


if __name__ == '__main__':
    main()
