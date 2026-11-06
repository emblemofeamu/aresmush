#!/usr/bin/env python3
"""Regenerate plugins/pf2e/specs/support/foundry_formula_corpus.txt from a Foundry pf2e checkout.

    git clone --depth 1 https://github.com/foundryvtt/pf2e /tmp/pf2e
    python3 scripts/extract_foundry_formulas.py /tmp/pf2e

Every arithmetic expression in their shipped packs, one per line with its use count. Pf2e::Formula
must parse all of them, which formula_specs.rb asserts - a line it cannot parse is a construct we
have read wrongly, and that is the reason this corpus is checked in rather than sampled.

The expressions are game mechanics; the items carrying them declare OGL 1.0a or ORC.
"""
import argparse, collections, json, glob, os, re

# Fields of a rule element whose content is an arithmetic value rather than a slug, a predicate or
# display text.
NUMERIC_FIELDS = ['value', 'diceNumber', 'radius', 'modifier', 'maxSlots', 'dim', 'bright', 'max', 'dice']
SKIP_FIELDS = {'label', 'text', 'title', 'description', 'img', 'name', 'uuid', 'note'}

FUNC = re.compile(r'\b([a-z][a-zA-Z0-9_]*)\s*\(')
ARITH = re.compile(r'(?:\d|\)|@[\w.]+|\})\s*[-+*/]\s*(?:\d|\(|@|\{|-)')
ASSET = re.compile(r'\.(webp|png|svg|jpg)')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'plugins', 'pf2e', 'specs', 'support', 'foundry_formula_corpus.txt')

HEADER = """\
# Every distinct arithmetic expression in the Foundry VTT pf2e system's shipped packs.
#
# Extracted from foundryvtt/pf2e (packs/), one expression per line, most-used first, with
# its use count. These are game mechanics: the items carrying them declare OGL 1.0a or ORC.
# Regenerate with scripts/extract_foundry_formulas.py.
#
# Pf2e::Formula must parse every line. A line it cannot parse is a construct we have not
# read correctly - which is the whole reason this file is checked in rather than sampled.
"""


def is_expression(text):
    if ASSET.search(text):
        return False

    return ('@' in text) or bool(FUNC.search(text)) or bool(ARITH.search(text)) \
        or bool(re.fullmatch(r'-?\d+', text.strip()))


def collect(node, field, out, depth=0):
    """Every string under `node`, tagged with the field name it sat under."""
    if depth > 12:
        return
    if isinstance(node, str):
        if field not in SKIP_FIELDS:
            out[field].append(node)
    elif isinstance(node, dict):
        for key, value in node.items():
            collect(value, key if isinstance(key, str) else field, out, depth + 1)
    elif isinstance(node, list):
        for value in node:
            collect(value, field, out, depth + 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout', help='a foundryvtt/pf2e checkout holding packs/')
    args = parser.parse_args()

    found = collections.Counter()

    for path in glob.glob(os.path.join(args.checkout, 'packs', '**', '*.json'), recursive=True):
        if os.path.basename(path).startswith('_'):
            continue
        try:
            doc = json.load(open(path, encoding='utf-8'))
        except Exception:
            continue

        # Rules live on items, and on items embedded in actors.
        stack = [doc]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                system = node.get('system')
                rules = system.get('rules') if isinstance(system, dict) else None
                if isinstance(rules, list):
                    for rule in rules:
                        if not isinstance(rule, dict):
                            continue
                        fields = collections.defaultdict(list)
                        for key, value in rule.items():
                            collect(value, key, fields)
                        for field in NUMERIC_FIELDS:
                            for text in fields.get(field, []):
                                if is_expression(text):
                                    found[text] += 1
                stack.extend(v for v in node.values() if isinstance(v, (dict, list)))
            elif isinstance(node, list):
                stack.extend(v for v in node if isinstance(v, (dict, list)))

    if not found:
        raise SystemExit(f'no expressions found under {args.checkout} - is packs/ there?')

    with open(OUT, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write(HEADER)
        for text, count in found.most_common():
            handle.write(f'{count}\t{text}\n')

    print(f'{len(found)} distinct expressions, {sum(found.values())} uses -> {OUT}')


main()
