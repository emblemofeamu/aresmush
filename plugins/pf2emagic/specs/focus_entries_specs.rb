require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Focus spells as spellcasting entries, one per focus type per granting source.
    #
    # PF2e shares a single focus pool across every source a character has, but casts each
    # source's spells at that source's own DC. A bucket keyed by focus type could hold the spells
    # but not say whose they were, so two sources of one type had nowhere to go.
    describe "focus spell entries", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Foc#{rand(1000000)}")
        @magic = PF2Magic.get_create_magic_obj(@char)
      end

      after(:each) do
        @char.delete if @char
      end

      def reload
        @magic = PF2Magic[@magic.id]
      end

      it "should record a focus spell for its type" do
        Entries.grant_focus!(@char, 'devotion', [ 'Lay on Hands' ], :kind => 'spell', :granted_by => 'Champion')
        reload

        expect(Entries.focus_spells(@magic, 'devotion')).to eq [ 'Lay on Hands' ]
        expect(Entries.focus_types(@magic)).to eq [ 'devotion' ]
      end

      it "should keep cantrips and spells apart within one entry" do
        Entries.grant_focus!(@char, 'devotion', [ 'Lay on Hands' ], :kind => 'spell', :granted_by => 'Champion')
        Entries.grant_focus!(@char, 'devotion', [ 'Shields of the Spirit' ], :kind => 'cantrip', :granted_by => 'Champion')
        reload

        expect(Entries.focus_spells(@magic, 'devotion')).to eq [ 'Lay on Hands' ]
        expect(Entries.focus_cantrips(@magic, 'devotion')).to eq [ 'Shields of the Spirit' ]
        expect(Entries.focus_entries(@magic, 'devotion').size).to eq 1
      end

      it "should add to a source's list rather than replacing it" do
        Entries.grant_focus!(@char, 'devotion', [ 'Lay on Hands' ], :kind => 'spell', :granted_by => 'Champion')
        Entries.grant_focus!(@char, 'devotion', [ "Champion's Sacrifice" ], :kind => 'spell', :granted_by => 'Champion')
        reload

        expect(Entries.focus_spells(@magic, 'devotion').sort).to eq [ "Champion's Sacrifice", 'Lay on Hands' ]
      end

      it "should not record the same spell twice" do
        2.times { Entries.grant_focus!(@char, 'devotion', [ 'Lay on Hands' ], :kind => 'spell', :granted_by => 'Champion') }
        reload

        expect(Entries.focus_spells(@magic, 'devotion')).to eq [ 'Lay on Hands' ]
      end

      # The case the old shape could not hold at all.
      describe "two sources of one focus type" do
        before(:each) do
          Entries.grant_focus!(@char, 'devotion', [ 'Lay on Hands' ], :kind => 'spell', :granted_by => 'Champion')
          Entries.grant_focus!(@char, 'devotion', [ 'Touch of the Void' ], :kind => 'spell', :granted_by => 'Champion Archetype')
          reload
        end

        it "should keep them as separate entries" do
          entries = Entries.focus_entries(@magic, 'devotion')

          expect(entries.size).to eq 2
          expect(entries.map { |e| e['granted_by'] }.sort).to eq [ 'Champion', 'Champion Archetype' ]
        end

        it "should still cast from the merged list, because the pool is shared" do
          expect(Entries.focus_spells(@magic, 'devotion').sort).to eq [ 'Lay on Hands', 'Touch of the Void' ]
        end

        it "should say which source each spell came from" do
          archetype = Entries.focus_entries(@magic, 'devotion').find { |e| e['granted_by'] == 'Champion Archetype' }

          expect(archetype['known']['spell']).to eq [ 'Touch of the Void' ]
        end
      end

      it "should keep different focus types apart" do
        Entries.grant_focus!(@char, 'devotion', [ 'Lay on Hands' ], :kind => 'spell', :granted_by => 'Champion')
        Entries.grant_focus!(@char, 'revelation', [ 'Whispers of Weakness' ], :kind => 'spell', :granted_by => 'Oracle')
        reload

        expect(Entries.focus_types(@magic).sort).to eq [ 'devotion', 'revelation' ]
        expect(Entries.focus_spells(@magic, 'devotion')).to eq [ 'Lay on Hands' ]
      end

      describe :revoke_focus! do
        it "should take a spell away" do
          Entries.grant_focus!(@char, 'devotion', [ 'Lay on Hands', 'Touch of the Void' ], :kind => 'spell', :granted_by => 'Champion')
          Entries.revoke_focus!(@char, 'devotion', 'Lay on Hands', :kind => 'spell')
          reload

          expect(Entries.focus_spells(@magic, 'devotion')).to eq [ 'Touch of the Void' ]
        end

        # Taking a spell away used to write the spell list into the cantrip list, clobbering the
        # cantrips and leaving the spell in place.
        it "should leave the cantrips alone" do
          Entries.grant_focus!(@char, 'devotion', [ 'Lay on Hands' ], :kind => 'spell', :granted_by => 'Champion')
          Entries.grant_focus!(@char, 'devotion', [ 'Shields of the Spirit' ], :kind => 'cantrip', :granted_by => 'Champion')

          Entries.revoke_focus!(@char, 'devotion', 'Lay on Hands', :kind => 'spell')
          reload

          expect(Entries.focus_spells(@magic, 'devotion')).to eq []
          expect(Entries.focus_cantrips(@magic, 'devotion')).to eq [ 'Shields of the Spirit' ]
        end
      end

      it "should report no focus magic for a character with none" do
        expect(Entries.focus?(@magic)).to be false
        expect(Entries.all_focus(@magic)).to eq []
      end

      # The writer the game actually uses.
      it "should record what update_magic grants" do
        PF2Magic.update_magic(@char, 'Champion', { 'focus_spell' => { 'devotion' => [ 'Lay on Hands' ] } }, nil)
        reload

        expect(Entries.focus_spells(@magic, 'devotion')).to eq [ 'Lay on Hands' ]
        expect(Entries.focus_entries(@magic, 'devotion').first['granted_by']).to eq 'Champion'
      end

      it "should record a focus cantrip through update_magic under the cantrip key" do
        PF2Magic.update_magic(@char, 'Champion', { 'focus_cantrip' => { 'devotion' => [ 'Shields of the Spirit' ] } }, nil)
        reload

        expect(Entries.focus_cantrips(@magic, 'devotion')).to eq [ 'Shields of the Spirit' ]
        expect(Entries.focus_spells(@magic, 'devotion')).to eq []
      end
    end
  end
end
