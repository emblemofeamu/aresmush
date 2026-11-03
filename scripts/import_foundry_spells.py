#!/usr/bin/env python3
"""What a spell does when it is cast at someone, from Foundry's spells.

Our spell catalogue (`pf2e_spells_*.yml`) describes a spell for a player to read and for a caster to
prepare. Casting one at a target needs what Foundry holds as data beside the prose: the defence it is
against - a save, basic or not, or AC for a spell attack - its damage and how that grows as it is
heightened, and its area. Those are written to `pf2e_spell_mechanics.yml`, keyed by the spell's name.

What a save's outcome does beyond damage is in the prose: Fear's failure leaves the target Frightened 2.
The prose links the condition it means (`@UUID[...conditionitems...]{Frightened 2}`), and the paragraph it
sits in says which outcome it is, so each outcome's conditions and effects are read from there. Every
outcome of a save happens to whoever rolled it, which is what makes the link enough.

Not every spell gives its outcomes paragraphs of their own. Daze says it in a sentence: "If the target
critically fails the save, it is also Stunned 1." So a sentence that names an outcome - "critically
fails", "on a failure", "on a success" - gives that outcome the conditions in the same clause, including
a numbered one written without a link ("or sickened 2 on a critical failure"). A failure's condition is
a critical failure's too, unless the sentence gives the critical failure its own.

And what an outcome does that is neither damage nor a condition - Command's "must use a single action
to do as you command" - is kept as its words (`outcome_text`), for the room to be told.

Usage: scripts/import_foundry_spells.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import json
import os
import re
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_foundry_npcs as npcs  # noqa: E402
import foundry_source  # noqa: E402
import import_foundry_rules as rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')
OUT = 'pf2e_spell_mechanics.yml'

OUTCOMES = {'Critical Success': 'criticalSuccess', 'Success': 'success', 'Failure': 'failure',
            'Critical Failure': 'criticalFailure'}
PARAGRAPH = re.compile(r'<strong>(Critical Success|Critical Failure|Success|Failure)</strong>(.*?)(?=<strong>(?:Critical Success|Critical Failure|Success|Failure)</strong>|<hr|</p>\s*<p><strong>Heightened|\Z)',
                       re.S)
# A link, with the words it shows or without: `@UUID[...Item.Frightened]{Frightened 2}`, or
# `@UUID[...Item.Fleeing]`, which shows the item's own name.
LINK = re.compile(r'@UUID\[Compendium\.pf2e\.([\w-]+)\.Item\.([^\]]+)\](?:\{([^}]+)\})?')


def shown(link):
    return link.group(3) or link.group(2)

# How long something an outcome leaves lasts. Counted from the caster's turn: to the end of this one, to
# the end or start of their next, or a number of rounds, which ends as their turn starts that many
# rounds on; a minute is ten rounds. Or counted from the turn of whoever it was left on, which is what
# "its next turn" means: `its-` and the same words.
THEIRS = r"(?:its|their|the target's|the creature's|that creature's)"
UNTIL = [(re.compile(r'until the end of (?:your|the caster\'s) next turn', re.I), lambda _: 'next-turn-end'),
         (re.compile(r'until the (?:start|beginning) of (?:your|the caster\'s) (?:next )?turn', re.I), lambda _: 'next-turn-start'),
         (re.compile(r'until the end of (?:your|the caster\'s) turn', re.I), lambda _: 'turn-end'),
         (re.compile(r'until the end of ' + THEIRS + r' next turn', re.I), lambda _: 'its-next-turn-end'),
         (re.compile(r'until the end of ' + THEIRS + r' turn', re.I), lambda _: 'its-turn-end'),
         (re.compile(r'until the (?:start|beginning) of ' + THEIRS + r' (?:next )?turn', re.I), lambda _: 'its-next-turn-start'),
         (re.compile(r'until ' + THEIRS + r' next turn begins', re.I), lambda _: 'its-next-turn-start'),
         (re.compile(r'until ' + THEIRS + r' next turn ends', re.I), lambda _: 'its-next-turn-end'),
         (re.compile(r'until your next turn begins', re.I), lambda _: 'next-turn-start'),
         (re.compile(r'until your next turn ends', re.I), lambda _: 'next-turn-end'),
         (re.compile(r'for (\d+) rounds?', re.I), lambda found: f'rounds:{found.group(1)}'),
         (re.compile(r'for (\d+) minutes?', re.I), lambda found: f'rounds:{int(found.group(1)) * 10}')]


VALUED_NAMES = ('Clumsy', 'Doomed', 'Drained', 'Enfeebled', 'Frightened', 'Sickened', 'Slowed', 'Stunned', 'Stupefied')

# The conditions this game has, which is what an outcome may leave: a spell that links an attitude -
# Charm's Friendly - leaves no condition the engine knows.
CONDITIONS = set(yaml.safe_load(open(os.path.join(CONFIG, 'pf2e_conditions.yml')))['pf2e_conditions'])

# What the caster gains, said of "you": Blinding Fury's "you become hidden to it".
THE_CASTER = re.compile(r"\byou(?:'re)?\s+(?:become|are|gain)\b|\brendering you\b|\byou are\b", re.I)


def duration_of(text, durations, link):
    """The duration a linked condition lasts for, by where the sentence that holds it says it. Read with
    every link blanked out, because a link's own path is full of full stops."""
    text = LINK.sub(lambda found: '#' * len(found.group(0)), text)
    start = max(text.rfind('.', 0, link.start()), text.rfind(';', 0, link.start())) + 1
    end_at = [at for at in (text.find('.', link.end()), text.find(';', link.end())) if at >= 0]
    end = min(end_at) if end_at else len(text)

    after = next((key for at, key in durations if link.end() <= at < end), None)
    if after:
        return after

    opening = next((key for at, key in durations
                    if start <= at < link.start() and not re.sub(r'<[^>]+>|\W', '', text[start:at])), None)

    return opening


