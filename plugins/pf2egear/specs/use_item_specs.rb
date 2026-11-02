require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # `use`: a consumable is used one at a time, and the last one used is gone.
    describe "using an item", :dbtest => true do

      class UseItemClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_failure(message)
          @failures << message.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = UseItemClient.new
        @room = Room.create(:name => "Larder#{rand(1000000)}")
        @char = Character.create(:name => "Drinker#{rand(1000000)}", :room => @room)
        @potion = PF2Consumable.create(:name => 'Healing Potion (Minor)', :quantity => 2, :character => @char)

        allow_any_instance_of(Room).to receive(:emit)
        allow(Login).to receive(:update_notification_count)
      end

      after(:each) do
        Character[@char.id].login_notices.each(&:delete)
        [ PF2Consumable[@potion.id], Character[@char.id], @room ].each { |one| one&.delete }
      end

      def use
        PF2UseItemCmd.new(@client, Command.new('use consumables=0'), Character[@char.id]).on_command
      end

      it "should use one at a time" do
        use

        expect(@client.failures).to eq []
        expect(PF2Consumable[@potion.id].quantity).to eq 1
      end

      it "should be gone once the last is used" do
        use
        use

        expect(@client.failures).to eq []
        expect(PF2Consumable[@potion.id]).to be_nil
        expect(@client.said.join).to include(t('pf2egear.item_used_up', :name => 'Healing Potion (Minor)'))
      end

      # What they carried into a running encounter is that encounter's until it ends: used or sold on their
      # own sheet meanwhile, they would have it twice.
      describe "what an encounter they are in carries" do
        before(:each) do
          @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
          Pf2e::Combatants.join(@encounter, @char.name, 10, :holder => Character[@char.id])
          Character[@char.id].encounters.add @encounter
          allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        end

        after(:each) { PF2Encounter[@encounter.id]&.delete }

        def sell
          PF2SellCmd.new(@client, Command.new('sell consumables=0/2'), Character[@char.id]).on_command
        end

        it "should be neither used nor sold from their own" do
          use
          sell

          expect(@client.failures).to eq [ t('pf2egear.item_in_encounter', :item => 'Healing Potion (Minor)', :id => @encounter.id) ] * 2
          expect(PF2Consumable[@potion.id].quantity).to eq 2
        end

        it "should be theirs to use and sell again once the encounter ends" do
          Pf2e::Encounters::Ending.end!(PF2Encounter[@encounter.id])
          use

          expect(@client.failures).to eq []
          expect(PF2Consumable[@potion.id].quantity).to eq 1
        end

        it "should leave what they bought since theirs to use" do
          bought = PF2Consumable.create(:name => 'Antidote (Lesser)', :quantity => 1, :character => @char)
          PF2UseItemCmd.new(@client, Command.new('use consumables=1'), Character[@char.id]).on_command

          expect(@client.failures).to eq []
          expect(PF2Consumable[bought.id]).to be_nil
        end
      end
    end
  end
end
