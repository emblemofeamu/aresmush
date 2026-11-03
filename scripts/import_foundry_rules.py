#!/usr/bin/env python3
"""Foundry's rule elements, as `rules:` blocks on our conditions, items and feats.

Their pf2e system is the reference implementation of these mechanics, so a rule copied from their
data is a rule we have not got wrong. What this replaced was hand-written, and measurably wrong in
the same direction every time: of 51 item bonuses, 10 granted a conditional bonus unconditionally,
and of our 14 hand-written conditions, Unconscious penalised the wrong save.

Rows are copied field for field - `key`, `selector`, `value`, `type`, `predicate`, `diceNumber`,
`dieSize` - because a translation is a place to introduce an error. A rule is taken only when its
kind is one `Pf2e::Rules` implements, every selector maps to a domain we can reach, and every field
is one we read. Anything else is reported and left out, never flattened: a conditional bonus
imported without its condition is an item strictly better than the rules allow.

Usage: scripts/import_foundry_rules.py /path/to/foundryvtt-pf2e [--write]
"""

import argparse
import collections
import glob
import html
import json
import os
import re
import subprocess
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ea_dragons  # noqa: E402
import formula_words  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, 'game', 'config')

# Which Foundry pack feeds which of our catalogues. A feat's name is matched against the merged feat
# config, which is spread over several files.
SOURCES = [
    ('conditions', ['pf2e_conditions.yml']),
    ('equipment', ['pf2e_magicitem.yml', 'pf2e_armor.yml', 'pf2e_weapons.yml', 'pf2e_shields.yml',
                   'pf2e_gear.yml', 'pf2e_consumables.yml']),
    ('feats', ['pf2e_feat_ancestry.yml', 'pf2e_feat_class.yml', 'pf2e_feat_dedication.yml',
               'pf2e_feat_general.yml', 'pf2e_feat_skill.yml']),
    ('class-features', ['pf2e_class_features.yml']),
    # An action's own rules - Rage's +2 to melee damage while raging - which apply to whoever has it.
    ('actions', ['pf2e_actions.yml']),
]

# A subclass as their pack names it: a barbarian's Fury is their Fury Instinct, a sorcerer's Draconic
# their Bloodline: Draconic. Any class not named here calls it what we do.
SUBCLASS_NAMES = {'Barbarian': '{} Instinct', 'Druid': '{} Order', 'Sorcerer': 'Bloodline: {}',
                  'Investigator': '{} Methodology'}

# A subclass's rules the engine works out itself, so reading them as well would count them twice: a
# thief's Dexterity to finesse damage is `Pf2e::Damage.damage_attribute`'s.
HANDLED = {('Rogue', 'Thief'): lambda rule: rule.get('key') == 'FlatModifier' and rule.get('ability') == 'dex'}

# A class feature as the class tables grant it carries what it amounts to at that level - "Sneak Attack
# 2d6", "Incredible Movement (+15 feet)", "Precise Strike 3 (3d6)" - where their pack has one item that
# works it out itself. `Pf2e::Effects.feature_named` reads it the same way.
def feature_named(granted):
    name = re.sub(r'\s*\(.*\)$', '', granted)
    name = re.sub(r'\s+\d+d\d+$', '', name)
    name = re.sub(r'\s+\d+$', '', name)
    return name.strip()


def granted_features():
    """Every class feature a class or a specialty grants, by the name it has in their pack."""
    found = set()

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ('charclass_feature', 'charclass_features', 'features', 'feature') and isinstance(value, list):
                    found.update(feature_named(one) for one in value if isinstance(one, str))
                walk(value)
        elif isinstance(node, list):
            for one in node:
                walk(one)

    for name in ('pf2e_class.yml', 'pf2e_specialty.yml'):
        walk(yaml.safe_load(open(os.path.join(CONFIG, name))))

    return found


def subclasses(theirs):
    """Every class's subclasses their pack has, as `{ their name: (class, ours) }`."""
    found = {}
    specialties = yaml.safe_load(open(os.path.join(CONFIG, 'pf2e_specialty.yml')))['pf2e_specialty']

    for charclass, held in specialties.items():
        for ours in held or {}:
            name = SUBCLASS_NAMES.get(charclass, '{}').format(ours)
            if name in theirs:
                found[name] = (charclass, ours)

    return found


def class_feature_catalogue(theirs):
    """The class features and subclasses this game grants that their pack gives rules, as entries for
    the rules to be written under. A subclass's entry names the class and subclass it is."""
    lines = ['---',
             '# A class feature\'s or subclass\'s rule elements, from Foundry\'s class-features pack, written',
             '# by scripts/import_foundry_rules.py. An entry is a feature some class or specialty grants, or a',
             '# subclass, which says whose it is.',
             'pf2e_class_features:']
    named = subclasses(theirs)

    for name in sorted(granted_features() | set(named)):
        rules = [rule for rule in theirs.get(name, ([], []))[0] if rule.get('key') in KINDS]
        if not rules:
            continue
        lines += [f'  {json.dumps(name)}:', '    pack: "class-features"']
        if name in named:
            lines += [f'    charclass: {json.dumps(named[name][0])}', f'    subclass: {json.dumps(named[name][1])}']

    return '\n'.join(lines) + '\n'