def effects_in(effects_text):
    """What one outcome's paragraph leaves on the one who rolled: each condition it links, at the value
    its label gives, and each effect. A condition the paragraph gives the caster, or one this game does
    not have, is left out.

    A duration belongs to the conditions its sentence names before it - "confused and dazzled until the
    end of its next turn" - or, where the sentence opens with it, to all of them: "Until the end of its
    next turn, the target is stupefied 2 and fascinated". Frightened takes none, because it eases by
    itself each turn: "frightened 3 and fleeing for 1 round" is the fleeing's round."""
    found = []
    durations = sorted((match.start(), key(match)) for pattern, key in UNTIL for match in pattern.finditer(effects_text))
    links = list(LINK.finditer(effects_text))

    for index, link in enumerate(links):
        pack, label = link.group(1), shown(link)
        following = links[index + 1].start() if index + 1 < len(links) else len(effects_text)
        until = duration_of(effects_text, durations, link)

        sentence = re.split(r'[.;]', effects_text[:link.start()])[-1]

        if THE_CASTER.search(re.sub(r'@UUID\[[^\]]*\](\{[^}]*\})?', '', sentence)):
            continue

        if pack == 'conditionitems':
            named = re.match(r'(.+?)(?:\s+(\d+))?\Z', label.strip())
            one = {'condition': named.group(1).strip().title().replace('Off-guard', 'Off-Guard')}
            if one['condition'] not in CONDITIONS:
                continue
            if one['condition'] == 'Frightened':
                until = None
            if named.group(2):
                one['value'] = int(named.group(2))
            if until:
                one['until'] = until
            found.append(one)
        elif pack in ('spell-effects', 'other-effects', 'feat-effects', 'equipment-effects'):
            found.append({'effect': label.strip()})

    return found


# A condition an outcome's paragraph names without linking it, which Foundry does once a condition has
# been linked earlier in the description: Blindness links Blinded in its success and writes "blinded for
# 1 minute" in its failure. Only what leaves a creature worse off, and only in a paragraph that is one
# outcome's own.
UNLINKED = ('Blinded', 'Confused', 'Controlled', 'Dazzled', 'Deafened', 'Fascinated', 'Fatigued', 'Fleeing',
            'Grabbed', 'Immobilized', 'Off-Guard', 'Paralyzed', 'Petrified', 'Prone', 'Restrained', 'Unconscious')
NAMED = re.compile(r'\b(?:(' + '|'.join(VALUED_NAMES) + r')\s+(\d+)|(' + '|'.join(UNLINKED) + r'))\b', re.I)

