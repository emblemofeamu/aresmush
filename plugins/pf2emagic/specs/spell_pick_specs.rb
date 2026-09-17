require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Whether a spell may be added to a list at a rank.
    #
    # One place, so chargen and a level-up cannot enforce different subsets of the rules - which they
    # did: chargen checked the ranks and the spellbook's restricted entries, a level-up checked that
    # a signature spell was one the character knew, and neither checked the other's.
    describe SpellPick do

      def ctx(overrides = {})
        { 'list' => 'spellbook', 'rank' => '3', 'spell' => 'Fireball', 'tradition' => 'arcane',
          'details' => { 'tradition' => [ 'arcane' ], 'base_level' => 3 },
          'picks' => [ 'open' ], 'known' => {} }.merge(overrides)
      end

      it "should allow a spell the class casts at a rank it has" do
        expect(SpellPick.check(ctx)).to be_nil
      end

      describe "the tradition" do
        it "should refuse a spell with no tradition at all" do
          result = SpellPick.check(ctx('details' => { 'base_level' => 3 }))

          expect(result.code).to eq :no_tradition
        end

        it "should refuse a spell off another tradition's list" do
          result = SpellPick.check(ctx('details' => { 'tradition' => [ 'divine' ], 'base_level' => 3 }))

          expect(result.code).to eq :wrong_tradition
        end

        it "should allow one something adapted onto the list" do
          result = SpellPick.check(ctx('details' => { 'tradition' => [ 'divine' ], 'base_level' => 3 },
                                       'adapted' => true))

          expect(result).to be_nil
        end
      end

      describe "the rank" do
        it "should refuse a cantrip in a ranked slot" do
          result = SpellPick.check(ctx('details' => { 'tradition' => [ 'arcane' ], 'base_level' => 0 }))

          expect(result.code).to eq :cantrip_in_slot
        end

        it "should refuse a ranked spell in a cantrip slot" do
          result = SpellPick.check(ctx('rank' => 'cantrip'))

          expect(result.code).to eq :spell_in_cantrip
        end

        it "should refuse a spell written above the slot's rank" do
          result = SpellPick.check(ctx('rank' => '2'))

          expect(result.code).to eq :rank_too_low
        end

        # A 3rd-rank spell in a 5th-rank slot is heightened, which is allowed.
        it "should allow a spell below the slot's rank" do
          expect(SpellPick.check(ctx('rank' => '5'))).to be_nil
        end

        it "should allow a cantrip in a cantrip slot" do
          result = SpellPick.check(ctx('rank' => 'cantrip',
                                       'details' => { 'tradition' => [ 'arcane' ], 'base_level' => 0 }))

          expect(result).to be_nil
        end
      end

      describe "what they already have" do
        it "should refuse one picked earlier in the same sitting" do
          result = SpellPick.check(ctx('picks' => [ 'Fireball', 'open' ]))

          expect(result.code).to eq :already_picked
        end

        it "should refuse a spell already in the spellbook at any rank" do
          result = SpellPick.check(ctx('known' => { '5' => [ 'Fireball' ] }))

          expect(result.code).to eq :already_known
        end

        # A repertoire holds a spell per rank, so knowing Fireball at 3rd does not stop a Sorcerer
        # taking it again at 5th to cast it heightened.
        it "should allow a repertoire spell already known at another rank" do
          result = SpellPick.check(ctx('list' => 'repertoire', 'rank' => '5',
                                       'known' => { '3' => [ 'Fireball' ] }))

          expect(result).to be_nil
        end

        it "should refuse a repertoire spell already known at this rank" do
          result = SpellPick.check(ctx('list' => 'repertoire', 'known' => { '3' => [ 'Fireball' ] }))

          expect(result.code).to eq :already_known
        end
      end

      describe "a signature spell" do
        it "should have to be one they know at that rank" do
          result = SpellPick.check(ctx('list' => 'signature', 'known' => { '5' => [ 'Fireball' ] }))

          expect(result.code).to eq :signature_unknown
        end

        it "should be allowed when they know it" do
          result = SpellPick.check(ctx('list' => 'signature', 'known' => { '3' => [ 'Fireball' ] }))

          expect(result).to be_nil
        end
      end

      describe "a spellbook's restricted entries" do
        it "should refuse an addition that cannot be seated" do
          expect(SpellPick.check(ctx('fits' => false)).code).to eq :no_room
        end

        it "should allow one that can" do
          expect(SpellPick.check(ctx('fits' => true))).to be_nil
        end

        # A repertoire has no curriculum entry to satisfy.
        it "should not ask the question of a repertoire" do
          expect(SpellPick.check(ctx('list' => 'repertoire', 'fits' => false))).to be_nil
        end
      end

      describe "an innate spell" do
        def innate(overrides = {})
          { 'rank' => '3', 'granted_rank' => '3', 'tradition' => 'arcane',
            'details' => { 'tradition' => [ 'arcane' ], 'base_level' => 3 } }.merge(overrides)
        end

        it "should allow one the grant covers" do
          expect(SpellPick.check_innate(innate)).to be_nil
        end

        it "should refuse one off the grant's tradition" do
          result = SpellPick.check_innate(innate('details' => { 'tradition' => [ 'divine' ], 'base_level' => 3 }))

          expect(result.code).to eq :wrong_tradition
        end

        # The grant is for one rank, so the spell is taken at that rank and no other.
        it "should refuse a rank the grant does not cover" do
          expect(SpellPick.check_innate(innate('rank' => '5', 'granted_rank' => '3')).code).to eq :wrong_slot
        end

        it "should refuse a ranked spell against a cantrip grant" do
          expect(SpellPick.check_innate(innate('rank' => 'cantrip')).code).to eq :spell_in_cantrip
        end

        it "should allow a cantrip against a cantrip grant" do
          result = SpellPick.check_innate(innate('rank' => 'cantrip', 'granted_rank' => 'cantrip',
                                                 'details' => { 'tradition' => [ 'arcane' ], 'base_level' => 0 }))

          expect(result).to be_nil
        end
      end

      it "should have a locale entry for every rule it can refuse with" do
        locale = YAML.load_file(File.join(Pf2emagic.plugin_dir, 'locales', 'locale_en.yml'))['en']['pf2emagic']
        keys = File.read(File.join(Pf2emagic.plugin_dir, 'helpers', 'spell_pick.rb'))
                   .scan(/'pf2emagic\.([a-z_]+)'/).flatten.uniq

        expect(keys.reject { |key| locale.key?(key) }).to eq []
      end
    end
  end
end
