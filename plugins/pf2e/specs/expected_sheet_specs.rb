require "plugin_test_loader"
require_relative "support/expected_sheet"

module AresMUSH
  module Pf2e

    # The expectation folded out of a class's own tables.
    #
    # Pure, so it runs in the unit suite against the shipped config with no climb. The climb
    # itself is checked against these expectations in level_twenty_audit_specs.rb.
    describe ExpectedSheet do

      describe "the shipped tables" do
        # If a class table grows a key this does not absorb, the audit would pass while checking
        # less than it claims to. That is the one failure mode worth failing the build for.
        it "should account for every key the class tables use" do
          expect(ExpectedSheet.unabsorbed).to eq []
        end
      end

      describe "a Fighter at 20" do
        def expected
          @expected ||= ExpectedSheet.for('Fighter', 20)
        end

        it "should expect the features the table names, by name" do
          expect(expected['features']).to include('Bravery', 'Battle Hardened', 'Combat Flexibility')
        end

        it "should expect the feat granted outright at chargen" do
          expect(expected['granted_feats']).to include('Shield Block')
        end

        it "should expect a class feat slot at every even level" do
          expect(expected['feat_slots']['charclass']).to include(2, 4, 6, 8, 10, 12, 14, 16, 18, 20)
        end

        it "should expect four attribute boosts after chargen" do
          expect(expected['boosts']).to eq 4
        end

        it "should expect the last proficiency rank the table sets, not the first" do
          # Will goes expert at 3 and the table raises it again later; the expectation has to hold
          # where it ended up.
          expect(%w(expert master legendary)).to include expected['saves']['will']
        end

        it "should expect the choices the table asks the player to make" do
          names = expected['choices'].map { |c| c['name'] }

          expect(names).to include 'Fighter Weapon Mastery'
        end

        it "should expect no spellcasting" do
          expect(expected['spells_per_day']).to eq({})
        end
      end

      describe "a Wizard at 20" do
        def expected
          @expected ||= ExpectedSheet.for('Wizard', 20)
        end

        it "should expect slots at every rank the table grants" do
          expect(expected['spells_per_day']['cantrip']).to eq 5
          expect(expected['spells_per_day']['1']).to be > 0
          expect(expected['spells_per_day']['10']).to be > 0
        end

        it "should pin the spellbook picks the table puts at a rank" do
          # Ten cantrips and five first-rank at chargen.
          expect(expected['known_picks']['cantrip']).to eq 10
          expect(expected['known_picks']['1']).to eq 5
        end

        it "should count the picks the player places wherever they like separately" do
          # Two a level from 2 to 20, which the table writes as `any`, so which rank each lands
          # at is the player's business and only the total is predictable.
          expect(expected['known_anywhere']).to be > 20
          expect(expected['known_picks']).to_not have_key 'any'
        end

        it "should expect the arcane bond and thesis by name" do
          expect(expected['features']).to include('Arcane Bond', 'Arcane Thesis')
        end
      end

      describe "a Rogue at 20" do
        def expected
          @expected ||= ExpectedSheet.for('Rogue', 20)
        end

        # The value the engine was dropping.
        it "should expect sneak attack dice" do
          expect(expected['sneak_attack']).to eq '4d6'
        end

        it "should expect the weapon proficiencies the level 5 block sets" do
          expect(expected['weapon_prof']['simple']).to_not be_nil
          expect(expected['weapon_prof']['unarmed']).to_not be_nil
        end
      end

      # The two keys the engine was dropping. They step trained -> expert at 13 -> master at 19,
      # so which rank is expected depends on the level, and a fold that took the first value
      # rather than the last would stop at expert.
      describe "an Alchemist's armour" do
        it "should be expert once level 13 is reached" do
          expected = ExpectedSheet.for('Alchemist', 13)

          expect(expected['armor_prof']['light']).to eq 'expert'
          expect(expected['armor_prof']['unarmored']).to eq 'expert'
        end

        it "should still be trained at 12" do
          expect(ExpectedSheet.for('Alchemist', 12)['armor_prof']['light']).to eq 'trained'
        end

        it "should be master by 20" do
          expect(ExpectedSheet.for('Alchemist', 20)['armor_prof']['light']).to eq 'master'
        end
      end

      describe "folding up to a level" do
        it "should ignore blocks above the level asked for" do
          at_two = ExpectedSheet.for('Fighter', 2)

          # Chargen's own class feat slot counts as level 1, then level 2's.
          expect(at_two['feat_slots']['charclass']).to eq [ 1, 2 ]
          expect(at_two['boosts']).to eq 0
        end

        it "should include chargen even at level 1" do
          at_one = ExpectedSheet.for('Fighter', 1)

          expect(at_one['granted_feats']).to include 'Shield Block'
          expect(at_one['feat_slots']['charclass']).to eq [ 1 ]
        end
      end

      # Finding 29: the Druid's chargen block writes two feat *names* into `choose_feat`, which
      # everywhere else holds slot *types*. Chargen only acts on 'charclass' and 'skill' entries,
      # so both are inert - they open no slot and grant nothing, and a Druid receives neither
      # feat. Whether the fix is a granted feat per order or a class feat slot is a rules question
      # for Raven, so this pins the defect rather than guessing: it fails if anything else drifts
      # into the same shape.
      describe "inert feat slots" do
        it "should be only the Druid's two, until finding 29 is settled" do
          expect(ExpectedSheet.inert_feat_slots).to eq(
            'Druid' => [ 'Animal Empathy', 'Plant Empathy' ]
          )
        end
      end

      # The specialty's own blocks shape the sheet too, so an expectation built from the class
      # alone reads a correct character as wrong - a Warpriest Cleric has expert fortitude and
      # martial weapons from the specialty, not from the class.
      describe "a specialty's own table" do
        it "should be folded in when one was chosen" do
          # A Warpriest has expert fortitude from level 1, where the class alone gives trained.
          plain = ExpectedSheet.for('Cleric', 1)
          warpriest = ExpectedSheet.for('Cleric', 1, :specialize => 'Warpriest')

          expect(plain['saves']['fortitude']).to eq 'trained'
          expect(warpriest['saves']['fortitude']).to eq 'expert'
        end

        # The Wizard's school states the whole spellbook total - 11 cantrips and 7 first-rank,
        # which is the class's 10 and 5 with the curriculum's 1 and 2 counted in - so summing the
        # two blocks would expect 21 and 12 and read a correct Wizard as fifteen spells short.
        it "should let a specialty's chargen spell total supersede the class's" do
          plain = ExpectedSheet.for('Wizard', 1)
          school = ExpectedSheet.for('Wizard', 1, :specialize => 'Department of Mana Syntaxia')

          expect(plain['known_picks']['cantrip']).to eq 10
          expect(school['known_picks']['cantrip']).to eq 11
          expect(school['known_picks']['1']).to eq 7
        end

        it "should still accumulate the picks advance blocks grant" do
          school = ExpectedSheet.for('Wizard', 5, :specialize => 'Department of Mana Syntaxia')

          # One curriculum spell at rank 2 from level 3 and one at rank 3 from level 5.
          expect(school['known_picks']['2']).to eq 1
          expect(school['known_picks']['3']).to eq 1
        end

        it "should bring the specialty's weapon proficiencies too" do
          warpriest = ExpectedSheet.for('Cleric', 20, :specialize => 'Warpriest')

          expect(warpriest['weapon_prof']['simple']).to_not be_nil
        end

        it "should bring the specialty's features with it" do
          cloistered = ExpectedSheet.for('Cleric', 20, :specialize => 'Cloistered')

          expect(cloistered['features'].any? { |f| f.start_with?('First Doctrine') }).to be true
        end
      end

      describe "a choice whose options are a hash" do
        it "should read the option names off the keys" do
          # The Champion's Blessing of the Devoted writes its options as a hash keyed by name.
          champion = ExpectedSheet.for('Champion', 20)
          blessing = champion['choices'].find { |c| c['name'] == 'Blessing of the Devoted' }

          expect(blessing['options']).to include('Blessed Armament', 'Blessed Shield', 'Blessed Swiftness')
        end
      end

      describe :apply_delta do
        it "should set a bare number" do
          expect(ExpectedSheet.apply_delta(3, 5)).to eq 5
        end

        it "should add a signed string, the way the engine does" do
          expect(ExpectedSheet.apply_delta(3, '+2')).to eq 5
          expect(ExpectedSheet.apply_delta(3, '-1')).to eq 2
        end
      end
    end
  end
end