def handled(rule, entry_text):
    """Whether a subclass's rule is one the engine works out itself."""
    charclass = re.search(r'^    charclass: "(.+)"$', entry_text or '', re.M)
    subclass = re.search(r'^    subclass: "(.+)"$', entry_text or '', re.M)
    test = HANDLED.get((charclass and charclass.group(1), subclass and subclass.group(1)))

    return bool(test and test(rule))


# The kinds Pf2e::Rules implements, and the fields it reads for each. What is listed here is written
# out: a field accepted and then dropped is a rule that reads as something other than what Foundry
# wrote, which is how `slug` went missing and every imported adjustment reached every modifier its
# selector touched. Anything deliberately not carried is named in PRESENTATION below instead.
KINDS = {
    'FlatModifier': {'key', 'selector', 'value', 'type', 'ability', 'min', 'max', 'damageType',
                     'damageCategory', 'critical', 'predicate', 'slug', 'label', 'hideIfDisabled', 'priority', 'phase',
                     'requiresEquipped', 'removeAfterRoll'},
    # Text shown with a roll, for an outcome where it says: Revel in Retribution's reminder on a hit.
    'Note': {'key', 'selector', 'text', 'title', 'predicate', 'outcome', 'slug', 'label', 'visibility',
             'priority'},
    # Traits an effect gives or takes away: Humanoid Form makes you humanoid, Soul Thief undead.
    'ActorTraits': {'key', 'add', 'remove', 'predicate', 'priority', 'slug', 'label'},
    # The most Dexterity counts towards AC: Mountain Stance, a mutagen.
    'DexterityModifierCap': {'key', 'value', 'predicate', 'slug', 'label'},
    # Hit points lost when an effect begins, and - where it says - not regained while it lasts.
    'LoseHitPoints': {'key', 'value', 'recoverable', 'reevaluateOnUpdate', 'predicate', 'slug', 'label'},
    # A fixed number in place of the d20: Assurance's 10.
    'SubstituteRoll': {'key', 'selector', 'value', 'required', 'effectType', 'removeAfterRoll', 'predicate',
                       'slug', 'label'},
    # A multiple attack penalty other than the usual: Agile Grace's -3.
    'MultipleAttackPenalty': {'key', 'selector', 'value', 'predicate', 'slug', 'label'},
    # How big the character is, and how far they reach.
    'CreatureSize': {'key', 'value', 'reach', 'resizeEquipment', 'maximumSize', 'minimumSize', 'predicate',
                     'slug', 'label'},
    # An emanation that puts effects on whoever is inside it.
    'Aura': {'key', 'radius', 'slug', 'traits', 'effects', 'predicate', 'level', 'label', 'appearance',
             'priority', 'mergeExisting'},
    # A polymorph: the form's AC, attacks, speeds and senses in place of the character's own.
    'BattleForm': {'key', 'overrides', 'brackets', 'predicate', 'hasHands', 'canCast', 'ownUnarmed',
                   'value', 'slug', 'label'},
    # Hit points regained as each turn starts; regeneration is switched off by damage it names.
    'FastHealing': {'key', 'value', 'type', 'details', 'deactivatedBy', 'predicate', 'slug', 'label'},
    # What an effect changes about one of the character's things while it lasts: Magic Weapon's runes.
    'ItemAlteration': {'key', 'itemType', 'itemId', 'mode', 'property', 'value', 'predicate', 'slug',
                       'label', 'priority', 'phase', 'fromEquipment'},
    # Fortune and misfortune: roll the d20 twice and keep the higher, or the lower.
    'RollTwice': {'key', 'selector', 'keep', 'predicate', 'removeAfterRoll', 'slug', 'label'},
    'DamageDice': {'key', 'selector', 'diceNumber', 'dieSize', 'damageType', 'category', 'critical',
                   'predicate', 'slug', 'label', 'hideIfDisabled', 'override', 'tags', 'priority', 'phase'},
    # placement and mergeable position a toggle in Foundry's character sheet, which is not a mechanic
    # and not an interface we have.
    'RollOption': {'key', 'option', 'domain', 'toggleable', 'value', 'predicate', 'slug', 'label',
                   'suboptions', 'selection', 'alwaysActive', 'disabledIf', 'disabledValue',
                   'placement', 'mergeable', 'phase', 'priority', 'requiresEquipped'},
    # phase and priority order writes against Foundry's data preparation, which has no counterpart here;
    # the modes are ordered instead, which is what the ordering is for.
    'ActiveEffectLike': {'key', 'path', 'mode', 'value', 'predicate', 'slug', 'label', 'phase',
                         'priority', 'merge'},
    # priority orders adjustments against Foundry's data preparation; ours are ordered by mode.
    'AdjustModifier': {'key', 'selector', 'selectors', 'slug', 'mode', 'value', 'suppress', 'relabel',
                       'damageType', 'maxApplications', 'predicate', 'label', 'priority', 'requiresEquipped'},
    'AdjustDegreeOfSuccess': {'key', 'selector', 'adjustment', 'predicate', 'type', 'slug', 'label'},
    'BaseSpeed': {'key', 'selector', 'value', 'predicate', 'slug', 'label'},
    # img is the icon their sheet shows; fist is a flag about replacing the default unarmed attack.
    # replaceAll makes it the only attack the character has, as a monk's stance does.
    'Strike': {'key', 'slug', 'label', 'category', 'group', 'baseType', 'damage', 'traits', 'otherTags',
               'range', 'predicate', 'img', 'fist', 'replaceAll'},
    'MartialProficiency': {'key', 'slug', 'definition', 'sameAs', 'maxRank', 'label'},
    'CriticalSpecialization': {'key', 'predicate', 'slug', 'label'},
    'Sense': {'key', 'selector', 'acuity', 'range', 'predicate', 'slug', 'label'},
    # adjustName renames the feat after the choice in Foundry's sheet; allowedDrops is a drag-and-drop
    # affordance. Neither is a mechanic.
    'ChoiceSet': {'key', 'choices', 'flag', 'prompt', 'rollOption', 'adjustName', 'predicate',
                  'allowNoSelection', 'allowedDrops', 'slug', 'label', 'priority'},
    'DamageAlteration': {'key', 'property', 'mode', 'value', 'selectors', 'selector', 'predicate',
                         'slug', 'label', 'priority', 'phase', 'requiresEquipped'},
    'AdjustStrike': {'key', 'property', 'mode', 'value', 'definition', 'predicate', 'slug', 'label', 'priority', 'phase'},
    'Immunity': {'key', 'type', 'value', 'predicate', 'definition', 'slug', 'label', 'exceptions'},
    'Weakness': {'key', 'type', 'value', 'predicate', 'definition', 'slug', 'label', 'exceptions'},
    'Resistance': {'key', 'type', 'value', 'predicate', 'definition', 'slug', 'label', 'exceptions', 'doubleVs'},
    # A condition or an effect that brings another with it: Grabbed makes you off-guard, Dying makes you
    # unconscious. `uuid` names the other by compendium, and Pf2e::Grants resolves it to our catalogue.
    # Temporary hit points, set when an effect begins and refreshed each turn where it says so.
    'TempHP': {'key', 'value', 'predicate', 'events', 'slug', 'label'},
    'GrantItem': {'key', 'uuid', 'inMemoryOnly', 'predicate', 'onDeleteActions', 'allowDuplicate',
                  'alterations', 'slug', 'label', 'priority'},
}

