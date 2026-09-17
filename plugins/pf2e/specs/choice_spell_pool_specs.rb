require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The pool of spells a feat's choice offers, minus the ones the character already holds.
    #
    # Focus spells are not an attribute of PF2Magic - they are entries, read through
    # Pf2emagic::Entries - so asking the model for them raises. A verifying double is what keeps
    # that honest: it only answers methods the real class has.
    describe :choice_spell_pool do

      def catalogue
        {
          'Inner Upheaval' => { 'base_level' => 'cantrip', 'traits' => [ 'monk', 'focus', 'concentrate' ] },
          'Wholeness of Body' => { 'base_level' => 1, 'traits' => [ 'monk', 'focus', 'healing' ] },
          'Fireball' => { 'base_level' => 3, 'traits' => [ 'arcane', 'fire' ] }
        }
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_spells').and_return(catalogue)
      end

      # instance_double raises if PF2Magic has no such method, so a reader that has drifted from
      # the model fails here rather than in front of a player.
      def char_with_focus(held)
        magic = instance_double(AresMUSH::PF2Magic)
        allow(Pf2emagic::Entries).to receive(:focus_spells).with(magic, 'qi').and_return(held)

        double(:name => 'Someone', :magic => magic)
      end

      it "should offer the focus spells a trait filter names" do
        pool = Pf2e.choice_spell_pool(char_with_focus([]), 'traits' => [ 'monk', 'focus' ], 'focus_type' => 'qi')

        expect(pool).to eq [ 'Inner Upheaval', 'Wholeness of Body' ]
      end

      it "should leave out a spell the character already holds" do
        pool = Pf2e.choice_spell_pool(char_with_focus([ 'Inner Upheaval' ]), 'traits' => [ 'monk', 'focus' ], 'focus_type' => 'qi')

        expect(pool).to eq [ 'Wholeness of Body' ]
      end

      it "should answer for a character with no magic at all" do
        pool = Pf2e.choice_spell_pool(double(:name => 'Someone', :magic => nil),
                                      'traits' => [ 'monk', 'focus' ], 'focus_type' => 'qi')

        expect(pool).to eq [ 'Inner Upheaval', 'Wholeness of Body' ]
      end
    end
  end
end
