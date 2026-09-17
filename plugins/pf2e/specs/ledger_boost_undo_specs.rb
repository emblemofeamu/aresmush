require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Attribute boosts, undone and redone.
    #
    # PF2e gives four boosts at 5th, 10th, 15th and 20th level, each to a different attribute, and
    # a boost is worth 2 unless the score has reached 18, where it is worth 1 - the Remaster says
    # the same thing as a "partial boost" on a +4 modifier.
    #
    # The score is derived from the ledger's count and the scores chargen left, so rolling the level
    # back takes its four boosts with it.
    describe "attribute boosts in the ledger", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Boost#{rand(1000000)}")
      end

      after(:each) do
        @char.delete if @char
      end

      def scores(char)
        char.abilities.each_with_object({}) { |a, h| h[a.name] = a.base_val }
      end

      def boost_grants(char)
        char.grants.to_a.select { |g| g.kind == 'boost_ability' && g.reverted_by.blank? }
      end

      # Level 5 is the first level that hands out boosts, so a climb to 5 is the smallest case.
      def climbed
        builder = AutoBuilder.new(@char)
        builder.build_level_one('Barbarian')
        Pf2e::Ledger.commit_chargen!(Character[@char.id])

        @at_one = scores(Character[@char.id])

        builder.advance_to(5)
        Character[@char.id]
      end

      it "should record chargen's own boosts as grants at level 1" do
        char = climbed

        at_one = char.grants.to_a.select { |g| g.kind == 'boost_ability' && g.effective_level.to_i == 1 }

        expect(at_one).to_not be_empty
      end

      it "should derive every score from its flaws and boosts" do
        char = climbed

        flaws = char.grants.to_a.select { |g| g.kind == 'flaw_ability' }
                    .group_by { |g| g.payload['ability'] }.transform_values(&:size)
        boosts = char.grants.to_a.select { |g| g.kind == 'boost_ability' && g.reverted_by.blank? }
                     .group_by { |g| g.payload['ability'] }.transform_values(&:size)

        char.abilities.to_a.each do |ability|
          expect(ability.base_val).to eq(
            Pf2eAbilities.derived_score(flaws[ability.name].to_i, boosts[ability.name].to_i)
          ), ability.name
        end
      end

      it "should put the level 5 boosts in the ledger" do
        char = climbed

        taken = boost_grants(char).select { |g| g.effective_level.to_i == 5 }

        expect(taken.size).to eq 4
        expect(taken.map { |g| g.payload['ability'] }.uniq.size).to eq 4
      end

      # The score at 5 is the score at 1 with the levels between applied, by PF2e's own rule: +2,
      # or +1 once the score is 18. "went up" would pass for any increase at all.
      it "should raise the scores as PF2e says" do
        char = climbed

        since_one = boost_grants(char).select { |g| g.effective_level.to_i > 1 }
                                      .group_by { |g| g.payload['ability'] }.transform_values(&:size)

        expect(since_one).to_not be_empty

        @at_one.each_pair do |ability, was|
          expect(scores(char)[ability]).to eq(
            Pf2eAbilities.boosted_score(was, since_one[ability].to_i)
          ), ability
        end
      end

      it "should take the boosts back when the level is rolled back" do
        char = climbed
        before_rollback = scores(char)

        # rollback_to_level undoes that level and everything above it, so 5 is the level whose
        # boosts are being taken back.
        expect(Pf2e.rollback_to_level(char, 5)).to be_nil

        char = Character[@char.id]

        expect(char.pf2_level).to eq 4

        # Chargen's boosts are grants at level 1 and a rollback does not reach them, so what has to
        # be gone is everything the level handed out.
        above_one = boost_grants(char).select { |g| g.effective_level.to_i > 1 }

        expect(above_one).to be_empty
        expect(boost_grants(char)).to_not be_empty
        expect(scores(char)).to eq @at_one
        expect(scores(char)).to_not eq before_rollback
      end

      it "should give them back exactly once on a redo" do
        char = climbed
        before_rollback = scores(char)

        Pf2e.rollback_to_level(char, 5)
        expect(Pf2e.redo_rollback(Character[@char.id])).to be_nil

        char = Character[@char.id]

        expect(char.pf2_level).to eq 5
        expect(scores(char)).to eq before_rollback
        expect(boost_grants(char).count { |g| g.effective_level.to_i == 5 }).to eq 4
      end

      # A partial boost in Remaster terms: a score at 18 goes to 19, which is still a +4 modifier,
      # and only the next boost moves it to +5.
      it "should give only one point to a score that has reached 18" do
        expect(Pf2eAbilities.boosted_score(18, 1)).to eq 19
        expect(Pf2eAbilities.abilmod(18)).to eq 4
        expect(Pf2eAbilities.abilmod(19)).to eq 4
        expect(Pf2eAbilities.abilmod(20)).to eq 5
      end
    end
  end
end
