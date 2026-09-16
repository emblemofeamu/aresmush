require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Whether one more spell fits in a prepared caster's spellbook at a rank.
    #
    # The same assignment problem as preparing spells into slots, one lifetime earlier: a
    # Wizard's spellbook has a curriculum entry that only a school spell may occupy, so counting
    # the spells is not enough - it matters which of them can sit in the restricted place.
    describe :spellbook_addition_fits? do

      def char(restricted, held)
        magic = double(:restricted_spellbook => { 'Wizard' => restricted },
                       :spellbook => { 'Wizard' => { '2' => held } })

        double(:magic => magic, :name => 'Someone', :pf2_base_info => { 'specialize' => 'Battle Magic' })
      end

      before(:each) do
        allow(Pf2emagic).to receive(:pending_spellbook_picks).and_return(0)
        allow(Pf2emagic).to receive(:curriculum_spells).and_return([ 'Fireball' ])
      end

      it "should let anything in when nothing is restricted" do
        expect(Pf2emagic.spellbook_addition_fits?(char({}, [ 'Bless' ]), 'Wizard', '2', 'Haste')).to be true
      end

      it "should let the curriculum spell into the curriculum entry" do
        allow(Pf2emagic).to receive(:pending_spellbook_picks).and_return(1)
        subject = char({ 'curriculum' => { '2' => 1 } }, [])

        expect(Pf2emagic.spellbook_addition_fits?(subject, 'Wizard', '2', 'Fireball')).to be true
      end

      # One entry at this rank and it is the curriculum's, so a spell off the school list has
      # nowhere to go.
      it "should refuse a spell that cannot occupy the only entry left" do
        allow(Pf2emagic).to receive(:pending_spellbook_picks).and_return(1)
        subject = char({ 'curriculum' => { '2' => 1 } }, [])

        expect(Pf2emagic.spellbook_addition_fits?(subject, 'Wizard', '2', 'Haste')).to be false
      end

      it "should let a free entry take a spell the curriculum would not" do
        allow(Pf2emagic).to receive(:pending_spellbook_picks).and_return(2)
        subject = char({ 'curriculum' => { '2' => 1 } }, [ 'Fireball' ])

        expect(Pf2emagic.spellbook_addition_fits?(subject, 'Wizard', '2', 'Haste')).to be true
      end

      it "should count a replaced spell as gone" do
        subject = char({ 'curriculum' => { '2' => 1 } }, [ 'Haste' ])
        # One entry at this rank, currently holding a spell the curriculum would not accept.

        expect(Pf2emagic.spellbook_addition_fits?(subject, 'Wizard', '2', 'Fireball', 'Haste')).to be true
      end

      # Two reserved entries at one rank: both are enforced, and a spell neither accepts does not
      # fit.
      it "should enforce every restriction, not only the first" do
        allow(Pf2emagic).to receive(:pending_spellbook_picks).and_return(2)
        subject = char({ 'curriculum' => { '2' => 1 }, 'moon phase' => { '2' => 1 } }, [])

        # Two entries, both restricted: the curriculum's takes Fireball, and 'moon phase' is a
        # restriction nothing here understands, so it accepts nothing.
        expect(Pf2emagic.spellbook_addition_fits?(subject, 'Wizard', '2', 'Fireball')).to be true
        expect(Pf2emagic.spellbook_addition_fits?(subject, 'Wizard', '2', 'Haste')).to be false
      end
    end
  end
end
