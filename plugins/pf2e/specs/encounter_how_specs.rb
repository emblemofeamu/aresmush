require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # `+e/how <name>`, typed in an encounter: the commands for what the player names, from what they have
    # there.
    describe "asking how to do something in an encounter", :dbtest => true do
      include FightBench

      before(:each) { bench! }

      after(:each) do
        PF2Consumable.find(:character_id => @hero.id).each(&:delete)
        clear_bench!
      end

      def how(name)
        @client.said.clear
        hero_types("e/how #{name}")
        @client.said.join("\n")
      end

      it "should give a command for each Strike they can make" do
        expect(how('strike')).to include('+e/strike <target>=Fist', '+e/strike <target>=Claw')
      end

      it "should give an action anyone can use, with what it is used at" do
        expect(how('trip')).to include('+e/act trip=<target>')
      end

      it "should give what spends a Hero Point" do
        expect(how('reroll')).to include('hero/reroll', 'hero/boost', 'hero/survive')
      end

      it "should give how to use what they carried in, by its number there" do
        PF2Consumable.create(:name => 'Healing Potion (Minor)', :quantity => 1, :state => hero)

        expect(how('healing potion')).to include('+e/use consumables=0')
      end

      it "should say when nothing goes by the name" do
        how('nothing at all')

        expect(@client.failures.last).to eq t('pf2e.how_nothing', :name => 'nothing at all')
      end
    end
  end
end
