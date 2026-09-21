require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # What chargen says when a feat has handed the character an innate spell to choose.
    #
    # It said only "You have innate spell(s) to choose." The rank and tradition were a section
    # further down cg/review, and the command was in a help file. Three players in a row read the
    # prompt, guessed `addspell innate/1 = <a first-rank spell>` against a slot that wanted an
    # arcane cantrip, were refused, and never got the spell their ancestry feat granted.
    describe :innate_prompt do

      def grant(rank, tradition)
        { 'name' => 'open', 'level' => rank, 'tradition' => tradition }
      end

      it "should name the rank the slot wants" do
        expect(Pf2emagic.innate_prompt([ grant('cantrip', 'arcane') ])).to include 'cantrip'
      end

      it "should name the tradition the slot draws on" do
        expect(Pf2emagic.innate_prompt([ grant('cantrip', 'arcane') ])).to include 'arcane'
      end

      it "should name the command that fills it, with the rank already in place" do
        expect(Pf2emagic.innate_prompt([ grant('cantrip', 'arcane') ])).to include 'addspell innate/cantrip'
      end

      it "should use a ranked slot's own rank in the command, not a cantrip's" do
        prompt = Pf2emagic.innate_prompt([ grant(3, 'divine') ])

        expect(prompt).to include 'addspell innate/3'
        expect(prompt).to include 'divine'
      end

      it "should describe every open slot when a character has more than one" do
        prompt = Pf2emagic.innate_prompt([ grant('cantrip', 'arcane'), grant(2, 'occult') ])

        expect(prompt).to include 'arcane'
        expect(prompt).to include 'occult'
      end

      it "should say nothing when there is nothing to choose" do
        expect(Pf2emagic.innate_prompt([])).to be_nil
      end

      # A grant with no tradition recorded still has a rank worth naming, and the player still
      # needs the command; a prompt that renders half a sentence is worse than the old one.
      it "should still name the command when a grant records no tradition" do
        prompt = Pf2emagic.innate_prompt([ { 'name' => 'open', 'level' => 'cantrip' } ])

        expect(prompt).to include 'addspell innate/cantrip'
        expect(prompt).to_not include '%{'
      end
    end
  end
end
