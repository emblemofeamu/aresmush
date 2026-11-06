#!/usr/bin/env python3
"""GM Core's tables for building creatures, from Archives of Nethys, as `game/config/pf2e_creature_benchmarks.yml`.

GM Core gives, for each creature level from -1 to 24, what a figure is at each band: a high AC, a
moderate Strike bonus, a low Hit Points range. The creature checker compares a saved creature's figures
with these (`Pf2e::CreatureBenchmarks`), and flags one above the highest band for its author and for the
admins who approve it.

The tables are read from the Archives' search index, the pages whose ids are listed below, so they are
transcribed by this script from the source and never typed from memory. A cell is kept as the book
prints it, made into data:

  +5            5
  -             nil (the book gives none at that level)
  8-7, +2 to +1 [8, 7], [2, 1]: a range, high end first
  1d6+1 (4)     { formula: 1d6+1, average: 4 }

GM Core's base road maps - a brute, a skirmisher, a spellcaster - are prose, not a table: each names the
band of a few figures, and the rest are moderate. They are transcribed below as a band per figure, the
first where the book offers two ("high or extreme Str modifier" is high), each with the words it is read
from. The script fetches the sidebar and refuses to write if any of those words is not in it, and writes
each road map's own words beside its bands, for an author to read.

Usage: scripts/import_creature_benchmarks.py [--write]
"""

import argparse
import datetime
import json
import os
import re
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'config', 'pf2e_creature_benchmarks.yml')
ROAD_MAPS_OUT = os.path.join(ROOT, 'game', 'config', 'pf2e_creature_road_maps.yml')
ROAD_MAPS_SIDEBAR = 'Base Road Maps'
SEARCH = 'https://elasticsearch.aonprd.com/aon/_search'

# What each page's table is called here, and the GM Core page it is on.
TABLES = {
    'attribute': (2881, 114),
    'perception': (2882, 115),
    'skill': (2885, 116),
    'ac': (2889, 117),
    'save': (2890, 118),
    'hp': (2891, 118),
    'resistance': (2893, 119),
    'strike_attack': (2896, 120),
    'strike_damage': (2897, 120),
    'spell': (2899, 122),
    'area_damage': (2910, 124),
}

# Each road map: the band of each figure it names, and the words of the sidebar each is read from. A figure
# is `<table>` or `<table>.<which>`: `save.reflex`, `attribute.str`. Where the book offers two bands the
# first is taken; "low or lower" is low, the lowest the tables give a creature.
ROAD_MAPS = {
    'Brute': {
        'perception': ('low', 'low Perception'),
        'attribute.str': ('high', 'high or extreme Str modifier'),
        'attribute.con': ('high', 'high to moderate Con modifier'),
        'attribute.dex': ('low', 'low or lower Dex and mental modifiers'),
        'attribute.int': ('low', 'low or lower Dex and mental modifiers'),
        'attribute.wis': ('low', 'low or lower Dex and mental modifiers'),
        'attribute.cha': ('low', 'low or lower Dex and mental modifiers'),
        'ac': ('moderate', 'moderate or low AC'),
        'save.fortitude': ('high', 'high Fortitude'),
        'save.reflex': ('low', 'low Reflex or Will or both'),
        'hp': ('high', 'high HP'),
        'strike_attack': ('high', 'high attack bonus and high damage'),
        'strike_damage': ('high', 'high attack bonus and high damage'),
    },
    'Magical Striker': {
        'strike_attack': ('high', 'high attack and high damage'),
        'strike_damage': ('high', 'high attack and high damage'),
        'spell': ('moderate', 'moderate to high spell DCs'),
    },
    'Skill Paragon': {
        'save.reflex': ('high', 'typically high Reflex or Will'),
        'save.fortitude': ('low', 'low Fortitude'),
    },
    'Skirmisher': {
        'attribute.dex': ('high', 'high Dex modifier'),
        'save.fortitude': ('low', 'low Fortitude, high Reflex'),
        'save.reflex': ('high', 'low Fortitude, high Reflex'),
    },
    'Sniper': {
        'perception': ('high', 'high Perception'),
        'attribute.dex': ('high', 'high Dex modifier'),
        'save.fortitude': ('low', 'low Fortitude, high Reflex'),
        'save.reflex': ('high', 'low Fortitude, high Reflex'),
        'hp': ('moderate', 'moderate to low HP'),
        'strike_attack': ('high', 'ranged Strikes have high attack bonus and damage'),
        'strike_damage': ('high', 'ranged Strikes have high attack bonus and damage'),
        'ranged': (True, 'ranged Strikes'),
    },
    'Soldier': {
        'attribute.str': ('high', 'high Str modifier'),
        'ac': ('high', 'high to extreme AC'),
        'save.fortitude': ('high', 'high Fortitude'),
        'strike_attack': ('high', 'high attack bonus and high damage'),
        'strike_damage': ('high', 'high attack bonus and high damage'),
    },
    'Spellcaster': {
        'save.fortitude': ('low', 'low Fortitude, high Will'),
        'save.will': ('high', 'low Fortitude, high Will'),
        'hp': ('low', 'low HP'),
        'strike_attack': ('low', 'low attack bonus and moderate or low damage'),
        'strike_damage': ('moderate', 'low attack bonus and moderate or low damage'),
        'spell': ('high', 'high or extreme spell DCs'),
    },
}


