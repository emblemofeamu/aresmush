require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Describing what a feat's magic grants left for the player to choose.
    #
    # `innate_spells` is a list of grants, not a map keyed by spell name, because two sources can
    # grant one spell at different ranks and traditions. Reached by resolving a feat choice that
    # grants magic - a Champion picking their Devotion Spell at chargen.
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

      # Two unchosen grants are two picks; keyed by name they would be one.
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
