require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Describing what a feat's magic grants left for the player to choose.
    #
    # `do_feat_grants` read `magic.innate_spells` as a map keyed by spell name and called `.values`
    # on the result. That attribute is a *list* of grants now - reshaped because two sources of one
    # spell collided when it was keyed by name - so the read raised NoMethodError on Array.
    #
    # Nothing caught it because the only path that reaches it is resolving a feat choice that
    # grants magic, and the spec harness resolved chargen choices with `advance/option`, which the
    # `check_advancing` guard refuses. A Champion picking their Devotion Spell at chargen hits it.
    describe :open_innate_labels do

      def magic_with(grants)
        double(:innate_spells => grants)
      end

      it "should describe an unchosen cantrip" do
        magic = magic_with([ { 'name' => 'open', 'level' => 'cantrip', 'tradition' => 'divine' } ])

        expect(Pf2e.open_innate_labels(magic)).to eq [ 'innate cantrip (divine)' ]
      end

      it "should describe an unchosen ranked spell" do
        magic = magic_with([ { 'name' => 'open', 'level' => 2, 'tradition' => 'occult' } ])

        expect(Pf2e.open_innate_labels(magic)).to eq [ 'innate 2nd-rank spell (occult)' ]
      end

      it "should ignore spells that have been chosen" do
        magic = magic_with([
          { 'name' => 'Bless', 'level' => 1, 'tradition' => 'divine' },
          { 'name' => 'open', 'level' => 1, 'tradition' => 'divine' }
        ])

        expect(Pf2e.open_innate_labels(magic).size).to eq 1
      end

      # The collision the list shape exists to prevent: two unchosen grants are two picks, and
      # keyed by name they were one.
      it "should keep two unchosen grants apart" do
        magic = magic_with([
          { 'name' => 'open', 'level' => 'cantrip', 'tradition' => 'arcane' },
          { 'name' => 'open', 'level' => 'cantrip', 'tradition' => 'divine' }
        ])

        expect(Pf2e.open_innate_labels(magic).sort)
          .to eq [ 'innate cantrip (arcane)', 'innate cantrip (divine)' ]
      end

      it "should say so when a grant names no tradition" do
        magic = magic_with([ { 'name' => 'open', 'level' => 'cantrip' } ])

        expect(Pf2e.open_innate_labels(magic)).to eq [ 'innate cantrip (unknown tradition)' ]
      end

      it "should give nothing for a character with no magic" do
        expect(Pf2e.open_innate_labels(nil)).to eq []
      end

      it "should give nothing when no grant is unchosen" do
        magic = magic_with([ { 'name' => 'Bless', 'level' => 1, 'tradition' => 'divine' } ])

        expect(Pf2e.open_innate_labels(magic)).to eq []
      end
    end
  end
end
