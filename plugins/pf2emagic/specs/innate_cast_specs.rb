require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Which innate grant a cast draws on.
    #
    # `innate_spells` is a list of grants, so one spell can be granted twice at different ranks and
    # traditions, and a cast has to choose between them.
    describe :innate_to_cast do

      def magic_with(grants)
        double(:innate_spells => grants)
      end

      it "should give the only grant of a spell" do
        magic = magic_with([ { 'name' => 'Bless', 'level' => 1, 'tradition' => 'divine' } ])

        expect(Entries.innate_to_cast(magic, 'Bless', {})['tradition']).to eq 'divine'
      end

      it "should give nothing for a spell that was never granted" do
        magic = magic_with([ { 'name' => 'Bless', 'level' => 1, 'tradition' => 'divine' } ])

        expect(Entries.innate_to_cast(magic, 'Haste', {})).to be_nil
      end

      it "should match the spell however it was capitalised" do
        magic = magic_with([ { 'name' => 'Bless', 'level' => 1, 'tradition' => 'divine' } ])

        expect(Entries.innate_to_cast(magic, 'bless', {})).to_not be_nil
      end

      # A cantrip is cast at will, so it never needs a use to be available.
      it "should prefer a cantrip grant, which costs nothing" do
        magic = magic_with([
          { 'name' => 'Charm', 'level' => 4, 'tradition' => 'divine' },
          { 'name' => 'Charm', 'level' => 'cantrip', 'tradition' => 'arcane' }
        ])

        expect(Entries.innate_to_cast(magic, 'Charm', {})['level']).to eq 'cantrip'
      end

      # Charm is granted twice in this game - rank 4 divine by Enthralling Allure and rank 1 arcane
      # by Supernatural Charm - so a cast picks the one with a use left.
      it "should pick the grant whose rank still has a use" do
        magic = magic_with([
          { 'name' => 'Charm', 'level' => 4, 'tradition' => 'divine' },
          { 'name' => 'Charm', 'level' => 1, 'tradition' => 'arcane' }
        ])

        used = { '1' => [ 'Charm' ] }

        expect(Entries.innate_to_cast(magic, 'Charm', used)['tradition']).to eq 'arcane'
      end

      it "should fall back to the first grant when none has a use left" do
        magic = magic_with([
          { 'name' => 'Charm', 'level' => 4, 'tradition' => 'divine' },
          { 'name' => 'Charm', 'level' => 1, 'tradition' => 'arcane' }
        ])

        # So the caller still reaches its own "no slots available" message rather than a nil.
        expect(Entries.innate_to_cast(magic, 'Charm', {})['tradition']).to eq 'divine'
      end
    end
  end
end
