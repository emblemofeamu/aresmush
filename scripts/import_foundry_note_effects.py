#!/usr/bin/env python3
"""The effects a note links, as `effects:` on the Note rows we already stock.

A Note in Foundry's data may link an effect in its text: Sympathetic Strike's note on a hit ends
`@UUID[Compendium.pf2e.feat-effects.Item.qBTJYpopY3AwFFUJ]{Effect: Sympathetic Strike}`. Foundry shows
the link in the chat card and the player drags it onto whoever it is for. Our importers turn the link
into its label, so the words survived and the link did not, and nothing could apply the effect.

`import_foundry_rules.py` now keeps the links on the rows it writes (`linked_effects`). This adds them to
the rows already written without importing anything else again, because the catalogues hold hand edits a
full reimport would lose. Only Note rows change, and only by an `effects:` line: a row of ours is matched
to one of theirs on the same item by its selector and its outcomes, in order.

Usage: scripts/import_foundry_note_effects.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import json
import os
import re
import subprocess
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_foundry_rules as rules  # noqa: E402

CONFIG = rules.CONFIG

# Their packs, and our catalogues each one fills. The effect packs fill the effect catalogue.
EFFECT_PACKS = ['feat-effects', 'spell-effects', 'equipment-effects', 'other-effects', 'campaign-effects']
SOURCES = rules.SOURCES + [(pack, ['pf2e_effects.yml']) for pack in EFFECT_PACKS]

ROW_START = re.compile(r'^(\s*)- key: "?Note"?\s*$')


def shape(selector, outcome):
    """What a note is matched on: its selectors and its outcomes, in no order."""
    selectors = selector if isinstance(selector, list) else [selector]
    outcomes = outcome if isinstance(outcome, list) else ([] if outcome is None else [outcome])

    return (tuple(sorted(str(one) for one in selectors)), tuple(sorted(str(one) for one in outcomes)))


def theirs(checkout, words):
    """name -> [(shape, effects)] for every item whose notes link an effect, in their order."""
    found = {}

    for pack, _catalogues in SOURCES:
        items = rules.foundry(checkout, pack)
        if pack == 'actions':
            from import_foundry_actions import RENAMED
            items = {RENAMED.get(item, item): held for item, held in items.items() if item not in RENAMED.values()}

        for item, (held_rules, _declared) in items.items():
            linked = [(shape(rule.get('selector') or rule.get('selectors'), rule.get('outcome')),
                       rules.linked_effects(rule.get('text'), words))
                      for rule in held_rules if rule.get('key') == 'Note']
            linked = [one for one in linked if one[1]]
            if linked:
                found.setdefault(item, []).extend(linked)

    return found


def note_rows(lines, start, end):
    """Every Note row between two lines of a catalogue: (first line, last line, field indent, row)."""
    out = []
    index = start

    while index < end:
        opened = ROW_START.match(lines[index])
        if not opened:
            index += 1
            continue

        dash = len(opened.group(1))
        last = index
        while last + 1 < end:
            following = lines[last + 1]
            indent = len(following) - len(following.lstrip())
            if not following.strip() or indent <= dash:
                break
            last += 1

        text = '\n'.join(line[dash + 2:] if line.startswith(' ' * (dash + 2)) else line.strip()
                         for line in [lines[index].replace('- ', '  ', 1)] + lines[index + 1:last + 1])
        out.append((index, last, ' ' * (dash + 2), yaml.safe_load(text) or {}))
        index = last + 1

    return out


def item_span(lines, item):
    """The lines of one catalogue entry, from its name to the next entry."""
    heading = re.compile(rf'^  "?{re.escape(item)}"?:\s*$')
    start = next((index for index, line in enumerate(lines) if heading.match(line)), None)
    if start is None:
        return None

    end = start + 1
    while end < len(lines) and (not lines[end].strip() or lines[end].startswith('    ')):
        end += 1

    return start, end


def fill(path, linked, report):
    """Add `effects:` to the Note rows of one catalogue. Answers the new text, or None if unchanged."""
    lines = open(path, encoding='utf-8').read().split('\n')
    changed = False

    for item, notes in linked.items():
        span = item_span(lines, item)
        if not span:
            continue

        waiting = list(notes)
        # Bottom up, so a line added below leaves the rows above where they were.
        rows = note_rows(lines, *span)
        pairs = []
        for first, last, indent, row in rows:
            wanted = shape(row.get('selector') or row.get('selectors'), row.get('outcome'))
            match = next((one for one in waiting if one[0] == wanted), None)
            if match:
                waiting.remove(match)
                pairs.append((first, last, indent, row, match[1]))

        if pairs:
            report['found'].add(item)
        for _shape, effects in waiting:
            report['unmatched'].append((item, f'{os.path.basename(path)}: {item} ({", ".join(effects)})'))

        for first, last, indent, row, effects in reversed(pairs):
            report['matched'] += 1
            if row.get('effects') == effects:
                continue
            written = f'{indent}effects: {json.dumps(effects, ensure_ascii=False)}'
            existing = next((index for index in range(first, last + 1)
                             if lines[index].strip().startswith('effects:')), None)
            if existing is not None:
                lines[existing] = written
            else:
                lines.insert(last + 1, written)
            changed = True

    return '\n'.join(lines) if changed else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    words = rules.strings(args.checkout)
    rules.effect_ids(args.checkout)
    linked = theirs(args.checkout, words)
    commit = subprocess.run(['git', '-C', args.checkout, 'rev-parse', 'HEAD'], capture_output=True, text=True, encoding='utf-8').stdout.strip()

    catalogue = (yaml.safe_load(open(os.path.join(CONFIG, 'pf2e_effects.yml'), encoding='utf-8')) or {}).get('pf2e_effects', {})
    report = {'matched': 0, 'unmatched': [], 'found': set()}
    touched = []

    for name in sorted({one for _pack, catalogues in SOURCES for one in catalogues}):
        path = os.path.join(CONFIG, name)
        if not os.path.exists(path):
            continue
        text = fill(path, linked, report)
        if text is not None:
            touched.append(name)
            if args.write:
                open(path, 'w', encoding='utf-8', newline='\n').write(text)

    linked_names = sorted({effect for notes in linked.values() for _shape, effects in notes for effect in effects})

    print(f"{'written' if args.write else 'dry run'} from foundryvtt/pf2e {commit or '(unknown commit)'}")
    print(f"  notes with their effects: {report['matched']}; changed: {', '.join(touched) or 'nothing'}")
    print(f"  items with linked notes in their packs: {len(linked)}; of ours: {len(report['found'])}")
    missing = [name for name in linked_names if name not in catalogue]
    print(f"  linked effects not in pf2e_effects.yml: {len(missing)}")
    for name in missing:
        print(f'    {name}')
    # An item may share its name with an entry of another catalogue - Sympathetic Strike is a feat and an
    # action - so a note is unmatched only where no catalogue matched it.
    unmatched = [line for item, line in report['unmatched'] if item not in report['found']]
    if unmatched:
        print('  notes of theirs with no row of ours to match:')
        for one in unmatched:
            print(f'    {one}')


if __name__ == '__main__':
    main()