# The compendia a GrantItem may name that we hold as a catalogue of our own. A grant of anything else -
# an action, a monster's ability - has nothing here to become.
GRANTABLE = {'conditionitems', 'spell-effects', 'feat-effects', 'equipment-effects', 'other-effects'}
# The properties of an item an alteration may change that change something modelled here, and the
# kinds of thing it may alter. A spell's area, an action's frequency, an item's description are not.
ALTERED = {'traits', 'runes-potency', 'runes-striking', 'runes-resilient', 'damage-dice-faces',
           'damage-dice-number', 'damage-type', 'material-type', 'range-increment', 'group', 'category',
           'ac-bonus', 'dex-cap', 'check-penalty', 'speed-penalty', 'strength', 'hardness', 'badge-value',
           'badge-max', 'pd-recovery-dc', 'other-tags'}
ALTERABLE_ITEMS = {'weapon', 'armor', 'shield', 'condition'}

# The kinds of their own thing a character may be asked to choose among, as our inventory holds them.
# `melee` is a creature's natural attack, which a character's weapons list stands in for.
OWNED_TYPES = {'weapon', 'armor', 'shield', 'melee'}

LEDGER_PACKS = {'feats-srd', 'classfeatures', 'ancestryfeatures', 'heritages'}
GRANT_UUID = re.compile(r'^Compendium\.pf2e\.([\w-]+)\.Item\.(.+)$')

# What an alteration of a granted item may change. The badge is the one a condition carries: Encumbered
# makes you clumsy 1.
GRANT_ALTERATIONS = {'badge-value'}

# Fields that position a control in Foundry's character sheet, or order a rule against their data
# preparation passes. Accepted so a rule carrying one is not refused, and not written out, because
# neither describes a mechanic. This mirrors `Pf2e::Rules::PRESENTATION`.
PRESENTATION = {
    'RollOption': {'placement', 'mergeable', 'phase', 'priority'},
    'ActiveEffectLike': {'phase', 'priority'},
    'AdjustModifier': {'priority'},
    'AdjustStrike': {'priority', 'phase'},
    'DamageAlteration': {'priority', 'phase'},
    'DamageDice': {'priority', 'phase', 'hideIfDisabled'},
    'FlatModifier': {'priority', 'phase', 'hideIfDisabled'},
    'ChoiceSet': {'adjustName', 'allowedDrops', 'priority'},
    'Strike': {'img'},
    'GrantItem': {'priority'},
    # `fromEquipment` marks an alteration automatic bonus progression would replace, and there is no
    # automatic bonus progression here.
    'ItemAlteration': {'priority', 'phase', 'fromEquipment'},
    # Resizing the character's equipment matters to how items look in Foundry's canvas, and to Bulk, which
    # a size here does not change. How an aura is drawn is the canvas's too.
    'CreatureSize': {'resizeEquipment'},
    # Their priority orders a trait's arrival against their data preparation, which has no counterpart.
    'ActorTraits': {'priority'},
    'Aura': {'appearance', 'priority', 'mergeExisting'},
    # Whether a form has hands, or can cast, is a question for the actions it allows, which this engine
    # does not police.
    'BattleForm': {'hasHands', 'canCast'},
    # Who sees a note is a question for Foundry's chat log, which we do not have.
    'Note': {'visibility', 'priority'},
}

