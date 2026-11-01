require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An encounter's history: each change, taken back and put back whole.
    describe History, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @hero = Character.create(:name => "Hero#{rand(1000000)}", :pf2_level => 3)
        @hp = Pf2eHP.create(:character => @hero, :ancestry_hp => 8, :charclass_hp => 10)
        @hero.update(:hp => @hp)
        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        Combatants.join(@encounter, @hero.name, 10, :holder => Character[@hero.id])
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        @hp.delete
        @hero.delete
      end

      def encounter
        PF2Encounter[@encounter.id]
      end

      def standing
        CombatantStates.of(encounter, Character[@hero.id])
      end

      def hurt(amount)
        History.recording(encounter, "GM: damage #{amount}") { Pf2eHP.modify_damage(standing, amount) }
      end

      it "should record a change, and take it back and put it back" do
        hurt(7)

        expect(History.entries(encounter).map(&:said)).to eq [ 'GM: damage 7' ]

        expect(History.undo(encounter).ok?).to be true
        expect(standing.damage).to eq 0

        expect(History.redo(encounter).ok?).to be true
        expect(standing.damage).to eq 7
      end

      it "should step back through several, one at a time" do
        hurt(3)
        hurt(4)

        History.undo(encounter)
        expect(standing.damage).to eq 3

        History.undo(encounter)
        expect(standing.damage).to eq 0
        expect(History.undo(encounter).code).to eq :nothing_to_undo
      end

      it "should drop what could be redone once something new happens" do
        hurt(3)
        History.undo(encounter)
        hurt(5)

        expect(History.entries(encounter).map(&:said)).to eq [ 'GM: damage 5' ]
        expect(History.redo(encounter).code).to eq :nothing_to_redo
      end

      it "should record nothing for a change that changed nothing" do
        History.recording(encounter, 'GM: look') { }

        expect(History.entries(encounter)).to eq []
      end

      it "should record a change inside another as one" do
        History.recording(encounter, 'GM: as') { hurt(2) }

        expect(History.entries(encounter).map(&:said)).to eq [ 'GM: as' ]
      end

      it "should take back a creature added, and bring back one removed" do
        rat = Described.read('Rat', 'ac 12 hp 5 perception 2').state

        History.recording(encounter, 'GM: add') { Combatants.add_npc(encounter, :described => rat, :initiative => 5) }
        npc = encounter.npcs.to_a.first

        History.recording(encounter, 'GM: remove') do
          Combatants.leave(encounter, npc.number)
          npc.delete
        end

        History.undo(encounter)
        expect(encounter.npcs.to_a.map(&:id)).to eq [ npc.id ]
        expect(Combatants.all(encounter).map(&:label)).to include(npc.name)

        History.undo(encounter)
        expect(encounter.npcs.to_a).to eq []
        expect(Combatants.all(encounter).map(&:label)).to eq [ @hero.name ]
      end

      # What is set for the first time has nothing in the copy from before to be put back over it.
      it "should empty again what a change set for the first time" do
        History.recording(encounter, 'GM: explore') { standing.update(:exploration_activity => 'Scout') }

        History.undo(encounter)
        expect(standing.exploration_activity).to be_nil

        History.redo(encounter)
        expect(standing.exploration_activity).to eq 'Scout'
      end

      it "should take back an effect put on someone" do
        History.recording(encounter, 'GM: effect') { ActiveEffects.apply(standing, 'Effect: Adamantine Body', :encounter => encounter) }

        History.undo(encounter)

        expect(ActiveEffects.on(standing)).to eq []
      end

      describe "what its characters carry" do
        def carried_potion
          standing.consumables.to_a.first
        end

        before(:each) do
          @potion = PF2Consumable.create(:name => 'Minor Healing Potion', :quantity => 2, :character => @hero)
          @encounter.states.each(&:delete)
          @encounter.update(:participants => [])
          Combatants.join(PF2Encounter[@encounter.id], @hero.name, 10, :holder => Character[@hero.id])
        end

        after(:each) { PF2Consumable[@potion.id]&.delete }

        def drink
          History.recording(encounter, 'Hero: +e/use consumable=0') do
            left = carried_potion.quantity - 1
            left.zero? ? carried_potion.delete : carried_potion.update(:quantity => left)
          end
        end

        it "should give back an item used, and take it again, in the encounter's copy only" do
          drink

          History.undo(encounter)
          expect(carried_potion.quantity).to eq 2

          History.redo(encounter)
          expect(carried_potion.quantity).to eq 1
          expect(PF2Consumable[@potion.id].quantity).to eq 2
        end

        it "should bring back the last of an item, used up" do
          drink
          drink
          expect(carried_potion).to be_nil

          History.undo(encounter)

          expect(carried_potion.quantity).to eq 1
        end

        it "should be untouched by what happens to the character's own things outside" do
          drink
          PF2Consumable[@potion.id].update(:quantity => 5)

          expect(History.undo(encounter).ok?).to be true
          expect(carried_potion.quantity).to eq 2
          expect(PF2Consumable[@potion.id].quantity).to eq 5
        end
      end

      # Each entry holds the whole encounter twice over, so a long fight's history is large: a change, an
      # undo or a redo reads the one entry it needs, and the listing reads none of what they hold.
      describe "a long history" do
        before(:each) do
          5.times { |at| hurt(at + 1) }
          allow(Pf2eEncounterEntry).to receive(:[]).and_call_original
        end

        it "should read only the entry it takes back, puts back or answers with" do
          History.undo(encounter)
          History.redo(encounter)
          History.latest(encounter)

          expect(Pf2eEncounterEntry).to have_received(:[]).exactly(3).times
        end

        it "should read only the change it drops to record a new one after it" do
          History.undo(encounter)
          hurt(9)

          expect(Pf2eEncounterEntry).to have_received(:[]).exactly(2).times
          expect(History.listed(encounter).map { |one| [ one['seq'], one['said'] ] }.last(2)).to eq [ [ 4, 'GM: damage 4' ], [ 5, 'GM: damage 9' ] ]
        end

        it "should list each change with who spent a Hero Point in it" do
          History.latest(encounter).update(:hero_spent => { 'Aria' => 1 })

          expect(History.listed(encounter).map { |one| [ one['seq'], one['heroes'] ] }).to eq [ [ 1, [] ], [ 2, [] ], [ 3, [] ], [ 4, [] ], [ 5, [ 'Aria' ] ] ]
          expect(Pf2eEncounterEntry).to have_received(:[]).once
        end
      end

      # An entry holds what its change moved and nothing else: the rest of the encounter, and everything
      # its characters carry, is the same before and after.
      describe "what an entry holds" do
        it "should hold only the records the change moved, as they were and as they are" do
          hurt(7)
          entry = History.latest(encounter)
          state = standing.id.to_s

          expect(entry.before.keys - [ 'diff' ]).to eq [ 'states' ]
          expect(entry.before['states'].keys).to eq [ state ]
          expect([ entry.before['states'][state]['damage'].to_i, entry.after['states'][state]['damage'].to_i ]).to eq [ 0, 7 ]
        end

        it "should hold a record made as one that was not there, and take it away again" do
          rat = Described.read('Rat', 'ac 12 hp 5 perception 2').state
          History.recording(encounter, 'GM: add') { Combatants.add_npc(encounter, :described => rat, :initiative => 5) }
          made = encounter.npcs.to_a.first

          expect(History.latest(encounter).before['npcs']).to eq(made.id.to_s => nil)

          History.undo(encounter)
          expect(Pf2eNpc[made.id]).to be_nil
        end

        it "should still take back a change recorded whole" do
          before = History.snapshot(encounter)
          Pf2eHP.modify_damage(standing, 4)
          after = History.snapshot(encounter)
          Pf2eEncounterEntry.create(:encounter => encounter, :seq => 1, :said => 'GM: damage 4', :before => before, :after => after)
          encounter.update(:history_at => 1)

          History.undo(encounter)
          expect(standing.damage.to_i).to eq 0

          History.redo(encounter)
          expect(standing.damage.to_i).to eq 4
        end
      end

      it "should be frozen once the encounter ends" do
        hurt(3)
        encounter.update(:is_active => false)

        expect(History.undo(encounter).code).to eq :frozen
        expect(standing.damage).to eq 3
      end
    end
  end
end
