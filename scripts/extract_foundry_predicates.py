#!/usr/bin/env python3
"""Every distinct predicate in Foundry's pf2e packs, one per line with its use count.

A predicate is how a rule element says "only in these circumstances": a list of statements
tested against a set of options. Pf2e::Predicate must find every line here structurally
valid - a line it rejects is a construct we have read wrongly, which would otherwise show up
as a bonus that applies when it should not.

Usage: scripts/extract_foundry_predicates.py /path/to/foundryvtt-pf2e
"""

import argparse
import collections
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'plugins', 'pf2e', 'specs', 'support', 'foundry_predicate_corpus.txt')

# `definition` is the same language, used by rules that describe a set of creatures rather than
# a circumstance.
FIELDS = ('predicate', 'definition')

HEADER = """\
# Every distinct predicate in the Foundry VTT pf2e system's shipped packs.
#
# Extracted from foundryvtt/pf2e (packs/), one JSON predicate per line, most-used first, with
# its use count. These are game mechanics: the items carrying them declare OGL 1.0a or ORC.
# Regenerate with scripts/extract_foundry_predicates.py.
#
# Pf2e::Predicate.valid? must accept every line. A line it rejects is a construct we have not
# read correctly - which is the whole reason this file is checked in rather than sampled.
"""


def rule_elements(node):
    """Every rule element under a pack document, including items embedded in actors."""
    stack = [node]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            system = current.get('system')
            rules = system.get('rules') if isinstance(system, dict) else None
            if isinstance(rules, list):
                for rule in rules:
                    if isinstance(rule, dict):
                        yield rule
            stack.extend(v for v in current.values() if isinstance(v, (dict, list)))
        elif isinstance(current, list):
            stack.extend(v for v in current if isinstance(v, (dict, list)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout', help='a foundryvtt/pf2e checkout with packs/')
    args = parser.parse_args()

    found = collections.Counter()

    for base, _dirs, names in os.walk(os.path.join(args.checkout, 'packs')):
        for name in names:
            if not name.endswith('.json'):
                continue
            try:
                doc = json.load(open(os.path.join(base, name), encoding='utf-8'))
            except Exception:
                continue

            for rule in rule_elements(doc):
                for field in FIELDS:
                    predicate = rule.get(field)
                    if isinstance(predicate, list) and predicate:
                        found[json.dumps(predicate, sort_keys=True)] += 1

    if not found:
        raise SystemExit(f'no predicates found under {args.checkout} - is packs/ there?')

    with open(OUT, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write(HEADER)
        for text, count in found.most_common():
            handle.write(f'{count}\t{text}\n')

    print(f'{len(found)} distinct predicates, {sum(found.values())} uses -> {OUT}')


main()