# The order fields are written in, so a re-run produces the same file. A field of a kind that is not
# named here still gets written, after these.
ORDER = ['key', 'add', 'remove', 'recoverable', 'reevaluateOnUpdate', 'required', 'effectType', 'overrides', 'brackets', 'radius', 'effects', 'reach', 'maximumSize', 'minimumSize',
         'ownUnarmed', 'itemType', 'itemId', 'property', 'uuid', 'inMemoryOnly', 'allowDuplicate', 'onDeleteActions', 'alterations', 'option', 'domain', 'toggleable', 'alwaysActive', 'suboptions', 'selection',
         'disabledIf', 'disabledValue', 'flag', 'rollOption', 'prompt', 'choices',
         'allowNoSelection', 'path', 'mode', 'merge',
         'property', 'definition', 'sameAs', 'maxRank',
         'acuity', 'range', 'category', 'group',
         'baseType', 'damage', 'traits', 'otherTags', 'fist', 'replaceAll', 'exceptions', 'doubleVs',
         'selector', 'selectors', 'adjustment', 'suppress', 'relabel',
         'maxApplications', 'type', 'ability',
         'value', 'min', 'max', 'diceNumber', 'dieSize', 'damageType', 'damageCategory',
         'critical', 'override', 'tags', 'hideIfDisabled', 'slug', 'requiresEquipped',
         'events', 'deactivatedBy', 'details', 'keep', 'outcome', 'removeAfterRoll', 'title', 'text', 'label', 'predicate']


def written(key):
    """The fields of one kind that are written out, in order."""
    fields = KINDS[key] - PRESENTATION.get(key, set()) - {''}

    return sorted(fields, key=lambda f: (ORDER.index(f) if f in ORDER else len(ORDER), f))


# Neither of these reaches a statistic: one declares a circumstance and the other writes a value.
SELECTORLESS = {'RollOption', 'ActiveEffectLike', 'Immunity', 'Weakness', 'Resistance', 'AdjustStrike', 'GrantItem',
                'TempHP', 'ItemAlteration', 'FastHealing', 'CreatureSize', 'Aura', 'BattleForm',
                'ActorTraits', 'DexterityModifierCap', 'LoseHitPoints',
                'Strike', 'MartialProficiency', 'CriticalSpecialization', 'Sense', 'ChoiceSet'}

# Senses this engine knows. One it does not would be a fact nothing could show or ask about.
SENSES = {'darkvision', 'greater-darkvision', 'low-light-vision', 'scent', 'tremorsense', 'echolocation',
          'lifesense', 'motion-sense', 'wavesense', 'thoughtsense', 'spiritsense', 'truesight'}

# What a DamageAlteration may change and have it mean something: the kind of damage, how many dice, how
# large they are. Anything else names a part of a damage roll this engine does not build.
ALTERABLE = {'damage-type', 'dice-number', 'dice-faces'}

# A BaseSpeed's selector is a kind of movement rather than a domain.
MOVEMENT = {'land', 'burrow', 'climb', 'fly', 'swim'}

# What an AdjustStrike may change and have it mean something here. A trait changes numbers; a material,
# a range increment and a property rune name things this engine does not model.
STRIKE_PROPERTIES = {'traits', 'weapon-traits', 'property-runes', 'materials', 'range-increment'}

# What an adjustment may do to one of those. A word is only ever added; a range increment is arithmetic.
STRIKE_MODES = {'add', 'multiply', 'upgrade', 'downgrade', 'override'}

# Paths Pf2e::Paths can write. Anything else is refused rather than written somewhere wrong.
WRITABLE = [
    re.compile(r'^system\.skills\.(?:[\w-]+|\{[^}]*\})\.rank$'),
    re.compile(r'^system\.proficiencies\.(defenses|attacks)\.[\w-]+\.rank$'),
    re.compile(r'^system\.attributes\.dying\.recoveryDC$'),
    re.compile(r'^system\.attributes\.hp\.recoveryMultiplier$'),
    re.compile(r'^system\.attributes\.(flanking\.canFlank|flanking\.canGangUp|flanking\.flankable'
               r'|familiarAbilities\.value)$'),
    re.compile(r'^inventory\.bulk\.(maxAddend|encumberedAfterAddend)$'),
    re.compile(r'^flags\.system\.[\w.]+$'),
]

TYPES = {'item', 'circumstance', 'status', 'ability', 'proficiency', 'potency', 'untyped'}