# A sentence that says a condition is not so, or is another's, or is so only on some further condition:
# "the creature is off-guard for as long as it's immobilized", "such as dropping prone".
NOT_SO = re.compile(r"\b(?:not|no longer|isn't|aren't|can't|cannot|immune|unless|rather than|instead of|as if|as though|"
                    r"ends?|remove[sd]?|reduc\w+|recover\w*|if|such as|while|as long as|can|may|might|would|choose[sd]?|either|"
                    r"already|whenever|when)\b", re.I)


def unlinked_in(text, already):
    """What an outcome's paragraph leaves that it names without a link, beyond what its links gave."""
    blank = LINK.sub(lambda found: '#' * len(found.group(0)), re.sub(r'<[^>]+>', lambda found: ' ' * len(found.group(0)), text))
    durations = sorted((match.start(), key(match)) for pattern, key in UNTIL for match in pattern.finditer(blank))
    held = {one['condition'] for one in already if 'condition' in one}
    found = []

    for match in NAMED.finditer(blank):
        name = (match.group(1) or match.group(3)).title().replace('Off-guard', 'Off-Guard')
        start = max(blank.rfind('.', 0, match.start()), blank.rfind(';', 0, match.start())) + 1
        ends = [at for at in (blank.find('.', match.end()), blank.find(';', match.end())) if at >= 0]
        sentence = blank[start:min(ends) if ends else len(blank)]

        if name in held or name not in CONDITIONS or NOT_SO.search(sentence) or THE_CASTER.search(sentence):
            continue

        one = {'condition': name}
        if match.group(2):
            one['value'] = int(match.group(2))
        until = duration_of(blank, durations, match)
        # An end the sentence gives in words this does not read is left to the words.
        if not until and re.search(r'\buntil\b', sentence, re.I):
            continue
        if until and name != 'Frightened':
            one['until'] = until
        held.add(name)
        found.append(one)

    return found


def outcomes_of(description):
    out = {}

    for label, text in PARAGRAPH.findall(description or ''):
        held = effects_in(text)
        held = held + unlinked_in(text, held)
        if held:
            out[OUTCOMES[label]] = held

    for outcome, held in prose_outcomes(description).items():
        out.setdefault(outcome, held)

    return out


# Outcomes as a sentence names them, most particular first.
SPOKEN = [(re.compile(r'critically fails|critical failure|critically failed', re.I), 'criticalFailure'),
          (re.compile(r'critically succeeds|critical success', re.I), 'criticalSuccess'),
          (re.compile(r'\bfails\b|\bfailure\b|\bfailed\b', re.I), 'failure'),
          (re.compile(r'\bon a success\b|\bsucceeds\b', re.I), 'success')]

# A sentence whose outcome belongs to another roll, or that a condition escapes, is not read: "must
# succeed at a Reflex save or become off-guard" is a second save, and "unless it Escapes" a way out.
AMBIGUOUS = re.compile(r'must succeed|unless|\bStrike\b|Heightened', re.I)

# A condition with a value, written without a link.
VALUED = VALUED_NAMES
PLAIN = re.compile(r'\b(' + '|'.join(VALUED) + r')\s+(\d+)\b', re.I)


def prose_outcomes(description):
    """The outcomes a spell names in its sentences rather than in paragraphs of their own."""
    rest = PARAGRAPH.sub('', description or '').split('<strong>Heightened')[0]
    out = {}

    for sentence in re.split(r'(?<=[.!?])\s+|</p>', rest):
        if AMBIGUOUS.search(re.sub(r'@UUID\[[^\]]*\]', '', sentence)):
            continue

        said = {}
        for clause in re.split(r';|\(|\)|, or |, and on ', sentence):
            outcome = next((key for pattern, key in SPOKEN if pattern.search(re.sub(r'@UUID\[[^\]]*\]', '', clause))), None)
            held = effects_in(clause) + plain_conditions(clause)
            if outcome and held:
                said.setdefault(outcome, []).extend(held)

        if 'failure' in said and 'criticalFailure' not in said:
            said['criticalFailure'] = list(said['failure'])

        for outcome, held in said.items():
            out.setdefault(outcome, []).extend(held)

    return out


