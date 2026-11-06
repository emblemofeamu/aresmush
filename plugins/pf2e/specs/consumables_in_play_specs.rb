require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a consumable does when it is used in a fight: a potion heals whoever drinks it, an elixir or a
    # mutagen puts its effect on them, and a bomb is thrown as a Strike and spent.
    #
    # Every die shows `@dice` of its faces: at 0.75 a d8 is 6 and a d20 is 15.
    describe "what the catalogue says consumables do" do
      before(:all) do
        @consumables = YAML.load_file('game/config/pf2e_consumables.yml')['pf2e_consumables']
        @effects = YAML.load_file('game/config/pf2e_effects.yml')['pf2e_effects']
      end

      # A glue bomb deals nothing and sticks; every other deals damage of a kind.
      it "should give every bomb its damage or its effect" do
        bombs = @consumables.select { |_name, info| Array(info['traits']).include?('bomb') && info['category'] }

        expect(bombs.reject { |_name, info|
          info['bomb'] && ((info.dig('bomb', 'damage_type') && info.dig('bomb', 'dice').to_i.positive?) || info['effect'])
        }.keys).to eq []
      end

      it "should name only effects the game has" do
        expect(@consumables.select { |_name, info| info['effect'] && !@effects.key?(info['effect']) }.keys).to eq []
      end
    end

    describe "consumables in a fight", :dbtest => true do

      class ConsumableClient
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

        @client = ConsumableClient.new
        @room = Room.create(:name => "Alley#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @hero = hero("Vex")
        @ally = hero("Bram")
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1,
                                         :is_active => true)

        @dice = 0.75
        allow(Pf2e).to receive(:roll_dice) { |amount = 1, sides = 20| [ [ (sides.to_i * @dice).ceil, 1 ].max ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.npcs&.each(&:delete)
        PF2Encounter[@encounter.id]&.delete
        @made.each { |one| one.class[one.id]&.delete }
        [ @gm, @scene, @room ].each(&:delete)
      end

      def hero(name)
        @made ||= []
        char = Character.create(:name => "#{name}#{rand(1000000)}", :room => @room, :pf2_level => 1, :pf2_conditions => {},
                                :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {},
                                :pf2_base_info => { 'charclass' => 'Alchemist' },
                                :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        combat = Pf2eCombat.create(:character => char, :armor_prof => { 'unarmored' => 'trained' },
                                   :weapon_prof => { 'simple' => 'trained', 'martial' => 'trained', 'unarmed' => 'trained' })
        hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 8)
        char.update(:combat => combat, :hp => hp)
        abilities = Pf2e::ABILITIES.map { |ability| Pf2eAbilities.create(:character => char, :name => ability, :base_val => 14) }
        @made += [ char, combat, hp ] + abilities
        char
      end

      def carry(char, name, quantity = 1)
        Pf2egear.create_item(Character[char.id], 'consumables', name, quantity, Global.read_config('pf2e_consumables', name))
      end

      def join(char)
        Combatants.join(PF2Encounter[@encounter.id], char.name, 10, :holder => Character[char.id])
      end

      def standing(char)
        CombatantStates.of(PF2Encounter[@encounter.id], Character[char.id])
      end

      def wound(char, amount)
        standing(char).update(:damage => amount)
      end

      def run(cmd_class, text, who = @hero)
        cmd_class.new(@client, Command.new(text), Character[who.id]).on_command
      end

      def use(text, who = @hero)
        run(Pf2egear::PF2EncounterUseCmd, "e/use #{text}", who)
      end

      def carried(char, name)
        standing(char).consumables.to_a.find { |one| one.name == name }
      end

      def said
        @client.said.join("\n")
      end

      describe "a healing potion" do
        before(:each) do
          carry(@hero, 'Healing Potion (Minor)', 2)
          join(@hero)
          join(@ally)
          wound(@hero, 10)
          wound(@ally, 10)
        end

        it "should heal whoever drinks it by its dice, and be one fewer" do
          use('consumables=0')

          expect(@client.failures).to eq []
          expect(standing(@hero).damage).to eq 10 - 6
          expect(carried(@hero, 'Healing Potion (Minor)').quantity).to eq 1
          expect(said).to include('regains 6')
        end

        it "should heal the ally it is given to" do
          use("consumables=0/#{@ally.name}")

          expect(@client.failures).to eq []
          expect(standing(@ally).damage).to eq 10 - 6
          expect(standing(@hero).damage).to eq 10
        end

        it "should refuse someone who is not in the fight, and spend nothing" do
          use('consumables=0/Nobody')

          expect(@client.failures).to_not eq []
          expect(carried(@hero, 'Healing Potion (Minor)').quantity).to eq 2
        end

        # A healing potion's vitality heals the living; to the undead it is nothing.
        it "should do nothing for an undead creature" do
          run(PF2EncounterAddCmd, 'e/add zombie shambler', @gm)
          zombie = PF2Encounter[@encounter.id].npcs.to_a.first
          zombie.update(:damage => 5)

          use("consumables=0/##{Combatants.rows(PF2Encounter[@encounter.id]).find { |row| row['npc'] }['id']}")

          expect(Pf2eNpc[zombie.id].damage).to eq 5
          expect(said).to include(t('pf2e.consumable_no_effect', :item => 'Healing Potion (Minor)', :target => zombie.name))
        end

        it "should be taken back, potion and all, by the GM" do
          use('consumables=0')
          run(PF2EncounterUndoCmd, 'e/undo', @gm)

          expect(standing(@hero).damage).to eq 10
          expect(carried(@hero, 'Healing Potion (Minor)').quantity).to eq 2
        end
      end

      it "should heal with an elixir of life and leave its effect" do
        carry(@hero, 'Elixir of Life (Minor)')
        join(@hero)
        wound(@hero, 10)

        use('consumables=0')

        expect(standing(@hero).damage).to eq 10 - 5
        expect(ActiveEffects.on(standing(@hero)).map(&:name)).to include('Effect: Elixir of Life')
      end

      it "should put a mutagen's effect on whoever drinks it" do
        carry(@hero, 'Juggernaut Mutagen (Lesser)')
        join(@hero)

        use('consumables=0')

        expect(@client.failures).to eq []
        expect(ActiveEffects.on(standing(@hero)).map(&:name)).to include('Effect: Juggernaut Mutagen (Lesser)')
      end

      describe "a bomb" do
        before(:each) do
          carry(@hero, "Alchemist's Fire (Lesser)", 2)
          join(@hero)
          run(PF2EncounterAddCmd, 'e/add goblin warrior', @gm)
          @goblin = Combatants.rows(PF2Encounter[@encounter.id]).find { |row| row['npc'] }
        end

        def goblin
          Pf2eNpc[@goblin['npc']]
        end

        it "should be refused as something to drink" do
          use('consumables=0')

          expect(@client.failures).to eq [ t('pf2e.consumable_throw_it', :item => "Alchemist's Fire (Lesser)") ]
          expect(carried(@hero, "Alchemist's Fire (Lesser)").quantity).to eq 2
        end

        it "should be thrown as a Strike: its fire, its persistent fire and its splash, and one is spent" do
          run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=alchemist's fire")

          expect(@client.failures).to eq []
          expect(said).to include("Alchemist's Fire (Lesser)")
          expect(said).to include('7 fire (1d8: 6; with 1 splash) + 1 persistent fire')
          expect(PersistentDamage.held(goblin).map { |one| [ one['formula'], one['type'] ] }).to eq [ [ '1', 'fire' ] ]
          expect(carried(@hero, "Alchemist's Fire (Lesser)").quantity).to eq 1
        end

        # A critical hit doubles the bomb's dice and its persistent damage, and not its splash.
        it "should double all but its splash on a critical hit" do
          @dice = 1.0

          run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=alchemist's fire")

          expect(said).to include('17 fire (1d8: 8 = 8, doubled; with 1 splash) + 2 persistent fire')
        end

        it "should leave a glue bomb's effect on the creature it hits" do
          carry(@hero, 'Glue Bomb (Lesser)')
          @hero = Character[@hero.id]
          PF2Encounter[@encounter.id].states.each(&:delete)
          Combatants.leave(PF2Encounter[@encounter.id], Combatants.rows(PF2Encounter[@encounter.id]).find { |row| row['char'] }['id'])
          join(@hero)

          run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=glue bomb")

          expect(@client.failures).to eq []
          expect(ActiveEffects.on(goblin).map(&:name)).to include('Effect: Glue Bomb')
        end

        # A bomb in a pack is not worn, and its notes name its own attack, so they come with its throw
        # and no other Strike. The hit puts on the bomb's effect; the note that links it does not again.
        describe "a glue bomb's notes" do
          before(:each) do
            carry(@hero, 'Glue Bomb (Lesser)')
            @hero = Character[@hero.id]
            PF2Encounter[@encounter.id].states.each(&:delete)
            Combatants.leave(PF2Encounter[@encounter.id], Combatants.rows(PF2Encounter[@encounter.id]).find { |row| row['char'] }['id'])
            join(@hero)
          end

          def glue_effects
            ActiveEffects.on(goblin).map(&:name).count('Effect: Glue Bomb')
          end

          it "should tell its note on a hit, and put its effect on once" do
            run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=glue bomb")

            expect(@client.failures).to eq []
            expect(said).to include('On a hit, -10-foot Speed penalty for 1 minute.')
            expect(said).not_to include('Immobilized')
            expect(said).not_to include('is now under Effect: Glue Bomb')
            expect(glue_effects).to eq 1
          end

          it "should tell its critical hit's note on a critical hit" do
            @dice = 1.0

            run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=glue bomb")

            expect(said).to include('Immobilized for 1 round')
            expect(said).not_to include('On a hit,')
            expect(glue_effects).to eq 1
          end

          it "should not tell its notes with another bomb's Strike" do
            run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=alchemist's fire")

            expect(said).to include("Alchemist's Fire (Lesser)")
            expect(said).not_to include('Speed penalty')
          end
        end

        # Splash lands on a miss too, though not on a critical miss.
        it "should splash the target when it misses" do
          @dice = 0.4

          run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=alchemist's fire")

          expect(said).to include('miss', '1 splash fire')
          expect(goblin.damage).to eq 1
          expect(PersistentDamage.held(goblin)).to eq []
          expect(carried(@hero, "Alchemist's Fire (Lesser)").quantity).to eq 1
        end

        it "should be gone once the last is thrown" do
          2.times { run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=alchemist's fire") }

          expect(carried(@hero, "Alchemist's Fire (Lesser)")).to be_nil
          run(PF2EncounterStrikeCmd, "e/strike ##{@goblin['id']}=alchemist's fire")
          expect(@client.failures.last).to eq t('pf2e.act_no_attack', :attack => "alchemist's fire")
        end
      end
    end
  end
end
