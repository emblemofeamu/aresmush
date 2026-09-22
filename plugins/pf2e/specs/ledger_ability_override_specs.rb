require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Staff setting an ability score outright.
    #
    # Scores derive from counts of boosts and flaws, and most scores a character can reach are
    # derivable that way. A staff correction need not be: 15 is not a number any sequence of boosts
    # from 10 produces. So an absolute score is its own grant, and the fold prefers it over the
    # derivation for that ability.
    describe "an ability score set outright" do

      def grant(kind, payload, level = 1, source = 'staff', seq = 1)
        { 'kind' => kind, 'payload' => payload, 'effective_level' => level, 'reverted_by' => nil,
          'source_type' => source, 'seq' => seq }
      end

      def plan_for(grants, held)
        sheet = Ledger.fold(grants, :at_level => 5)
        current = { 'ability_scores' => held, 'boosts' => {}, 'level' => 5 }

        Ledger.plan(sheet, current)
      end

      it "should fold an absolute score" do
        sheet = Ledger.fold([ grant('set_ability_score', 'ability' => 'Strength', 'to' => 15) ], :at_level => 5)

        expect(sheet['ability_overrides']).to eq('Strength' => 15)
      end

      it "should keep the score staff set rather than deriving it" do
        ops = plan_for([ grant('set_ability_score', 'ability' => 'Strength', 'to' => 15) ], 'Strength' => 15)

        expect(ops.select { |o| o['op'] == 'set_ability' }).to eq []
      end

      it "should put the score back when something else has moved it" do
        ops = plan_for([ grant('set_ability_score', 'ability' => 'Strength', 'to' => 15) ], 'Strength' => 10)

        expect(ops).to include('op' => 'set_ability', 'ability' => 'Strength', 'to' => 15)
      end

      it "should take the latest of two corrections" do
        grants = [ grant('set_ability_score', { 'ability' => 'Strength', 'to' => 15 }),
                   grant('set_ability_score', { 'ability' => 'Strength', 'to' => 17 }) ]

        expect(Ledger.fold(grants, :at_level => 5)['ability_overrides']).to eq('Strength' => 17)
      end

      it "should leave the other abilities deriving as usual" do
        grants = [ grant('set_ability_score', { 'ability' => 'Strength', 'to' => 15 }),
                   grant('boost_ability', { 'ability' => 'Wisdom' }) ]

        ops = plan_for(grants, 'Strength' => 15, 'Wisdom' => 10)

        expect(ops).to include('op' => 'set_ability', 'ability' => 'Wisdom', 'to' => 12)
        expect(ops.select { |o| o['ability'] == 'Strength' }).to eq []
      end

      # Without the override the derivation wins, which is what makes a direct write to base_val
      # disappear on the next materialise.
      it "should overwrite a score nothing in the ledger accounts for" do
        ops = plan_for([], 'Strength' => 15)

        expect(ops).to include('op' => 'set_ability', 'ability' => 'Strength', 'to' => 10)
      end

      # A correction is a new starting point, not a ceiling: PF2e still lets the character boost
      # that attribute at 5th level and beyond, and those boosts apply on top of what staff set.
      it "should let a later boost raise the score staff set" do
        grants = [ grant('set_ability_score', { 'ability' => 'Strength', 'to' => 15 }, 1, 'staff', 1),
                   grant('boost_ability', { 'ability' => 'Strength' }, 5, 'level_up', 2) ]
        ops = plan_for(grants, 'Strength' => 15)

        expect(ops.find { |o| o['op'] == 'set_ability' }['to']).to eq 17
      end

      # The boosts before it are what the correction is replacing, so they do not apply twice.
      it "should ignore the boosts a correction supersedes" do
        grants = [ grant('boost_ability', { 'ability' => 'Strength' }, 1, 'chargen', 1),
                   grant('boost_ability', { 'ability' => 'Strength' }, 1, 'chargen', 2),
                   grant('set_ability_score', { 'ability' => 'Strength', 'to' => 15 }, 1, 'staff', 3) ]
        ops = plan_for(grants, 'Strength' => 15)

        expect(ops.select { |o| o['op'] == 'set_ability' }).to eq []
      end

      it "should leave another attribute deriving as usual" do
        grants = [ grant('set_ability_score', { 'ability' => 'Strength', 'to' => 15 }, 1, 'staff', 1),
                   grant('boost_ability', { 'ability' => 'Dexterity' }, 1, 'chargen', 2) ]
        ops = plan_for(grants, 'Strength' => 15, 'Dexterity' => 12)

        expect(ops.select { |o| o['op'] == 'set_ability' }).to eq []
      end
    end
  end
end