SKILLS = {'acrobatics', 'arcana', 'athletics', 'crafting', 'deception', 'diplomacy', 'intimidation',
          'medicine', 'nature', 'occultism', 'performance', 'religion', 'society', 'stealth',
          'survival', 'thievery'}

ATTRIBUTES = {'str', 'dex', 'con', 'int', 'wis', 'cha'}

# Domains Pf2e::Domains can produce that are not derived from a name.
PLAIN = ({'hp', 'ac', 'perception', 'saving-throw', 'fortitude', 'reflex', 'will', 'skill-check',
          'lore-skill-check', 'class-dc', 'class', 'spell-dc', 'spell-attack', 'all', 'check',
          'attack', 'attack-roll', 'strike-attack-roll', 'all-speeds', 'initiative',
          'healing-received'}
         | SKILLS
         | {f'{a}-based' for a in ATTRIBUTES}
         | {f'{a}-skill-check' for a in ATTRIBUTES}
         | {f'{a}-damage' for a in ATTRIBUTES}
         | {f'{a}-attack' for a in ATTRIBUTES})

# `{item|id}` is the item naming itself, which Pf2e::Effects resolves against the item's own id.
SELF_REFERENCE = re.compile(r'^\{item\|_?id\}(-.*)?$')

# A selector naming something off the weapon: its name, its group, its base type. These are domains
# we produce, so they are taken; an interpolation we cannot resolve is not.
DERIVED = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*-(?:damage|speed|attack|attack-roll|check'
                     r'|base-attack-roll|group-attack-roll|weapon-group-damage|base-damage'
                     r'|base-type-damage|strike-damage)$')

INTERPOLATION = re.compile(r'\{[^}]*\}')

# Foundry's own interpolation, as against a JSON object that merely has braces in it. A compound
# predicate is `{"or": [...]}` and is not an interpolation.
INJECTED = re.compile(r'\{(?:item|actor|choice|weapon|spell)\|')


# Their text is localisation keys - `PF2E.SpecificRule.Prompt.Skill` - with the English in
# `static/lang/en.json` and, for rule text, `static/lang/re-en.json`. A key is translated on the way
# in, so a note or a prompt reads as the words a player sees.
LANG_FILES = ['static/lang/en.json', 'static/lang/re-en.json', 'static/lang/action-en.json']
LANG_KEY = re.compile(r'\APF2E\.[\w.-]+\Z')

# The fields of a rule that are words for a player rather than mechanics.
WORDED = {'text', 'title', 'label', 'prompt'}

ENRICHER_START = re.compile(r'@(\w+)\[')
TAG = re.compile(r'<[^>]+>')

# The English `strings` last read, which `@Localize[...]` in a text is read from.
LOCALIZED = {}

# Whether the text being made plain is a spell's, where an item's level is the spell's rank.
RANKED = False

# What a text still holds of Foundry's markup when it has not been made plain.
MARKUP = re.compile(r'@(?:Localize|Damage|Check|UUID|Template)\[|\[\[/|<(?:p|br|hr|strong|em|span)\b')


def strings(checkout):
    """Every localisation key their packs name, as its English."""
    found = {}

    for name in LANG_FILES:
        path = os.path.join(checkout, name)
        if os.path.exists(path):
            text = open(path).read()
        else:
            shown = subprocess.run(['git', '-C', checkout, 'show', f'HEAD:{name}'],
                                   capture_output=True, text=True)
            if shown.returncode != 0:
                continue
            text = shown.stdout
        flatten(json.loads(text), '', found)
    LOCALIZED.update(found)

    return found


def flatten(node, prefix, out):
    for key, held in node.items():
        path = f'{prefix}{key}'
        if isinstance(held, dict):
            flatten(held, path + '.', out)
        else:
            out[path] = held


def closing(text, start):
    """Where the bracket opened at `start` closes, counting the brackets nested inside it -
    `@Damage[1d6[bludgeoning]]` holds a pair of its own."""
    depth = 0

    for index in range(start, len(text)):
        if text[index] == '[':
            depth += 1
        elif text[index] == ']':
            depth -= 1
            if depth == 0:
                return index

    return -1


def spoken(kind, target):
    """What an enricher without a label reads as. A link is the name of what it links to; damage is
    its formula and type; a check is the statistic, with its DC where it has one."""
    if kind == 'UUID':
        return target.split('.Item.')[-1].split('.')[-1]
    if kind == 'Damage':
        # The roll's own options - `|options:area-damage` - say how it is rolled, not what it is.
        formula = target.split('|')[0]
        formula = re.sub(r'\[([\w,-]+)\]', lambda found: ' ' + found.group(1).replace(',', ' '), formula).strip()
        return re.sub(r',\s*', ', ', formula)
    if kind == 'Localize':
        return enrich(LOCALIZED.get(target, ''))
    if kind == 'Check':
        parts = target.split('|')
        dc = next((part.split(':', 1)[1] for part in parts if part.startswith('dc:')), None)
        named = parts[0].replace('-', ' ').title()
        named = f'basic {named}' if 'basic' in parts else named
        return f'DC {dc} {named}' if dc and dc.isdigit() else named
    if kind == 'Template':
        parts = target.split('|')
        fields = dict(part.split(':', 1) for part in parts if ':' in part)
        shape = fields.get('type') or next((part for part in parts if ':' not in part), '')
        return f"{fields.get('distance', '')}-foot {shape}".strip()

    return ''


