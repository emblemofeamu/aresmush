#!/usr/bin/env python3
"""Replace a spell's effect and heighten text in game/config/pf2e_spells_*.yml with the text the
Foundry VTT pf2e system carries for it.

    python3 scripts/import_foundry_spell_text.py --foundry <dir holding packs/spells> "Adapt Self" ...
    python3 scripts/import_foundry_spell_text.py --foundry <dir> --all-in <commit>

Only effect and heighten are touched; rank, traits, actions, range, target, duration and area are
left as they are. Without --apply it prints the conversion and changes nothing.
"""
import argparse, glob, html, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')

# Foundry links the automation it ships for a spell from the middle of the prose. Those entries are
# machinery, not text, and the catalogue has never carried them.
AUTOMATION_PACKS = ('spell-effects', 'feat-effects', 'equipment-effects', 'other-effects')


def resolve_uuid(match):
    body, label = match.group(1), match.group(2)

    if any(pack in body for pack in AUTOMATION_PACKS):
        return ''

    name = label or body.rsplit('.', 1)[-1]

    # Foundry capitalises a condition because it is a link label; Paizo's prose does not, and
    # neither does this catalogue. A sentence that opens on one is put back below.
    if 'conditionitems' in body and name:
        return name[0].lower() + name[1:]

    return name


def resolve_check(match):
    parts = match.group(1).split('|')
    kind = parts[0]
    fields = dict(p.split(':', 1) for p in parts[1:] if ':' in p)
    dc = fields.get('dc')

    return f"{kind} check (DC {dc})" if dc else f"{kind} check"


def to_markup(raw):
    """Foundry's description HTML in the markup the game's templates speak."""
    text = raw or ''

    text = re.sub(r'@UUID\[([^\]]*)\](?:\{([^}]*)\})?', resolve_uuid, text)
    text = re.sub(r'@Check\[([^\]]*)\](?:\{[^}]*\})?', resolve_check, text)

    text = re.sub(r'<strong>\s*(.*?)\s*</strong>', r'**\1**', text, flags=re.S)
    text = re.sub(r'<em>\s*(.*?)\s*</em>', r'*\1*', text, flags=re.S)

    # A bulleted list sits under the paragraph introducing it, one item to a line.
    text = re.sub(r'\s*<ul>\s*', '%r%r', text)
    text = re.sub(r'\s*</ul>\s*', '%r%r', text)
    text = re.sub(r'\s*<li>\s*', '%t- ', text)
    text = re.sub(r'\s*</li>\s*', '%r', text)

    text = re.sub(r'<hr\s*/?>', '%r%r', text)
    text = re.sub(r'</p>\s*<p>', '%r%r', text)
    text = re.sub(r'</?p>', '%r%r', text)
    text = re.sub(r'<[^>]+>', '', text)

    text = html.unescape(text)
    text = re.sub(r'[ \t\n\r]+', ' ', text)
    text = re.sub(r'\s*%r\s*', '%r', text)
    text = re.sub(r'(%r){3,}', '%r%r', text)
    text = tighten_degrees(text)
    text = open_sentences(text)

    return text.strip('%r ').strip()


DEGREES = r'\*\*(?:Critical Success|Success|Failure|Critical Failure)\*\*'


def tighten_degrees(text):
    """Foundry gives each degree of success its own paragraph; the catalogue runs them together
    under one break."""
    return re.sub(rf'({DEGREES}[^%]*(?:%r(?!%r))?[^%]*)%r%r(?={DEGREES})', r'\1%r', text)


def open_sentences(text):
    return re.sub(r'(\A|(?<=\. )|(?<=%r)|(?<=%t- ))([a-z])', lambda m: m.group(1) + m.group(2).upper(), text)


TRIGGER = re.compile(r'\A\*\*Trigger\*\*\s*(.*?)(?:%r)+', re.S)


def split_trigger(effect):
    """A reaction's trigger opens Foundry's description and is the catalogue's own field."""
    match = TRIGGER.match(effect)

    if not match:
        return None, effect

    return match.group(1).strip(), effect[match.end():].strip('%r ').strip()


HEIGHTENED = re.compile(r'(%r)*\s*(\*\*Heightened.*)$', re.S)


def split_heighten(effect):
    """The trailing Heightened paragraphs become the catalogue's own field."""
    match = HEIGHTENED.search(effect)

    if not match:
        return effect, None

    # "**Heightened (+1)** text" in Foundry, "**+1:** text" in this catalogue.
    tail = re.sub(r'\*\*Heightened \(([^)]*)\)\*\*\s*', r'**\1:** ', match.group(2))

    # One rank to a line, the way the catalogue's existing heighten fields read.
    tail = re.sub(r'%r%r(?=\*\*[^*]+:\*\*)', '%r', tail)

    return effect[:match.start()].strip('%r ').strip(), tail.strip('%r ').strip()


def load_foundry(path):
    found = {}

    for file in glob.glob(os.path.join(path, '**', '*.json'), recursive=True):
        if os.path.basename(file).startswith('_'):
            continue
        doc = json.load(open(file))
        if doc.get('type') == 'spell':
            found[doc['name']] = doc

    return found


def quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def rewrite(path, name, trigger, effect, heighten):
    """Replace the text fields of the entry, leaving its mechanical ones alone."""
    lines = open(path, encoding='utf-8').read().split('\n')
    start = next(i for i, line in enumerate(lines) if line == f'  {name}:')
    end = next((i for i in range(start + 1, len(lines)) if re.match(r'^  \S', lines[i])), len(lines))

    fields = { 'effect': effect, 'heighten': heighten }

    if trigger:
        fields['trigger'] = trigger

    body = []

    # Each field keeps the position it already had; one the entry did not carry goes on the end.
    for line in lines[start + 1:end]:
        field = re.match(r'^    (\w+):', line)
        name = field and field.group(1)

        if name not in fields:
            body.append(line)
        elif fields[name]:
            body.append(f'    {name}: {quote(fields.pop(name))}')
        else:
            fields.pop(name)

    body += [f'    {name}: {quote(value)}' for name, value in fields.items() if value]

    lines[start + 1:end] = body
    open(path, 'w', encoding='utf-8').write('\n'.join(lines))


def file_holding(name):
    for path in sorted(glob.glob(os.path.join(CONFIG, '*spell*.yml'))):
        if any(line.rstrip() == f'  {name}:' for line in open(path, encoding='utf-8')):
            return path

    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--foundry', required=True, help='a checkout holding packs/spells')
    parser.add_argument('--apply', action='store_true', help='write, rather than only report')
    parser.add_argument('names', nargs='+')
    args = parser.parse_args()

    foundry = load_foundry(args.foundry)
    missing = [name for name in args.names if name not in foundry]

    if missing:
        sys.exit(f'not in Foundry: {", ".join(missing)}')

    for name in args.names:
        path = file_holding(name)

        if not path:
            sys.exit(f'not in the catalogue: {name}')

        effect, heighten = split_heighten(to_markup(foundry[name]['system']['description']['value']))
        trigger, effect = split_trigger(effect)

        print(f'== {name}  ({os.path.basename(path)})')
        if trigger:
            print(f'   trigger: {trigger}')
        print(f'   effect: {effect}')
        if heighten:
            print(f'   heighten: {heighten}')

        if args.apply:
            rewrite(path, name, trigger, effect, heighten)


main()
