require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Every command sent to the database while counting, by this thread.
    module CountedCommands
      KEY = :pf2e_counted_commands

      def write(args)
        Thread.current[KEY] += 1 if Thread.current[KEY]
        super
      end
    end
    Redic::Client.prepend(CountedCommands) unless Redic::Client < CountedCommands

    # An encounter command reads what it needs once and only the encounter it is about, however long the
    # fight has run: each of these sends no more than a few hundred commands to the database. Reading the
    # same records again and again sent several thousand for a Strike or an action.
    describe "how much an encounter command asks of the database", :dbtest => true do
      include FightBench

      BUDGET = 300

      before(:each) do
        bench!(level: 5)
        3.times { |at| PF2Gear.create(:name => "Rope #{at}", :character => @hero) }
        2.times { PF2Consumable.create(:name => 'Minor Healing Potion', :quantity => 3, :character => @hero) }
        6.times { add('goblin warrior') }
        add('spirit priest')
        # A fight that has gone on a while.
        30.times { |at| run(PF2ConditionSetCmd, "condition/set ##{2 + at % 6}=frightened/#{1 + at % 3}") }
        Pf2eHP.get_hp_obj(hero).update(:damage => 10)
        @client.said.clear
      end

      after(:each) do
        [ PF2Gear, PF2Consumable ].each { |model| model.find(:character_id => @hero.id).each(&:delete) }
        clear_bench!
      end

      def sent(text, who)
        char = Character[who.id]
        handler = Pf2e.get_cmd_handler(@client, Command.new(text), char)
        Thread.current[CountedCommands::KEY] = 0
        handler.new(@client, Command.new(text), char).on_command
        Thread.current[CountedCommands::KEY]
      ensure
        Thread.current[CountedCommands::KEY] = nil
      end

      it "should keep each within its budget" do
        priest = Combatants.all(encounter).find { |one| one.label.start_with?('Spirit Priest') }.number
        typed = [ [ 'e/view', @hero ], [ 'e/sheet', @hero ], [ 'e/turn', @hero ], [ 'e/strike #2=fist', @hero ],
                  [ 'e/act trip=#3', @hero ], [ 'e/act demoralize=#4', @hero ], [ 'e/use consumables=0', @hero ],
                  [ "e/as ##{priest}=cast fear=#{@hero.name}", @gm ], [ "e/as #5=strike #{@hero.name}", @gm ],
                  [ 'condition/set #6=prone', @gm ], [ "condition/set #{@hero.name}=frightened/1", @gm ],
                  [ "heal #{@hero.name}=3", @gm ], [ 'damage #6=2', @gm ], [ 'e/next', @gm ], [ 'e/undo', @gm ],
                  [ 'e/redo', @gm ], [ 'e/scan', @gm ], [ 'e/history', @gm ] ]

        over = typed.map { |text, who| [ text, sent(text, who) ] }.select { |_text, count| count > BUDGET }

        expect(over).to eq []
      end
    end
  end
end
