"""python3 -m unittest scripts/test_note_effects.py"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_foundry_note_effects as notes  # noqa: E402
import import_foundry_rules as rules  # noqa: E402

SYMPATHETIC = ('Until the beginning of your next turn, the target takes a -1 penalty. '
               '@UUID[Compendium.pf2e.feat-effects.Item.qBTJYpopY3AwFFUJ]{Effect: Sympathetic Strike}')


class LinkedEffects(unittest.TestCase):

    def setUp(self):
        self.ids = dict(rules.EFFECT_IDS)
        rules.EFFECT_IDS.clear()
        rules.EFFECT_IDS['qBTJYpopY3AwFFUJ'] = 'Effect: Sympathetic Strike'

    def tearDown(self):
        rules.EFFECT_IDS.clear()
        rules.EFFECT_IDS.update(self.ids)

    def test_a_link_by_id_is_named(self):
        self.assertEqual(rules.linked_effects(SYMPATHETIC, {}), ['Effect: Sympathetic Strike'])

    def test_a_link_by_name_keeps_the_name(self):
        text = '@UUID[Compendium.pf2e.spell-effects.Item.Spell Effect: Web]{Web}'
        self.assertEqual(rules.linked_effects(text, {}), ['Spell Effect: Web'])

    def test_a_localisation_key_is_read_in_english(self):
        found = {'PF2E.SpecificRule.Sympathetic.Note': SYMPATHETIC}
        self.assertEqual(rules.linked_effects('PF2E.SpecificRule.Sympathetic.Note', found),
                         ['Effect: Sympathetic Strike'])

    def test_a_link_to_anything_else_is_not_an_effect(self):
        text = '@UUID[Compendium.pf2e.conditionitems.Item.Frightened]{Frightened}'
        self.assertEqual(rules.linked_effects(text, {}), [])

    def test_one_effect_linked_twice_is_named_once(self):
        self.assertEqual(rules.linked_effects(SYMPATHETIC + ' ' + SYMPATHETIC, {}), ['Effect: Sympathetic Strike'])


class Filling(unittest.TestCase):

    CATALOGUE = '\n'.join([
        'pf2e_feat_class:',
        '  Sympathetic Strike:',
        '    rules:',
        '    - key: Note',
        '      selector: unarmed-attack-roll',
        '      outcome:',
        '      - success',
        '      - criticalSuccess',
        '      text: Until the beginning of your next turn...',
        '    - key: Note',
        '      selector: unarmed-attack-roll',
        '      text: Something else',
        '  Other Feat:',
        '    rules: []',
        ''])

    def fill(self, linked):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '__pycache__', 'note_effects_fixture.yml')
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as out:
            out.write(self.CATALOGUE)
        report = {'matched': 0, 'unmatched': [], 'found': set()}
        try:
            return notes.fill(path, linked, report), report
        finally:
            os.remove(path)

    def test_the_row_with_the_same_selector_and_outcomes_gets_the_effect(self):
        shape = notes.shape('unarmed-attack-roll', ['criticalSuccess', 'success'])
        text, report = self.fill({'Sympathetic Strike': [(shape, ['Effect: Sympathetic Strike'])]})

        lines = text.split('\n')
        self.assertEqual(lines[9], '      effects: ["Effect: Sympathetic Strike"]')
        self.assertEqual(lines[10], '    - key: Note')
        self.assertEqual(text.count('effects:'), 1)
        self.assertEqual(report['matched'], 1)

    def test_a_note_with_no_row_of_ours_is_reported(self):
        shape = notes.shape('strike-damage', None)
        text, report = self.fill({'Sympathetic Strike': [(shape, ['Effect: Sympathetic Strike'])]})

        self.assertIsNone(text)
        self.assertEqual(len(report['unmatched']), 1)


if __name__ == '__main__':
    unittest.main()
