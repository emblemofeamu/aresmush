require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Which spells a caster could actually take, per source and rank.
    #
    # Nothing answered this. A player picking spells guessed a name, was told the class had no
    # access to it or that the rank was wrong, and guessed again - a Wizard filling curriculum
    # slots did that at every level for twenty levels.
    describe :eligible_spells do

      def catalogue
        {
          'Force Barrage' => { 'base_level' => 1, 'tradition' => [ 'arcane', 'occult' ] },
          'Heal' => { 'base_level' => 1, 'tradition' => [ 'divine', 'primal' ] },
          'Fireball' => { 'base_level' => 3, 'tradition' => [ 'arcane', 'primal' ] },
          'Daze' => { 'base_level' => 'cantrip', 'tradition' => [ 'arcane', 'divine', 'occult' ] },
          'Sure Strike' => { 'base_level' => 1, 'tradition' => [] }
        }
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_spells').and_return(catalogue)
      end

      it "should offer a spell whose tradition the source casts" do
        expect(Pf2emagic.eligible_spells('arcane', 1)).to include 'Force Barrage'
      end

      it "should leave out a spell of another tradition" do
        expect(Pf2emagic.eligible_spells('arcane', 1)).to_not include 'Heal'
      end

      it "should leave out a spell written for a higher rank than the slot" do
        expect(Pf2emagic.eligible_spells('arcane', 1)).to_not include 'Fireball'
      end

      # A caster may always learn a lower-rank spell in a higher slot; that is heightening.
      it "should offer a lower-rank spell for a higher slot" do
        expect(Pf2emagic.eligible_spells('arcane', 3)).to include 'Force Barrage'
      end

      it "should keep cantrips out of a ranked slot" do
        expect(Pf2emagic.eligible_spells('arcane', 1)).to_not include 'Daze'
      end

      it "should offer only cantrips for a cantrip slot" do
        expect(Pf2emagic.eligible_spells('arcane', 'cantrip')).to eq [ 'Daze' ]
      end

      # A spell with no tradition at all cannot be matched against one, so it belongs to nobody.
      it "should leave out a spell with no tradition recorded" do
        expect(Pf2emagic.eligible_spells('arcane', 1)).to_not include 'Sure Strike'
      end

      it "should answer nothing for a tradition no spell uses" do
        expect(Pf2emagic.eligible_spells('elemental', 1)).to eq []
      end

      it "should ignore the case of the tradition" do
        expect(Pf2emagic.eligible_spells('ARCANE', 1)).to include 'Force Barrage'
      end

      it "should come back sorted, so the same question gives the same answer" do
        expect(Pf2emagic.eligible_spells('arcane', 3)).to eq [ 'Fireball', 'Force Barrage' ]
      end
    end
  end
end
