require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Chargen

      # The four small records a character owns outright.
      #
      # A roll shorthand, who they have shown a sheet section to, the notes staff keep on them, and
      # what they are known for. Four commands were each doing the same list-or-map edit by hand,
      # against four attributes nothing else could see.
      describe Records do

        def state(overrides = {})
          CharState.build({ 'name' => 'Tester' }.merge(overrides), :config => ConfigView.fixture({}))
        end

        describe "a roll shorthand" do
          it "should name a value" do
            result = Records.set(state, 'record' => 'alias', 'key' => 'str', 'value' => 'Strength')

            expect(result.state['roll_aliases']).to eq('str' => 'Strength')
            expect(result.messages.first['key']).to eq 'pf2e.alias_set_ok'
          end

          it "should take one away" do
            result = Records.unset(state('roll_aliases' => { 'str' => 'Strength' }), 'record' => 'alias', 'key' => 'str')

            expect(result.state['roll_aliases']).to eq({})
          end

          it "should refuse to take away one that is not there" do
            expect(Records.unset(state, 'record' => 'alias', 'key' => 'str').code).to eq :not_in_list
          end
        end

        describe "a staff note" do
          it "should say when it replaced one, out of character" do
            result = Records.set(state('cnotes' => { 'history' => 'old' }),
                                 'record' => 'cnote', 'key' => 'history', 'value' => 'new')

            expect(result.state['cnotes']).to eq('history' => 'new')
            expect(result.messages.map { |m| m['type'] }).to include 'ooc'
          end

          # A note is removed by a loosely typed name, so the name has to pick out exactly one.
          it "should match a name case-insensitively" do
            result = Records.unset(state('cnotes' => { 'History' => 'a note' }),
                                   'record' => 'cnote', 'key' => 'history')

            expect(result.state['cnotes']).to eq({})
          end

          it "should refuse a name that matches more than one note" do
            result = Records.unset(state('cnotes' => { 'History' => 'a', 'history' => 'b' }),
                                   'record' => 'cnote', 'key' => 'history')

            expect(result.code).to eq :not_unique
          end
        end

        describe "showing a sheet section" do
          it "should add the player to that section" do
            result = Records.add(state, 'record' => 'viewsheet', 'key' => 'combat', 'value' => 'Bob')

            expect(result.state['viewsheet']).to eq('combat' => [ 'Bob' ])
          end

          it "should leave it alone when they can already see it" do
            before = state('viewsheet' => { 'combat' => [ 'Bob' ] })
            result = Records.add(before, 'record' => 'viewsheet', 'key' => 'combat', 'value' => 'bob')

            expect(result.state['viewsheet']).to eq('combat' => [ 'Bob' ])
            expect(result.messages.first['key']).to eq 'pf2e.player_added'
          end
        end

        describe "what they are known for" do
          it "should append to the list" do
            result = Records.add(state('known_for' => [ 'a duel' ]), 'record' => 'known_for', 'value' => 'a song')

            expect(result.state['known_for']).to eq [ 'a duel', 'a song' ]
          end
        end

        describe "a record that does not do that" do
          it "should refuse an operation it has no row for" do
            expect(Records.unset(state, 'record' => 'known_for', 'key' => 'a duel').code).to eq :unknown_record
          end

          it "should refuse a record it has never heard of" do
            expect(Records.set(state, 'record' => 'nonsense', 'key' => 'x', 'value' => 'y').code).to eq :unknown_record
          end
        end

        it "should have a locale entry for every message it can send" do
          locale = YAML.load_file(File.join(Pf2e.plugin_dir, 'locales', 'locale_en.yml'))['en']['pf2e']
          keys = Records::RECORDS.values.flat_map { |row| row.values.grep(/\Apf2e\./) }.uniq

          expect(keys.reject { |key| locale.key?(key.sub('pf2e.', '')) }).to eq []
        end
      end
    end
  end
end