def enrich(text):
    """Every enricher as the words it shows: `@UUID[...]{Prone}` is Prone, `@Damage[1d6[bludgeoning]]`
    is 1d6 bludgeoning, and an inline roll `[[/act trip]]{Athletics}` is its label or its formula."""
    out = []
    index = 0

    while index < len(text):
        found = ENRICHER_START.match(text, index)
        inline = text.startswith('[[', index)

        if found or inline:
            opened = found.end() - 1 if found else index
            shut = closing(text, opened)

            if shut < 0:
                out.append(text[index])
                index += 1
                continue

            label_end = shut + 1
            label = None
            if text.startswith('{', label_end):
                ends = text.find('}', label_end)
                if ends > 0:
                    label = text[label_end + 1:ends]
                    label_end = ends + 1

            if found:
                out.append(label if label is not None else spoken(found.group(1), text[opened + 1:shut]))
            else:
                formula = text[index + 2:shut - 1].split(' ', 1)
                out.append(label if label is not None else (formula[1] if len(formula) > 1 else '').strip('{} '))

            index = label_end
            continue

        out.append(text[index])
        index += 1

    return ''.join(out)


def plain(text, limit=None):
    """Their HTML as a line a player can read, with a paragraph as `%r`, which is how our config breaks
    a line, and each roll formula in it as words (`formula_words`)."""
    text = enrich(text or '')
    text = re.sub(r'</p>|<hr\s*/?>|<br\s*/?>', '\x00', text)
    text = TAG.sub(' ', text)
    text = html.unescape(re.sub(r'\s+', ' ', text)).strip()
    text = re.sub(r'(?:\s*\x00\s*)+', '%r', text)
    text = re.sub(r'\A(?:%r)+|(?:%r)+\Z', '', text)
    text = formula_words.in_words(text, ranked=RANKED)

    if limit and len(text) > limit:
        text = text[:limit].rsplit(' ', 1)[0] + '…'

    return text


def translated(value, found):
    """A localisation key as its English, a text still in Foundry's markup as plain words, and anything
    else as it stands."""
    if isinstance(value, str) and LANG_KEY.match(value) and value in found:
        return plain(found[value])
    if isinstance(value, str) and MARKUP.search(value):
        return plain(value)

    return value


def worded(row, found):
    """A rule with its player-facing words translated: its own label or note, and the labels of the
    answers a choice set or an option offers."""
    out = {}

    for field, held in row.items():
        if field in WORDED:
            out[field] = translated(held, found)
        elif field in ('choices', 'suboptions') and isinstance(held, list):
            out[field] = [dict(one, label=translated(one.get('label'), found)) if isinstance(one, dict)
                          and 'label' in one else one for one in held]
        else:
            out[field] = held

    return out


def selector_ok(selector):
    if not isinstance(selector, str):
        return False
    slug = selector.strip()
    if SELF_REFERENCE.match(slug):
        return True
    # A selector naming the thing the player chose - `{item|flags.system.rulesSelections.weapon}-damage`
    # is the damage of the weapon they picked - is checked by shape, with the answer standing in.
    if INJECTED.search(slug):
        # One that is nothing but the answer - Assurance's skill - names whatever the answer is.
        if INTERPOLATION.fullmatch(slug):
            return True
        return selector_ok(INTERPOLATION.sub('chosen', slug))
    if INTERPOLATION.search(slug):
        return False
    if slug in PLAIN or slug == 'damage' or slug.endswith('-lore'):
        return True
    return bool(DERIVED.match(slug))


def documents(node):
    if isinstance(node, list):
        for item in node:
            yield from documents(item)
    elif isinstance(node, dict):
        if 'system' in node and 'type' in node:
            yield node
        for value in node.values():
            yield from documents(value)


def foundry(checkout, pack):
    """name -> (rules, options the item declares for itself)."""
    found = collections.defaultdict(lambda: ([], []))
    base = os.path.join(checkout, 'packs', 'pf2e', pack)

    for path in glob.glob(os.path.join(base, '**', '*.json'), recursive=True):
        try:
            doc = json.load(open(path))
        except Exception:
            continue
        for document in documents(doc):
            rules, options = found[document.get('name')]
            for rule in ((document.get('system') or {}).get('rules') or []):
                if isinstance(rule, dict):
                    rules.append(rule)

    return found


