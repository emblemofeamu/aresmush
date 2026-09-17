#!/usr/bin/env python3
"""Regenerate game/config/pf2e_renames.yml from Foundry's "Remaster Changes" journal.

The journal is one JSON file in the Foundry VTT pf2e system, with a table per category:

    curl -H "Accept: application/vnd.github.raw" -o remaster-changes.json \
      https://api.github.com/repos/foundryvtt/pf2e/contents/packs/pf2e/journals/remaster-changes.json
    python3 scripts/import_remaster_renames.py remaster-changes.json

spec/config_yaml_specs.rb checks the shape of what comes out, so a change to the journal's
markup fails a spec rather than reaching a player as an unreadable hint.
"""
import argparse, json, os, re, html, sys

STATUS = {
    'renamed': 'renamed', 'rename': 'renamed',
    'renamed, altered mechanics': 'renamed',
    'merged': 'merged', 'removed': 'removed',
}

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'game', 'config', 'pf2e_renames.yml')

parser = argparse.ArgumentParser()
parser.add_argument('journal', help="Foundry's packs/pf2e/journals/remaster-changes.json")
args = parser.parse_args()

pages = {p['name']: p['text']['content'] for p in json.load(open(args.journal))['pages']}


def rows(page):
    out = []
    for tr in re.findall(r'<tr>(.*?)</tr>', pages[page], re.S):
        tds = [html.unescape(re.sub(r'<[^>]+>', '', c)).strip()
               for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', tr, re.S)]
        if tds:
            out.append(tds)
    return out[1:]


def target(cell):
    label = re.search(r'@UUID\[[^\]]*\]\{([^}]*)\}', cell)
    if label:
        return label.group(1).strip()
    item = re.search(r'@UUID\[[^\]]*?\.Item\.([^\]]*)\]', cell)
    if item:
        return item.group(1).strip()
    return None


def table(page):
    entries = {}
    for row in rows(page):
        old, status, new = row[0], row[-2].lower(), row[-1]
        if old.startswith('@UUID') or status not in STATUS:
            continue
        status = STATUS[status]
        to = target(new)
        # A row marked Removed that still names where the thing went ("Folded into X") is a merge;
        # a row whose replacement is its own name kept the name and is nothing a player needs told.
        if to and to.lower() == old.lower():
            continue
        if status == 'removed' and to:
            status = 'merged'
        if status != 'removed' and not to:
            continue
        entries[old] = (status, to if status != 'removed' else None)
    return dict(sorted(entries.items(), key=lambda kv: kv[0].lower()))


def quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


lines = [
    '# Pre-Remaster names and where each one went, from the Foundry VTT pf2e system\'s own',
    '# "Remaster Changes" journal. Players arrive knowing the old names, so a lookup that misses',
    '# checks here before saying the name is not in the game.',
    '#',
    '# Regenerate with scripts/import_remaster_renames.py.',
    'pf2e_renames:',
]

for page, key in (('Spells', 'spells'), ('Feats', 'feats')):
    data = table(page)
    lines.append(f'  {key}:')
    for old, (status, to) in data.items():
        lines.append(f'    {quote(old)}:')
        lines.append(f'      status: {status}')
        if to:
            lines.append(f'      to: {quote(to)}')
    print(f'{key}: {len(data)}', file=sys.stderr)

open(OUT, 'w').write('\n'.join(lines) + '\n')
