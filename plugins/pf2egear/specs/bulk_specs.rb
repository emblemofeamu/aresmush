require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # What a character's things come to, and what they can't do about it.
    describe Bulk do

      def item(bulk, quantity = nil, bag_id = nil)
        row = double(:bulk => bulk, :bag_id => bag_id)

        allow(row).to receive(:quantity).and_return(quantity) if quantity
        row
      end

      def bag(id, bulk: 0, bonus: 0, traits: [])
        double(:id => id, :bulk => bulk, :bulk_bonus => bonus, :traits => traits)
      end

      describe "what items weigh" do
        it "should count ten light items as one Bulk" do
          expect(Bulk.sum([ item(0.1, 10) ])).to eq 10
        end

        it "should multiply by quantity" do
          expect(Bulk.sum([ item(2, 3) ])).to eq 60
        end

        it "should count a row with no quantity as one" do
          expect(Bulk.sum([ item(1) ])).to eq 10
        end

        it "should not drift adding up light items" do
          expect(Bulk.sum(Array.new(3) { item(0.1) })).to eq 3
        end

        it "should round down once, at the end" do
          expect(Bulk.whole(Bulk.tally([ item(6), item(0.1, 7) ], []))).to eq 6
        end

        it "should show whole Bulk without a point" do
          expect(Bulk.shown(30)).to eq 3
          expect(Bulk.shown(15)).to eq 1.5
        end
      end

      describe "what a bag adds" do
        it "should add its own bulk and its contents" do
          expect(Bulk.carrying(bag(1, :bulk => 2), 30)).to eq 50
        end

        it "should not count what a backpack takes the weight of" do
          expect(Bulk.carrying(bag(1, :bonus => 2), 30)).to eq 10
        end

        # A bonus takes from its contents, and leaves the bag's own bulk alone.
        it "should not let a bonus take from the bag's own bulk" do
          expect(Bulk.carrying(bag(1, :bulk => 1, :bonus => 2), 10)).to eq 10
        end

        it "should not count what an extradimensional bag holds" do
          expect(Bulk.carrying(bag(1, :bulk => 1, :traits => [ 'extradimensional' ]), 250)).to eq 10
        end
      end

      describe "everything together" do
        it "should count a stowed item through its bag" do
          expect(Bulk.tally([ item(1), item(3, nil, 7) ], [ bag(7, :bonus => 2) ])).to eq 20
        end

        it "should count an item whose bag has gone as loose" do
          expect(Bulk.tally([ item(3, nil, 7) ], [])).to eq 30
        end
      end

      describe "the catalogue" do
        let(:bags) { YAML.load_file('game/config/pf2e_bags.yml')['pf2e_bags'] }

        it "should hold each pouch's Bulk as a limit, with no bonus" do
          pouches = bags.select { |name, _| name.start_with?('Spacious Pouch') }

          expect(pouches.values.map { |one| one['capacity'] }).to contain_exactly(25, 50, 100, 150)
          expect(pouches.values.map { |one| one['bulk_bonus'] }.uniq).to eq [ 0 ]
        end

        it "should hold each belt to a number of items of 1 Bulk or less" do
          belts = bags.select { |name, _| name.start_with?('Retrieval Belt') }

          expect(belts.values.map { |one| one['max_items'] }).to contain_exactly(1, 3, 10)
          expect(belts.values.map { |one| [ one['capacity'], one['max_item_bulk'] ] }.uniq).to eq [ [ 0, 1 ] ]
        end

        it "should hold sleeves to their Bulk, and items of 1 Bulk or less" do
          expect(bags['Sleeves of Storage'].values_at('capacity', 'max_item_bulk')).to eq [ 10, 1 ]
          expect(bags['Sleeves of Storage (Greater)'].values_at('capacity', 'max_item_bulk')).to eq [ 40, 1 ]
        end

        it "should leave only a backpack with a bonus" do
          expect(bags.select { |_, one| one['bulk_bonus'].to_f.positive? }.keys).to eq [ 'Backpack' ]
        end
      end

      # Ohm assigns every stored field on load, and live bags have this one stored.
      it "should keep the attribute old bags have stored" do
        expect(PF2Bag.new.respond_to?(:gear_contents=)).to be true
      end
    end

    describe "what a character carries", :dbtest => true do

      class BagSpecClient
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

        def screen_reader
          false
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = BagSpecClient.new
        @room = Room.create(:name => "Porter#{rand(1000000)}")
        @char = Character.create(:name => "Porter#{rand(1000000)}", :room => @room, :pf2_money => 100000, :pf2_level => 1)

        allow_any_instance_of(Room).to receive(:emit)
        allow(Login).to receive(:update_notification_count)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
      end

      after(:each) do
        Inventory::CATEGORIES.each { |row| Inventory.model(row['names'].first).find(:character_id => @char.id).each(&:delete) }
        [ Character[@char.id], @room ].each { |one| one&.delete }
      end

      def reread
        Character[@char.id]
      end

      def backpack(capacity: 4, bonus: 2)
        PF2Bag.create(:name => 'Backpack', :character => @char, :capacity => capacity, :bulk_bonus => bonus)
      end

      def gear(name, quantity, bulk = 0.1, **more)
        PF2Gear.create({ :name => name, :character => @char, :quantity => quantity, :bulk => bulk }.merge(more))
      end

      def store(text)
        PF2BagStoreCmd.new(@client, Command.new("bag/store #{text}"), reread).on_command
      end

      def retrieve(text)
        PF2BagRetrieveCmd.new(@client, Command.new("bag/retrieve #{text}"), reread).on_command
      end

      def weigh_down(bulk = 7)
        gear('Anvil', 1, bulk)
      end

      def encumbered
        Pf2e.held_conditions(reread)['Encumbered']
      end

      describe "bag/store" do
        it "should store a whole stack with no quantity" do
          bag = backpack
          torch = gear('Torch', 5)

          store('gear/0=0')

          expect(@client.failures).to eq []
          expect(PF2Gear[torch.id].bag_id).to eq bag.id
          expect(PF2Gear[torch.id].quantity).to eq 5
        end

        it "should split a stack" do
          bag = backpack
          torch = gear('Torch', 5)

          store('gear/0 = 0/3')

          expect(@client.failures).to eq []
          expect(PF2Gear[torch.id].quantity).to eq 2
          expect(PF2Gear[torch.id].bag_id).to be_nil
          expect(PF2Bag[bag.id].gear.to_a.map(&:quantity)).to eq [ 3 ]
        end

        it "should join what is already there" do
          bag = backpack
          stowed = gear('Torch', 2, 0.1, :bag => bag)
          torch = gear('Torch', 5)

          store('gear/0 = 0/3')

          expect(PF2Gear[stowed.id].quantity).to eq 5
          expect(PF2Gear[torch.id].quantity).to eq 2
          expect(PF2Bag[bag.id].gear.to_a.size).to eq 1
        end

        it "should remove the stack when all of it joins what is there" do
          bag = backpack
          stowed = gear('Torch', 2, 0.1, :bag => bag)
          torch = gear('Torch', 5)

          store('gear/0 = 0')

          expect(PF2Gear[stowed.id].quantity).to eq 7
          expect(PF2Gear[torch.id]).to be_nil
        end

        it "should keep apart what was made to last a while" do
          bag = backpack
          stowed = gear('Torch', 2, 0.1, :bag => bag, :granted_by => 'crafting', :expires => 'rest')

          gear('Torch', 5)
          store('gear/0 = 0/3')

          expect(PF2Gear[stowed.id].quantity).to eq 2
          expect(PF2Bag[bag.id].gear.to_a.size).to eq 2
        end

        it "should carry the stack's facts onto the part that splits off" do
          bag = backpack

          gear('Torch', 5, 0.1, :granted_by => 'crafting', :expires => 'rest')
          store('gear/0 = 0/3')

          stowed = PF2Bag[bag.id].gear.to_a.first

          expect([ stowed.name, stowed.bulk, stowed.granted_by, stowed.expires ]).to eq [ 'Torch', 0.1, 'crafting', 'rest' ]
        end

        it "should refuse more than they have" do
          backpack
          torch = gear('Torch', 2)

          store('gear/0 = 0/3')

          expect(@client.failures).to eq [ t('pf2egear.bag_not_enough', :name => 'Torch', :have => 2) ]
          expect(PF2Gear[torch.id].quantity).to eq 2
        end

        it "should refuse a quantity of nothing" do
          backpack
          gear('Torch', 2)

          store('gear/0 = 0/0')

          expect(@client.failures).to eq [ t('pf2egear.bad_quantity') ]
        end

        it "should refuse what is over the bag's Bulk" do
          backpack
          anvil = gear('Anvil', 1, 5)

          store('gear/0 = 0')

          expect(@client.failures.size).to eq 1
          expect(@client.failures.first).to include 'no room'
          expect(PF2Gear[anvil.id].bag_id).to be_nil
        end

        it "should weigh the whole of what is stored against it" do
          bag = backpack(:capacity => 1, :bonus => 0)
          torch = gear('Torch', 11)

          store('gear/0 = 0')

          expect(PF2Gear[torch.id].bag_id).to be_nil

          store('gear/0 = 0/10')

          expect(PF2Bag[bag.id].gear.to_a.map(&:quantity)).to eq [ 10 ]
        end

        it "should hold a belt to its number of items" do
          belt = PF2Bag.create(:name => 'Retrieval Belt', :character => @char, :capacity => 0, :max_items => 1, :max_item_bulk => 1)

          gear('Torch', 2)
          store('gear/0 = 0')

          expect(@client.failures.first).to eq t('pf2egear.bag_too_many', :bag => 'Retrieval Belt', :max => 1, :held => 0)

          store('gear/0 = 0/1')

          expect(PF2Bag[belt.id].gear.to_a.map(&:quantity)).to eq [ 1 ]
        end

        it "should refuse an item too big for the bag" do
          PF2Bag.create(:name => 'Sleeves', :character => @char, :capacity => 10, :max_item_bulk => 1)
          gear('Anvil', 1, 2)

          store('gear/0 = 0')

          expect(@client.failures).to eq [ t('pf2egear.bag_item_too_big', :name => 'Anvil', :bag => 'Sleeves', :max => 1) ]
        end

        it "should refuse what is equipped" do
          backpack
          PF2Weapon.create(:name => 'Club', :character => @char, :equipped => true)

          store('weapons/0 = 0')

          expect(@client.failures).to eq [ t('pf2egear.bag_item_worn', :name => 'Club') ]
        end

        it "should refuse what is invested" do
          backpack
          PF2MagicItem.create(:name => 'Ring', :character => @char, :invested => true)

          store('magicitem/0 = 0')

          expect(@client.failures).to eq [ t('pf2egear.bag_item_worn', :name => 'Ring') ]
        end

        describe "in an encounter" do
          before(:each) do
            @bag = backpack
            @torch = gear('Torch', 2)
            @stowed = gear('Rope', 1, 0.1, :bag => @bag)
            @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
            Pf2e::Combatants.join(@encounter, @char.name, 10, :holder => reread)
            reread.encounters.add @encounter
          end

          it "should refuse to store what it holds" do
            store('gear/0 = 0')

            expect(@client.failures.first).to eq t('pf2egear.item_in_encounter', :item => 'Torch', :id => @encounter.id)
            expect(PF2Gear[@torch.id].bag_id).to be_nil
          end

          it "should refuse to retrieve what it holds" do
            retrieve('gear/0 = 0')

            expect(@client.failures.first).to eq t('pf2egear.item_in_encounter', :item => 'Rope', :id => @encounter.id)
            expect(PF2Gear[@stowed.id].bag_id).to eq @bag.id
          end

          # The state carries its own copies, stowed as the character's were.
          it "should count a character's state from its own copies" do
            state = Pf2e::CombatantStates.of(PF2Encounter[@encounter.id], reread)

            expect(Bulk.total(state)).to eq Bulk.total(reread)
            gear('Anvil', 1, 9)
            expect(Bulk.total(state)).to_not eq Bulk.total(reread)
          end
        end
      end

      describe "bag/retrieve" do
        it "should split a stack, and join what they hold" do
          bag = backpack
          stowed = gear('Torch', 5, 0.1, :bag => bag)
          held = gear('Torch', 1)

          retrieve('gear/0 = 0/3')

          expect(@client.failures).to eq []
          expect(PF2Gear[stowed.id].quantity).to eq 2
          expect(PF2Gear[held.id].quantity).to eq 4
        end

        it "should take a whole stack with no quantity" do
          bag = backpack
          stowed = gear('Torch', 5, 0.1, :bag => bag)

          retrieve('gear/0 = 0')

          expect(PF2Gear[stowed.id].bag_id).to be_nil
        end

        it "should warn someone it leaves encumbered" do
          bag = backpack

          gear('Anvil', 1, 4)
          gear('Rock', 1, 2, :bag => bag)
          gear('Weight', 1, 1)
          expect(encumbered).to be_nil

          retrieve('gear/0 = 0')

          expect(encumbered).to_not be_nil
          expect(@client.said.join).to include t('pf2egear.encumbered_warning', :carried => 7, :limit => 5, :max => 10)
        end
      end

      describe "bag <#>" do
        def viewed
          PF2BagViewCmd.new(@client, Command.new("bag 0"), reread).on_command

          @client.said.last
        end

        def magic_item(name, bag, **more)
          PF2MagicItem.create({ :name => name, :character => @char, :bag => bag }.merge(more))
        end

        it "should list the magic items in the bag, and only those" do
          bag = backpack

          magic_item('Bracers of Armor', bag, :bulk => 0.1)
          magic_item('Ring of Wizardry', nil)

          expect(viewed).to match(/Magic Items.*Bracers of Armor\s*%bL/m)
          expect(viewed).to_not include 'Ring of Wizardry'
        end

        it "should show a magic item's nickname" do
          magic_item('Ring of Wizardry', backpack, :nickname => "Grandfather's Ring")

          expect(viewed).to include "Grandfather's Ring (Ring of Wizardry)"
        end

        it "should give the number bag/retrieve takes" do
          bag = backpack
          items = %w{Bracers Cloak Ring}.map { |name| magic_item(name, bag) }

          number = viewed[/(\d+)\s*%bCloak/, 1]

          retrieve("magicitem/#{number} = 0")

          expect(@client.failures).to eq []
          expect(PF2MagicItem[items[1].id].bag_id).to be_nil
          expect(PF2MagicItem[items[0].id].bag_id).to eq bag.id
          expect(PF2MagicItem[items[2].id].bag_id).to eq bag.id
        end
      end

      describe "buy" do
        def buy(text)
          PF2BuyCmd.new(@client, Command.new("buy #{text}"), reread).on_command
        end

        it "should sell what leaves them encumbered, and tell them" do
          gear('Anvil', 1, 5)

          buy('bags = chest')

          expect(@client.failures).to eq []
          expect(reread.bags.to_a.map(&:name)).to eq [ 'Chest' ]
          expect(@client.said.join).to include t('pf2egear.encumbered_warning', :carried => 7, :limit => 5, :max => 10)
        end

        it "should say nothing to someone it leaves unencumbered" do
          buy('bags = chest')

          expect(@client.said.join).to_not include 'encumbered'
        end

        it "should say nothing more to someone already encumbered" do
          weigh_down

          buy('bags = chest')

          expect(@client.said.join).to_not include 'encumbered'
        end

        it "should name the maximum when it is passed" do
          weigh_down(9)

          buy('bags = chest')

          expect(@client.said.join).to include t('pf2egear.over_maximum_warning', :carried => 11, :limit => 5, :max => 10)
        end

        it "should count every one of a quantity" do
          gear('Anvil', 1, 5)

          buy('gear = torch/10')

          expect(reread.gear.to_a.find { |one| one.name == 'Torch' }.quantity).to eq 10
          expect(encumbered).to_not be_nil
        end
      end

      describe "Encumbered" do
        it "should come at more than the limit, and bring what it brings" do
          gear('Anvil', 1, 6)

          held = Pf2e.held_conditions(reread)

          expect(held['Encumbered']).to include('granted_by' => 'Bulk', 'derived' => true)
          expect(held['Clumsy']).to_not be_nil
        end

        it "should not come at the limit itself" do
          gear('Anvil', 1, 5)

          expect(encumbered).to be_nil
        end

        # The ruling from Paizo: at a limit of 5, 5 Bulk and 9 light is under.
        it "should not come until the next whole Bulk" do
          gear('Anvil', 1, 5)
          stack = gear('Torch', 9)

          expect(encumbered).to be_nil

          stack.update(:quantity => 10)

          expect(encumbered).to_not be_nil
        end

        it "should go when the bulk does" do
          anvil = gear('Anvil', 1, 6)

          expect(encumbered).to_not be_nil

          anvil.delete

          expect(encumbered).to be_nil
        end

        it "should lift when a load is stowed extradimensionally" do
          pouch = PF2Bag.create(:name => 'Spacious Pouch (Type I)', :character => @char, :capacity => 25,
                                :traits => [ 'extradimensional' ], :bulk => 1)
          anvil = gear('Anvil', 1, 6)

          expect(encumbered).to_not be_nil

          anvil.update(:bag => pouch)

          expect(encumbered).to be_nil
        end

        it "should stay as it was set in its own right" do
          Pf2e.set_condition(reread, 'Encumbered')

          expect(encumbered).to include('derived' => false)
        end

        it "should be off when encumbrance is" do
          gear('Anvil', 1, 6)

          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e_gear_options', 'use_encumbrance').and_return(false)

          expect(encumbered).to be_nil
        end

        # Working out what a character's rules write, `Paths.apply_all!` empties what those rules wrote, so
        # Hefty Hauler's two Bulk are missing for a moment. No rule writes anything on being Encumbered.
        it "should leave what rules write the same, whatever the moment's threshold" do
          gear('Anvil', 1, 6)
          @char.update(:pf2_derived => { 'encumberedafteraddend' => 2 })
          expect(encumbered).to be_nil

          predicates = YAML.load_file('game/config/pf2e_actions.yml').to_s.scan('condition:encumbered').size

          expect(predicates).to eq 1
        end
      end

      describe "the total during a command" do
        it "should be a command's own to hold, for a gear command" do
          expect(Pf2egear.get_cmd_handler(nil, Command.new('gear'), nil)).to be < Pf2e::ReadsOnce
        end

        it "should count a holder's things once" do
          gear('Anvil', 1, 2)
          char = reread

          Pf2e::SheetReads.during do
            expect(Bulk.total(char)).to eq 20

            expect(Bulk).to_not receive(:tally)
            expect(Bulk.total(char)).to eq 20
          end
        end

        Inventory::CATEGORIES.each do |row|
          it "should count again when #{row['names'].first} are written" do
            model = Inventory.model(row['names'].first)
            fields = { :name => 'Thing', :character => @char, :bulk => 1 }
            char = reread

            Pf2e::SheetReads.during do
              expect(Bulk.total(char)).to eq 0

              made = model.create(fields)
              expect(Bulk.total(char)).to eq 10

              made.update(:bulk => 2)
              expect(Bulk.total(char)).to eq 20

              made.delete
              expect(Bulk.total(char)).to eq 0
            end
          end
        end

        it "should keep nothing past the command" do
          char = reread

          Pf2e::SheetReads.during { expect(Bulk.total(char)).to eq 0 }

          gear('Anvil', 1, 2)
          expect(Bulk.total(char)).to eq 20
        end
      end

      # Gear's rules can be read off an item that has no nickname to ask for.
      describe "the name of something carried", :dbtest => true do
        it "should be its name, for a kind of item that takes no nickname" do
          expect(Pf2egear.get_item_name(gear('Religious Symbol (Silver)', 1, 0))).to eq 'Religious Symbol (Silver)'
        end

        it "should show a nickname on an item that has one" do
          weapon = PF2Weapon.create(:name => 'Longsword', :character => @char, :nickname => 'Glint')

          expect(Pf2egear.get_item_name(weapon)).to eq 'Glint (Longsword)'
        end
      end
    end
  end
end
