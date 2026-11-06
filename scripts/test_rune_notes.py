"""python3 -m unittest scripts/test_rune_notes.py"""
import collections
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_foundry_rules as wording  # noqa: E402
import import_foundry_runes as runes  # noqa: E402

FOUND = {
    'PF2E.WeaponPropertyRune.crushing.Name': 'Crushing',
    'PF2E.WeaponPropertyRune.crushing.Note': ('When you critically hit a target with this weapon, your target becomes '
                                              'Clumsy 1. @UUID[Compendium.pf2e.equipment-effects.Item.zNHvhwHsC8ckhKVp]'
                                              '{Effect: Crushing}'),
}

CRUSHING = {'damage': {'notes': [{'outcome': ['criticalSuccess'], 'title': 'PF2E.WeaponPropertyRune.crushing.Name',
                                  'text': 'PF2E.WeaponPropertyRune.crushing.Note'}]}}


class RuneNotes(unittest.TestCase):

    def setUp(self):
        self.ids = dict(wording.EFFECT_IDS)
        wording.EFFECT_IDS.clear()
        wording.EFFECT_IDS['zNHvhwHsC8ckhKVp'] = 'Effect: Crushing'

    def tearDown(self):
        wording.EFFECT_IDS.clear()
        wording.EFFECT_IDS.update(self.ids)

    def rows(self, rune):
        refused = collections.Counter()
        return runes.rules_of(rune, 'crushing', refused, FOUND), refused

    def test_a_damage_note_is_a_note_on_the_weapons_damage(self):
        rows, refused = self.rows(CRUSHING)

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['key'], 'Note')
        self.assertEqual(rows[0]['selector'], '{item|id}-damage')
        self.assertEqual(rows[0]['outcome'], ['criticalSuccess'])
        self.assertEqual(rows[0]['title'], 'Crushing')
        self.assertTrue(rows[0]['text'].startswith('When you critically hit'))
        self.assertNotIn('@UUID', rows[0]['text'])
        self.assertEqual(refused, collections.Counter())

    def test_it_keeps_the_effect_its_text_links(self):
        rows, _refused = self.rows(CRUSHING)

        self.assertEqual(rows[0]['effects'], ['Effect: Crushing'])

    def test_an_attack_note_is_on_the_weapons_attack(self):
        rows, _refused = self.rows({'attack': CRUSHING['damage']})

        self.assertEqual(rows[0]['selector'], '{item|id}-attack')


if __name__ == '__main__':
    unittest.main()
