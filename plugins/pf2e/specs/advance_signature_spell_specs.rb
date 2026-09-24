require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Signature and repertoire picks against spells a mystery grants, during a level-up.
    #
    # A Cosmos Oracle gains Darkness at 3rd level. The grant sits in the draft's magic_stats until
    # `advance/done`, and the Oracle can designate it a signature spell at that same level. Mystery
    # spells are the Oracle's whatever tradition they come from, and they reach the sheet without
    # the rarity check a spell picked by name goes through.
    describe "advance/spell against granted spells", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Mystery#{rand(1000000)}")
        @magic = PF2Magic.create(:character => @char,
                                 :tradition => { 'Oracle' => [ 'divine', 'trained' ] },
                                 :spell_abil => { 'Oracle' => 'Charisma' },
                                 :repertoire => { 'Oracle' => { '1' => [ 'Breathe Fire' ],
                                                                '4' => [ 'Talking Corpse' ] } })
        @char.update(:magic => @magic)

        @char.update(:pf2_level => 2,
                     :advancing => true,
                     :pf2_base_info => { 'charclass' => 'Oracle', 'specialize' => 'Cosmos' },
                     :pf2_to_assign => {
                       'repertoire' => { '1' => [ 'open' ], '2' => [ 'open' ], '4' => [ 'open' ] },
                       'signature' => { '1' => [ 'open' ], '2' => [ 'open' ], '4' => [ 'open' ] }
                     },
                     :pf2_advancement => {
                       'magic_stats' => { 'addrepertoire' => { '2' => [ 'Darkness' ] } }
                     })

        @builder = AutoBuilder.new(Character[@char.id])
      end

      after(:each) do
        @magic.delete if @magic
        @char.delete if @char
      end

      describe "a spell the level grants" do
        it "should be designated a signature spell at that level" do
          char = @builder.run 'advance/spell signature/2=Darkness'

          expect(@builder.failures).to be_empty
          expect(char.pf2_to_assign['signature']['2']).to eq [ 'Darkness' ]
        end

        it "should not be learned again into a repertoire slot" do
          char = @builder.run 'advance/spell repertoire/2=Darkness'

          expect(@builder.failures).to eq [ I18n.t('pf2emagic.spell_already_in_repertoire') ]
          expect(char.pf2_to_assign['repertoire']['2']).to eq [ 'open' ]
        end
      end

      describe "a granted spell off the class's tradition" do
        it "should be designated a signature spell" do
          char = @builder.run 'advance/spell signature/1=Breathe Fire'

          expect(@builder.failures).to be_empty
          expect(char.pf2_to_assign['signature']['1']).to eq [ 'Breathe Fire' ]
        end

        it "should still be refused as a spell to learn" do
          char = @builder.run 'advance/spell repertoire/1=Thunderstrike'

          expect(@builder.failures).to_not be_empty
          expect(char.pf2_to_assign['repertoire']['1']).to eq [ 'open' ]
        end
      end

      describe "an uncommon spell" do
        it "should be designated a signature spell when a grant put it in the repertoire" do
          char = @builder.run 'advance/spell signature/4=Talking Corpse'

          expect(@builder.failures).to be_empty
          expect(char.pf2_to_assign['signature']['4']).to eq [ 'Talking Corpse' ]
        end

        it "should be refused as a spell picked by name" do
          char = @builder.run 'advance/spell repertoire/4=Read Omens'

          expect(@builder.failures).to_not be_empty
          expect(char.pf2_to_assign['repertoire']['4']).to eq [ 'open' ]
        end

        it "should not be designated a signature spell when it is not known" do
          char = @builder.run 'advance/spell signature/4=Read Omens'

          expect(@builder.failures).to_not be_empty
          expect(char.pf2_to_assign['signature']['4']).to eq [ 'open' ]
        end
      end
    end
  end
end
