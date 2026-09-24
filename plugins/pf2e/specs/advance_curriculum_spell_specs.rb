require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # A Wizard's school teaches its curriculum, uncommon spells included. The Department of Mana
    # Syntaxia's only 9th-rank curriculum spell is Detonate Magic, which is uncommon, so a Wizard of
    # that school has to be able to learn it or the curriculum entry at 9th rank can never be filled.
    describe "advance/spell spellbook against a curriculum", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config
      end

      after(:each) do
        @magic.delete if @magic
        @char.delete if @char
      end

      def wizard(school)
        @char = Character.create(:name => "School#{rand(1000000)}")
        @magic = PF2Magic.create(:character => @char,
                                 :tradition => { 'Wizard' => [ 'arcane', 'master' ] },
                                 :spell_abil => { 'Wizard' => 'Intelligence' })
        @char.update(:magic => @magic)

        @char.update(:pf2_level => 16,
                     :advancing => true,
                     :pf2_base_info => { 'charclass' => 'Wizard', 'specialize' => school },
                     :pf2_to_assign => { 'spellbook' => { '9' => [ 'open' ] } },
                     :pf2_advancement => {})

        AutoBuilder.new(Character[@char.id])
      end

      it "should let a Wizard learn an uncommon spell from their school's curriculum" do
        builder = wizard('Department of Mana Syntaxia')
        char = builder.run 'advance/spell spellbook/9=Detonate Magic'

        expect(builder.failures).to be_empty
        expect(char.pf2_to_assign['spellbook']['9']).to eq [ 'Detonate Magic' ]
      end

      it "should refuse it to a Wizard of another school" do
        builder = wizard('Department of Urban Thaumaturgy')
        char = builder.run 'advance/spell spellbook/9=Detonate Magic'

        expect(builder.failures).to_not be_empty
        expect(char.pf2_to_assign['spellbook']['9']).to eq [ 'open' ]
      end
    end
  end
end