def plain_conditions(clause):
    """Numbered conditions a clause names without linking them."""
    unlinked = LINK.sub('', clause)

    return [{'condition': name.title(), 'value': int(value)} for name, value in PLAIN.findall(re.sub(r'<[^>]+>', '', unlinked))]


# What a spell with no save does to its target where its words say so outright: Stabilize's "The target
# loses the Dying condition".
ENDS = re.compile(r'The target loses the (\w+) condition')


def outcome_text_of(description):
    """Each outcome paragraph as the words a player reads."""
    out = {}

    for label, text in PARAGRAPH.findall(description or ''):
        words = rules.plain(LINK.sub(shown, text))
        if words:
            out[OUTCOMES[label]] = words

    return out


# How much of the damage an outcome deals, by what the spell's own paragraph for it says. Most saves
# that are not basic still say "unaffected", "half", "full" and "double"; where a paragraph says none of
# these, the scale is left out and the GM applies the damage by the text.
#
# The amounts are tried before the refusals, because "takes half damage and takes no persistent damage"
# is half damage.
#
# The damage may be named by its kind between: "half the persistent fire damage".
KIND = r'(?:(?!no\b)[a-z]+ ){0,3}'
SCALES = [(re.compile(rf'\bhalf (?:the )?{KIND}damage\b', re.I), 0.5),
          (re.compile(rf'\bdouble (?:the )?{KIND}damage\b', re.I), 2),
          (re.compile(rf'\bfull {KIND}damage\b|\btakes? (?:the )?(?:full )?{KIND}damage\b', re.I), 1),
          (re.compile(r'\bunaffected\b|\bno effect\b|\bno damage\b|\btakes? no\b[^.]*\bdamage\b', re.I), 0)]


def damage_scale_of(description):
    out = {}

    for label, text in PARAGRAPH.findall(description or ''):
        plain = re.sub(r'<[^>]+>', ' ', text)
        factor = next((factor for pattern, factor in SCALES if pattern.search(plain)), None)
        if factor is not None:
            out[OUTCOMES[label]] = factor

    return out


def variant_of(overlay, base):
    """A spell cast another way - Heal with two actions, or against the undead - as the fields it changes."""
    system = overlay.get('system') or {}
    variant = {'name': overlay.get('name')}

    time = (system.get('time') or {}).get('value')
    if time:
        variant['time'] = str(time)
    for field in ('range', 'target'):
        value = (system.get(field) or {}).get(field == 'range' and 'value' or 'value')
        if value:
            variant[field] = value
    area = system.get('area')
    if isinstance(area, dict) and area.get('value'):
        variant['area'] = f"{area.get('value')}-foot {area.get('type')}"
    if 'defense' in system:
        save = (system.get('defense') or {}).get('save') if isinstance(system.get('defense'), dict) else None
        variant['save'] = save.get('statistic') if save else None
        variant['basic'] = bool(save.get('basic')) if save else False

    damage = system.get('damage') or {}
    if damage:
        # The spell's own damage as this way changes it, then any this way deals of its own - Lay on
        # Hands deals nothing until it is cast one way or the other.
        own = base.get('damage') or {}
        keys = [key for key, one in own.items() if one.get('formula')] + \
               [key for key, one in damage.items() if key not in own and one.get('formula')]
        merged = []
        for key in keys:
            one = own.get(key) or {}
            change = damage.get(key) or {}
            merged.append({'formula': change.get('formula', one.get('formula')), 'type': change.get('type', one.get('type')),
                           'category': change.get('category', one.get('category')),
                           'kinds': change.get('kinds', one.get('kinds') or ['damage'])})
        variant['damage'] = merged
        heightening = (system.get('heightening') or {}).get('damage')
        if heightening:
            variant['heightening'] = {'interval': (system.get('heightening') or {}).get('interval') or
                                                  (base.get('heightening') or {}).get('interval', 1),
                                      'damage': [heightening.get(key) for key in keys]}

    return variant


def damage_of(system):
    return [{'formula': one.get('formula'), 'type': one.get('type'), 'category': one.get('category'),
             'kinds': one.get('kinds') or ['damage']}
            for one in (system.get('damage') or {}).values() if one.get('formula')]


