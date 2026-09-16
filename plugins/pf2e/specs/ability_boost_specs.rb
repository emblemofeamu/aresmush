require "plugin_test_loader"

module AresMUSH

  # Applying attribute boosts to a score.
  #
  # PF2e: a boost raises a score by 2, or by 1 once it is 18 or higher. The rule depends only on the
  # score being boosted, so a count per ability derives the result and no ordering between abilities
  # has to be preserved - which is what makes boosts foldable.
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
  end
end
