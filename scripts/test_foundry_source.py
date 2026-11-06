"""python3 -m unittest scripts/test_foundry_source.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import foundry_source  # noqa: E402
import import_foundry  # noqa: E402


def run(path, *args):
    subprocess.run(['git', '-C', path, *args], check=True, capture_output=True)


class FoundrySource(unittest.TestCase):

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.checkout = os.path.join(self.temp.name, 'pf2e')
        os.makedirs(os.path.join(self.checkout, 'packs'))
        run(self.checkout, 'init', '-q')
        run(self.checkout, 'config', 'user.email', 'test@example.com')
        run(self.checkout, 'config', 'user.name', 'test')
        json.dump({'version': '8.6.1'}, open(os.path.join(self.checkout, 'system.pf2e.json'), 'w', encoding='utf-8', newline='\n'))
        open(os.path.join(self.checkout, 'packs', 'one.json'), 'w', encoding='utf-8', newline='\n').write('{}')
        run(self.checkout, 'add', '.')
        run(self.checkout, 'commit', '-q', '-m', 'one')
        self.commit = subprocess.run(['git', '-C', self.checkout, 'rev-parse', 'HEAD'],
                                     capture_output=True, text=True, encoding='utf-8').stdout.strip()
        self.record = os.path.join(self.temp.name, 'record.yml')
        self.written = os.path.join(foundry_source.ROOT, 'game', 'config', 'pf2e_effects.yml')

    def tearDown(self):
        self.temp.cleanup()

    def test_describes_the_commit_and_version(self):
        held = foundry_source.describe(self.checkout)

        self.assertEqual(held['commit'], self.commit)
        self.assertEqual(held['version'], '8.6.1')
        self.assertFalse(held['dirty'])

    def test_a_file_inside_the_checkout_describes_it(self):
        held = foundry_source.describe(os.path.join(self.checkout, 'packs', 'one.json'))

        self.assertEqual(held['commit'], self.commit)

    def test_local_changes_to_what_is_read_are_noted(self):
        open(os.path.join(self.checkout, 'packs', 'one.json'), 'w', encoding='utf-8', newline='\n').write('{"changed": 1}')

        self.assertTrue(foundry_source.describe(self.checkout)['dirty'])

    def test_records_the_import_and_the_files_it_wrote(self):
        foundry_source.record(self.checkout, '/x/import_foundry_effects.py', [self.written], at=self.record)
        held = foundry_source.load(self.record)

        self.assertEqual(held['imports']['import_foundry_effects']['commit'], self.commit)
        self.assertEqual(held['files']['game/config/pf2e_effects.yml'],
                         {'by': 'import_foundry_effects', 'sha256': foundry_source.digest(self.written)})

    def test_a_record_is_a_single_root_key_like_every_config_file(self):
        foundry_source.record(self.checkout, 'import_foundry_effects.py', [self.written], at=self.record)

        import yaml
        self.assertEqual(list(yaml.safe_load(open(self.record, encoding='utf-8'))), ['pf2e_foundry_source'])

    def test_crlf_and_lf_hash_the_same(self):
        lf = os.path.join(self.temp.name, 'lf.yml')
        crlf = os.path.join(self.temp.name, 'crlf.yml')
        open(lf, 'wb').write(b'---\na: 1\nb: "x"\n')
        open(crlf, 'wb').write(b'---\r\na: 1\r\nb: "x"\r\n')

        self.assertEqual(foundry_source.digest(lf), foundry_source.digest(crlf))

    def test_removed_files_leave_the_record(self):
        foundry_source.record(self.checkout, 'import_foundry_effects.py', [self.written], at=self.record)
        foundry_source.record(self.checkout, 'import_foundry_effects.py', [], [self.written], at=self.record)

        self.assertEqual(foundry_source.load(self.record)['files'], {})

    def test_an_unrecorded_or_edited_whole_file_blocks_an_import(self):
        step = [{'whole': lambda: [self.written]}]
        held = foundry_source.load(self.record)

        self.assertEqual(import_foundry.edited(step, held),
                         [('game/config/pf2e_effects.yml', 'no import of it is recorded')])

        held['files']['game/config/pf2e_effects.yml'] = {'by': 'import_foundry_effects', 'sha256': '0' * 64}
        self.assertEqual(import_foundry.edited(step, held),
                         [('game/config/pf2e_effects.yml', 'changed since import_foundry_effects wrote it')])

        held['files']['game/config/pf2e_effects.yml']['sha256'] = foundry_source.digest(self.written)
        self.assertEqual(import_foundry.edited(step, held), [])


if __name__ == '__main__':
    unittest.main()