def take(rule, refused):
    """The rule as we would write it, or None with a reason recorded."""
    fields = KINDS[rule['key']]

    if rule['key'] not in SELECTORLESS and rule['key'] != 'BaseSpeed' \
            and not (rule.get('selector') or rule.get('selectors')):
        refused['no selector'] += 1
        return None

    # An adjustment that changes only a damage type, or one whose outcome we cannot read, adjusts
    # nothing here.
    if rule['key'] == 'AdjustModifier' and not (rule.get('suppress') or rule.get('value') is not None):
        refused['adjustment with no value'] += 1
        return None

    if rule['key'] == 'AdjustDegreeOfSuccess':
        named = rule.get('adjustment')
        if not isinstance(named, dict) or not named:
            refused['degree adjustment is not a mapping'] += 1
            return None

    # A kind of damage we cannot resolve - a charm whose type the wearer chose - would resist nothing.
    if rule['key'] in ('Immunity', 'Weakness', 'Resistance'):
        # One or the other: a kind of damage named, or a description of what it applies to.
        if not rule.get('type') and not rule.get('definition'):
            refused['iwr naming nothing'] += 1
            return None
        pass

    if rule['key'] == 'ActiveEffectLike':
        path = rule.get('path') or ''
        if not any(p.match(path) for p in WRITABLE):
            refused[f'path {path!r}'] += 1
            return None
        # A value that is a list or an object is a list of Foundry documents - the shapes a druid knows,
        # by compendium id. Nothing here can read one, so storing it would be noise rather than a rule.
        if not isinstance(rule.get('value'), (int, float, str, bool)):
            refused['value is a list of foundry documents'] += 1
            return None

    strays = set(rule) - fields
    if strays:
        refused[f"{rule['key']} field {sorted(strays)}"] += 1
        return None

    if rule['key'] == 'GrantItem':
        found = GRANT_UUID.match(str(rule.get('uuid') or ''))
        # A feat or a class feature granted by another is a pick, and picks are the ledger's: a feat's
        # own `grants:` records it as a grant of its own, so reading it here as well would give it twice.
        if not found or found.group(1) in LEDGER_PACKS:
            refused['a feat or feature it grants, which the ledger records as a grant of its own'] += 1
            return None
        if found.group(1) not in GRANTABLE:
            refused[f'a grant from {found.group(1)}, which we hold no catalogue of'] += 1
            return None
        altered = rule.get('alterations') or []
        if any((one or {}).get('property') not in GRANT_ALTERATIONS for one in altered):
            refused['a grant altering something other than its badge'] += 1
            return None

    if rule['key'] == 'ItemAlteration':
        if rule.get('property') not in ALTERED:
            refused[f"an alteration of {rule.get('property')}, which changes nothing modelled here"] += 1
            return None
        if not rule.get('itemId') and rule.get('itemType') not in ALTERABLE_ITEMS:
            refused[f"an alteration of {rule.get('itemType')} items, which are not things here"] += 1
            return None

    if rule['key'] == 'BaseSpeed':
        if rule.get('selector') not in MOVEMENT:
            refused[f"movement {rule.get('selector')!r}"] += 1
            return None
    elif rule['key'] == 'ChoiceSet':
        choices = rule.get('choices')
        # A set lists its answers, names a vocabulary, describes them with a filter over a catalogue, or
        # asks for one of the character's own things - "the weapon you choose". A set shaped some other
        # way says nothing we can offer.
        if isinstance(choices, list):
            if not all(isinstance(one, dict) and one.get('value') for one in choices):
                refused['choice set whose listed answers say nothing'] += 1
                return None
        elif isinstance(choices, dict) and choices.get('ownedItems'):
            if not set(choices.get('types') or []) <= OWNED_TYPES:
                refused[f"choice set among owned {sorted(choices.get('types') or [])}"] += 1
                return None
        elif isinstance(choices, dict):
            if not (choices.get('config') or choices.get('filter')):
                refused[f'choice set querying {sorted(choices)}'] += 1
                return None
        else:
            refused['choice set that is neither a list nor a query'] += 1
            return None
    elif rule['key'] == 'Sense':
        if rule.get('selector') not in SENSES:
            refused[f"sense {rule.get('selector')!r}"] += 1
            return None
    elif rule['key'] == 'DamageAlteration':
        if rule.get('property') not in ALTERABLE:
            refused[f"alterable {rule.get('property')!r}"] += 1
            return None
        pass
    elif rule['key'] == 'MartialProficiency':
        if not rule.get('sameAs'):
            refused['martial proficiency with nothing to copy'] += 1
            return None
        pass
    elif rule['key'] == 'Strike':
        # An attack with no damage of its own is one we could not roll.
        base = (rule.get('damage') or {}).get('base') or {}
        if not base.get('die'):
            refused['strike with no damage die'] += 1
            return None
    elif rule['key'] == 'AdjustStrike':
        if rule.get('property') not in STRIKE_PROPERTIES:
            refused[f"strike property {rule.get('property')!r}"] += 1
            return None
        listed = rule.get('property') in ('traits', 'weapon-traits', 'property-runes', 'materials')
        allowed = {'add'} if listed else STRIKE_MODES
        if rule.get('mode') not in allowed:
            refused[f"strike mode {rule.get('mode')!r} on {rule.get('property')}"] += 1
            return None
    elif rule['key'] not in SELECTORLESS:
        named = rule.get('selector') or rule.get('selectors')
        selectors = named if isinstance(named, list) else [named]
        bad = [s for s in selectors if not selector_ok(s)]
        if bad:
            refused[f'selector {bad}'] += 1
            return None

    if rule['key'] == 'FlatModifier':
        if rule.get('type') and rule['type'] not in TYPES:
            refused[f"type {rule['type']!r}"] += 1
            return None
        if not isinstance(rule.get('value'), (int, str)):
            refused[f"value {rule.get('value')!r}"] += 1
            return None

    return {field: rule[field] for field in written(rule['key']) if field in rule}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('checkout', nargs='?')
    parser.add_argument('--write', action='store_true')
    # What this reads, for `Pf2e::Rules` to be held against: a field accepted here and unread there
    # would be a rule doing less than it says, and one read there and refused here an effect nobody
    # can import. `imported_rules_specs.rb` compares the two.
    parser.add_argument('--fields', action='store_true')
    # One pack, where the others are not to be read again: `--only class-features`.
    parser.add_argument('--only')
    args = parser.parse_args()

    if args.fields:
        print(json.dumps({'fields': {k: sorted(v) for k, v in KINDS.items()},
                          'presentation': {k: sorted(v) for k, v in PRESENTATION.items()}}))
        return

    if not args.checkout:
        raise SystemExit('a checkout of foundryvtt/pf2e is needed')

    refused = collections.Counter()
    totals = collections.Counter()
    # Kinds of rule element nothing here reads at all, on the things we stock. Counted so the refusals
    # above are not the whole story: a kind we have not built is a larger gap than a rule we refused.
    unread = collections.Counter()
    words = strings(args.checkout)

    for pack, catalogues in SOURCES:
        if args.only and pack != args.only:
            continue

        theirs = foundry(args.checkout, pack)
        if not theirs:
            raise SystemExit(f'no {pack} under {args.checkout}')

        # An action the game renames takes its rules under the new name, and whatever Foundry already
        # calls by that name - another book's action - gives it none.
        if pack == 'actions':
            from import_foundry_actions import RENAMED
            theirs = {RENAMED.get(item, item): found for item, found in theirs.items() if item not in RENAMED.values()}

        # The class features' catalogue is made from the class tables, then filled like any other.
        made = class_feature_catalogue(theirs) if pack == 'class-features' else None
        if made and args.write:
            open(os.path.join(CONFIG, 'pf2e_class_features.yml'), 'w').write(ea_dragons.dragon_instinct(made))

        for name in catalogues:
            path = os.path.join(CONFIG, name)
            if not made and not os.path.exists(path):
                continue
            text = made or open(path).read()
            additions = {}

            for item, (rules, declared) in theirs.items():
                found = item and re.search(rf'^  "?{re.escape(item)}"?:$\n((?:    .*\n)*)', text, re.M)
                if not found:
                    continue
                rules = [rule for rule in rules if not handled(rule, found.group(1))]
                for rule in rules:
                    if rule.get('key') not in KINDS:
                        unread[rule.get('key')] += 1
                rows = [worded(row, words)
                        for row in (take(rule, refused) for rule in rules if rule.get('key') in KINDS)
                        if row]
                if not rows:
                    continue
                additions[item] = (rows, [])

            totals[pack] += len(additions)
            totals[f'{pack} rows'] += sum(len(rows) for rows, _ in additions.values())

            if args.write and additions:
                open(path, 'w').write(insert(text, additions))

    print('written' if args.write else 'dry run')
    for pack, _ in SOURCES:
        if args.only and pack != args.only:
            continue
        print(f"  {pack}: {totals[pack]} entries, {totals[f'{pack} rows']} rules")
    print('\nkinds of rule nothing here reads, on what we stock:')
    for kind, count in unread.most_common(12):
        print(f'  {count:5d}  {kind}')
    print('\nrules refused rather than flattened:')
    for why, count in refused.most_common(20):
        print(f'  {count:5d}  {why}')