def heightening_of(system, damage_keys):
    held = system.get('heightening') or {}

    if held.get('type') == 'interval':
        per = [held.get('damage', {}).get(key) for key in damage_keys]
        if any(per):
            return {'interval': held.get('interval', 1), 'damage': per}
    elif held.get('type') == 'fixed':
        levels = {}
        for rank, change in (held.get('levels') or {}).items():
            damage = (change or {}).get('damage') or {}
            formulas = [(damage.get(key) or {}).get('formula') for key in damage_keys]
            if any(formulas):
                levels[str(rank)] = formulas
        if levels:
            return {'fixed': levels}

    return None


def mechanics_of(doc):
    system = doc['system']
    traits = (system.get('traits') or {}).get('value') or []
    defense = system.get('defense') or {}
    save = defense.get('save') if isinstance(defense, dict) else None
    damage_keys = [key for key, one in (system.get('damage') or {}).items() if one.get('formula')]

    entry = {'rank': 0 if 'cantrip' in traits else (system.get('level') or {}).get('value', 1),
             'traits': traits}

    # How long it takes to cast: `2`, `1 to 3`, `reaction`, `10 minutes`.
    time = (system.get('time') or {}).get('value')
    if time:
        entry['time'] = str(time)
    if 'attack' in traits:
        entry['attack'] = True
    if save and save.get('statistic'):
        entry['save'] = save['statistic']
        entry['basic'] = bool(save.get('basic'))

    damage = damage_of(system)
    if damage:
        entry['damage'] = damage
        heightened = heightening_of(system, damage_keys)
        if heightened:
            entry['heightening'] = heightened

    area = system.get('area')
    if isinstance(area, dict) and area.get('value'):
        entry['area'] = f"{area.get('value')}-foot {area.get('type')}"
    for field in ('target', 'range'):
        value = (system.get(field) or {}).get('value')
        if value:
            entry[field] = value

    description = (system.get('description') or {}).get('value')
    outcomes = outcomes_of(description)
    if outcomes:
        entry['outcomes'] = outcomes
    ended = ENDS.findall(LINK.sub(shown, description or '')) if not save else []
    if ended:
        entry['applies'] = [{'remove': [name.title() for name in ended]}]
    if save:
        words = outcome_text_of(description)
        if words:
            entry['outcome_text'] = words
    if save and not save.get('basic') and damage:
        scale = damage_scale_of(description)
        if scale:
            entry['damage_scale'] = scale

    overlays = sorted((system.get('overlays') or {}).values(), key=lambda one: one.get('sort', 0))
    variants = [variant_of(one, system) for one in overlays if one.get('overlayType') == 'override']
    variants = [one for one in variants if len(one) > 1]
    if variants:
        entry['variants'] = variants

    return entry


def rendered(entries):
    lines = ['---', 'pf2e_spell_mechanics:']

    for name, entry in sorted(entries.items()):
        lines.append(f'  {json.dumps(name, ensure_ascii=False)}:')
        for field, held in entry.items():
            lines.append(f'    {field}: {json.dumps(held, ensure_ascii=False)}')

    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    # The English an outcome's `@Localize[...]` is read from, and a spell's level is its rank.
    rules.strings(args.checkout)
    rules.RANKED = True
    entries = {}

    for path, body in npcs.blobs(args.checkout, 'packs/pf2e/spells'):
        if not path.startswith('packs/pf2e/spells/'):
            continue

        doc = json.loads(body)

        if doc.get('type') == 'spell' and isinstance(doc.get('system'), dict):
            entries[doc['name']] = mechanics_of(doc)

    if args.write:
        open(os.path.join(CONFIG, OUT), 'w').write(rendered(entries))
        foundry_source.record(args.checkout, __file__, [os.path.join(CONFIG, OUT)])

    print('written' if args.write else 'dry run')
    print(f"  {len(entries)} spells: {sum('save' in one for one in entries.values())} with a save, "
          f"{sum('attack' in one for one in entries.values())} an attack, "
          f"{sum('damage' in one for one in entries.values())} damage, "
          f"{sum('outcomes' in one for one in entries.values())} leaving conditions or effects")


if __name__ == '__main__':
    main()
