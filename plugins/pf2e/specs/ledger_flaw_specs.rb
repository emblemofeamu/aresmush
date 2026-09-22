require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An ancestry's ability flaw, in the fold.
    #
    # A score is derived from 10 by applying flaws and then boosts, so the fold has to hold both.
    # Flaws are counted separately from boosts rather than folded in as negative boosts, because the
    # two are worth different amounts at the 18 threshold and the order they apply in matters.
    describe "folding an ability flaw" do

      def grant(kind, payload, level = 1)
        { 'kind' => kind, 'payload' => payload, 'effective_level' => level, 'reverted_by' => nil,
          'source_type' => 'chargen', 'seq' => 1 }
      end

      it "should count a flaw against its ability" do
        sheet = Ledger.fold([ grant('flaw_ability', 'ability' => 'Strength') ], :at_level => 1)

        expect(sheet['flaws']).to eq('Strength' => 1)
      end

      it "should keep flaws apart from boosts" do
        sheet = Ledger.fold([
          grant('flaw_ability', 'ability' => 'Strength'),
          grant('boost_ability', 'ability' => 'Dexterity')
        ], :at_level => 1)

        expect(sheet['flaws']).to eq('Strength' => 1)
        expect(sheet['boosts']).to eq('Dexterity' => 1)
      end

      it "should count two flaws on one ability" do
        sheet = Ledger.fold([
          grant('flaw_ability', 'ability' => 'Strength'),
          grant('flaw_ability', 'ability' => 'Strength')
        ], :at_level => 1)

        expect(sheet['flaws']).to eq('Strength' => 2)
      end

      it "should report no flaws for a character with none" do
        expect(Ledger.fold([], :at_level => 1)['flaws']).to eq({})
      end

      # A flaw is chargen's, so it applies at every level and a rollback does not reach it.
      it "should still apply at a later level" do
        sheet = Ledger.fold([ grant('flaw_ability', { 'ability' => 'Strength' }, 1) ], :at_level => 12)

        expect(sheet['flaws']).to eq('Strength' => 1)
      end

      describe "deriving the scores" do
        def plan_for(sheet_grants, held_scores)
          sheet = Ledger.fold(sheet_grants, :at_level => 1)
          current = { 'ability_scores' => held_scores, 'boosts' => {}, 'level' => 1 }

          Ledger.plan(sheet, current)
        end

        it "should set a boosted ability to what its boosts make of 10" do
          ops = plan_for([ grant('boost_ability', 'ability' => 'Strength') ], 'Strength' => 10)

          expect(ops).to include('op' => 'set_ability', 'ability' => 'Strength', 'to' => 12)
        end

        it "should set a flawed ability below 10" do
          ops = plan_for([ grant('flaw_ability', 'ability' => 'Strength') ], 'Strength' => 10)

          expect(ops).to include('op' => 'set_ability', 'ability' => 'Strength', 'to' => 8)
        end

        it "should apply the flaw before the boosts" do
          grants = [ grant('flaw_ability', 'ability' => 'Strength') ] +
                   Array.new(4) { grant('boost_ability', 'ability' => 'Strength') }

          ops = plan_for(grants, 'Strength' => 10)

          expect(ops).to include('op' => 'set_ability', 'ability' => 'Strength', 'to' => 16)
        end

        it "should leave an ability already at its derived score alone" do
          ops = plan_for([ grant('boost_ability', 'ability' => 'Strength') ], 'Strength' => 12)

          expect(ops.select { |o| o['op'] == 'set_ability' }).to eq []
        end

        it "should set an untouched ability to 10" do
          ops = plan_for([], 'Wisdom' => 14)

          expect(ops).to include('op' => 'set_ability', 'ability' => 'Wisdom', 'to' => 10)
        end
      end
    end
  end
end