def yaml_value(value, indent):
    """A rule's field as YAML: a scalar inline, anything structured as JSON, which YAML reads."""
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value)
    return json.dumps(value)


def yaml_rows(entry, indent='    '):
    rows, _unused = entry
    out = [f'{indent}rules:']
    for row in rows:
        first = True
        for field, value in row.items():
            lead = '  - ' if first else '    '
            out.append(f'{indent}{lead}{field}: {yaml_value(value, indent)}')
            first = False
    return out


def insert(text, additions):
    """A `rules:` block under each named entry, replacing one already there.

    Walked line by line rather than matched: an entry's keys sit at four spaces and a block's rows at
    six or more, so a block being replaced ends at the first line that is not one of its rows.
    """
    out = []
    pending = None
    dropping = False

    for line in text.split('\n'):
        if dropping:
            if re.match(r'^ {6,}\S', line) or not line.strip():
                continue
            dropping = False

        if re.match(r'^    (?:rules|grants_options|modifies|affected_stat):\s*$', line):
            dropping = True
            continue

        header = re.match(r'^  "?([^\s#"][^"]*?)"?:$', line)
        if header:
            if pending:
                out.extend(yaml_rows(additions[pending]))
            pending = header.group(1) if header.group(1) in additions else None

        out.append(line)

    if pending:
        out.extend(yaml_rows(additions[pending]))

    text = '\n'.join(out)

    return text if text.endswith('\n') else text + '\n'


if __name__ == "__main__":
    main()
