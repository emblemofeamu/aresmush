require "plugin_test_loader"

module AresMUSH

  # Applying attribute boosts to a score.
  #
  # PF2e: a boost raises a score by 2, or by 1 once it is 18 or higher. The rule depends only on the
  # score being boosted. A count per ability therefore derives the result, with no ordering between
  # abilities to preserve, and that is what makes boosts foldable.
  describe Pf2eAbilities do

    describe :boosted_score do
      it "should raise a low score by two" do
        expect(Pf2eAbilities.boosted_score(10, 1)).to eq 12
      end

      it "should raise by two repeatedly up to 18" do
        expect(Pf2eAbilities.boosted_score(10, 4)).to eq 18
      end

      it "should raise by one at 18 and above" do
        expect(Pf2eAbilities.boosted_score(18, 1)).to eq 19
        expect(Pf2eAbilities.boosted_score(19, 1)).to eq 20
      end

      it "should switch from two to one part way through" do
        # 16 -> 18 -> 19: the second boost is worth one, not two.
        expect(Pf2eAbilities.boosted_score(16, 2)).to eq 19
      end

      it "should leave a score alone for no boosts" do
        expect(Pf2eAbilities.boosted_score(14, 0)).to eq 14
      end

      it "should be the same as applying them one at a time" do
        # Folding a count is only sound if it agrees with the incremental writer.
        (10..20).each do |base|
          (0..6).each do |count|
            one_at_a_time = count.times.reduce(base) { |score, _| score < 18 ? score + 2 : score + 1 }

            expect(Pf2eAbilities.boosted_score(base, count)).to eq(one_at_a_time),
              "base #{base} with #{count} boosts"
          end
        end
      end

      it "should treat a negative count as no boosts" do
        expect(Pf2eAbilities.boosted_score(12, -1)).to eq 12
      end
    end
    # A score built from nothing but its counts, which is what lets the grant ledger own it.
    describe :derived_score do
      it "should start every ability at 10" do
        expect(Pf2eAbilities.derived_score(0, 0)).to eq 10
      end

      it "should apply boosts from 10" do
        expect(Pf2eAbilities.derived_score(0, 4)).to eq 18
      end

      it "should apply a flaw from 10" do
        expect(Pf2eAbilities.derived_score(1, 0)).to eq 8
      end

      # A flawed ability climbs from 8, so it lands two behind an unflawed one.
      it "should apply the flaw before the boosts" do
        expect(Pf2eAbilities.derived_score(1, 4)).to eq 16
        expect(Pf2eAbilities.derived_score(0, 4)).to eq 18
      end

      # Chargen's four categories plus a level-up's boosts can put several on one ability.
      it "should carry a long run of boosts through the 18 threshold" do
        expect(Pf2eAbilities.derived_score(0, 5)).to eq 19
        expect(Pf2eAbilities.derived_score(0, 6)).to eq 20
      end

      # Order is stated rather than left to chance. From a base of 10 the two orders agree for every
      # reachable count, and they part company from 17, which no sequence of boosts from 10 reaches.
      it "should agree with applying the boosts first, from a base of 10" do
        (0..8).each do |boosts|
          (0..2).each do |flaws|
            other = boosts.times.reduce(Pf2eAbilities.flawed_score(10, flaws)) { |s, _| Pf2eAbilities.boosted_score(s, 1) }

            expect(Pf2eAbilities.derived_score(flaws, boosts)).to eq(other),
              "#{boosts} boosts and #{flaws} flaws"
          end
        end
      end
    end

    describe :flawed_score do
      it "should take two off a score below 18" do
        expect(Pf2eAbilities.flawed_score(12, 1)).to eq 10
      end

      # The inverse of a boost: a boost at 18 is worth one, so a flaw from 19 is worth one.
      it "should take one off a score above 18" do
        expect(Pf2eAbilities.flawed_score(19, 1)).to eq 18
      end

      it "should take two off at exactly 18" do
        expect(Pf2eAbilities.flawed_score(18, 1)).to eq 16
      end

      it "should leave a score alone for no flaws" do
        expect(Pf2eAbilities.flawed_score(14, 0)).to eq 14
      end
    end
  end
end