def sidebar(name):
    """GM Core's sidebar of that name, as the search index holds its words."""
    query = json.dumps({'size': 5, 'query': {'bool': {'must': [{'match_phrase': {'name': name}},
                                                                {'match': {'source': 'GM Core'}}]}}}).encode()
    request = urllib.request.Request(SEARCH, data=query, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request) as answer:
        hits = [hit['_source'] for hit in json.load(answer)['hits']['hits']]
    found = [one for one in hits if one.get('name') == name and 'GM Core' in (one.get('source') or [])]
    if not found:
        raise SystemExit(f'No GM Core sidebar called {name!r} in the search index')
    return found[0]['text']


def road_maps(text):
    """Each road map's own words from the sidebar, and its bands, refused where the words they are read
    from are not there."""
    names = list(ROAD_MAPS)
    found = {}
    for index, name in enumerate(names):
        start = text.index(f' {name} ') + len(name) + 2
        end = text.index(f' {names[index + 1]} ', start) if index + 1 < len(names) else len(text)
        says = text[start:end].strip()
        for figure, (_band, words) in ROAD_MAPS[name].items():
            if words not in says:
                raise SystemExit(f'{name}: {figure} is read from {words!r}, which the sidebar no longer says')
        found[name] = {'says': says, 'bands': {figure: band for figure, (band, _words) in ROAD_MAPS[name].items()}}
    return found


def rendered_road_maps(found, day):
    lines = ["# GM Core's base road maps (p. 112): the band of each figure a role names; any other is moderate.",
             f'# Written by scripts/import_creature_benchmarks.py from Archives of Nethys ("{ROAD_MAPS_SIDEBAR}") on {day};',
             '# run it again rather than editing by hand. Where the book offers two bands, the first is taken.',
             'pf2e_creature_road_maps:']
    for name, held in found.items():
        lines.append(f'  {json.dumps(name)}:')
        lines.append(f'    says: {json.dumps(held["says"], ensure_ascii=False)}')
        lines.append('    bands: { ' + ', '.join(f'{figure}: {json.dumps(band)}' for figure, band in held['bands'].items()) + ' }')
    return '\n'.join(lines) + '\n'


def fetched(rules_id):
    query = urllib.parse.urlencode({'q': f'url:"/Rules.aspx?ID={rules_id}"', 'size': 10})
    with urllib.request.urlopen(f'{SEARCH}?{query}') as answer:
        hits = json.load(answer)['hits']['hits']
    for hit in hits:
        markdown = hit['_source'].get('markdown') or ''
        if '<table' in markdown:
            return markdown[markdown.index('<table'):markdown.index('</table>')]
    raise SystemExit(f'No table found on Rules.aspx?ID={rules_id}')


def rows(table):
    found = re.findall(r'<tr>(.*?)</tr>', table, re.S)
    return [[cell.strip().strip('*').strip() for cell in re.findall(r'<td>(.*?)</td>', row, re.S)] for row in found]


def number(text):
    return int(text.replace('–', '-').replace('−', '-').replace('+', ''))


def cell(text):
    text = text.strip()
    if text in ('—', '-', '–', ''):
        return None
    damage = re.match(r'^(\d+d\d+(?:[+-]\d+)?) \((\d+)\)$', text)
    if damage:
        return {'formula': damage.group(1), 'average': int(damage.group(2))}
    spread = re.match(r'^([+-]?\d+)\s*(?:–|to)\s*([+-]?\d+)$', text.replace('−', '-'))
    if spread:
        return [number(spread.group(1)), number(spread.group(2))]
    return number(text)


def column(name):
    return re.sub(r'[^a-z]+', '_', name.lower()).strip('_')


def read(table):
    header, *body = rows(table)
    columns = [column(name) for name in header[1:]]
    levels = {number(row[0]): [cell(one) for one in row[1:]] for row in body}
    return {'columns': columns, 'levels': levels}


def yaml_value(value):
    if value is None:
        return 'null'
    if isinstance(value, list):
        return '[' + ', '.join(yaml_value(one) for one in value) + ']'
    if isinstance(value, dict):
        return '{ ' + ', '.join(f'{key}: {yaml_value(one)}' for key, one in value.items()) + ' }'
    return str(value)


def rendered(tables, day):
    lines = ['# GM Core\'s tables for building creatures (pp. 114-124), by creature level: what a figure is at each band.',
             f'# Written by scripts/import_creature_benchmarks.py from Archives of Nethys on {day}; run it again rather than',
             '# editing by hand. A range is [high end, low end]; damage is its formula and its average.',
             'pf2e_creature_benchmarks:']
    for name, held in tables.items():
        rules_id, page = TABLES[name]
        lines.append(f'  {name}:')
        lines.append(f'    source: "GM Core p. {page}, Archives of Nethys Rules.aspx?ID={rules_id}"')
        lines.append(f'    columns: [{", ".join(held["columns"])}]')
        lines.append('    levels:')
        for level, cells in held['levels'].items():
            lines.append(f'      {level}: {yaml_value(cells)}')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    tables = {name: read(fetched(rules_id)) for name, (rules_id, _page) in TABLES.items()}
    text = rendered(tables, datetime.date.today().isoformat())

    day = datetime.date.today().isoformat()
    maps = rendered_road_maps(road_maps(sidebar(ROAD_MAPS_SIDEBAR)), day)

    if args.write:
        open(OUT, 'w', encoding='utf-8', newline='\n').write(text)
        open(ROAD_MAPS_OUT, 'w', encoding='utf-8', newline='\n').write(maps)
        print(f'written {OUT} and {ROAD_MAPS_OUT}')
    else:
        print(text[:2000])
    for name, held in tables.items():
        print(f'  {name}: {held["columns"]}, levels {min(held["levels"])} to {max(held["levels"])}')


if __name__ == '__main__':
    main()
