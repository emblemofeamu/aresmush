require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A spell cast in an encounter whose effect asks a question. What the caster says after the target
    # answers it. A spell that goes on one of the target's things - Runic Weapon, Shillelagh - takes the
    # one thing in their hands without being told, and is refused before it is spent where there is no
    # telling which.
    describe "casting a spell whose effect asks something", :dbtest => true do

      class CastItemClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_failure(msg)
          @failures << msg.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |msg| @said << msg.to_s } }

        def to_s
          "CastItemClient"
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = CastItemClient.new
        @room = Room.create(:name => "Arena#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :temp_room => true)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        @caster = pc('Caster')

        allow(Pf2e).to receive(:roll_dice) { |amount = 1, _sides = 20| [ 10 ] * amount.to_i }
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| @client.said << message.to_s }
        allow(Scenes).to receive(:add_to_scene)
        allow(Login).to receive(:emit_ooc_if_logged_in)
        allow(Login).to receive(:notify)
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow_any_instance_of(Character).to receive(:has_permission?).and_call_original
        allow_any_instance_of(Character).to receive(:has_permission?).with('kill_pc') { |char, _| char.name == @gm.name }
      end

      # A character in the encounter, with what they walked in with: `in_hand` equipped, `carried` not.
      def pc(prefix, in_hand: [], carried: [])
        char = Character.create(:name => "#{prefix}#{rand(1000000)}", :room => @room)
        combat = Pf2eCombat.create(:character => char, :armor_prof => { 'unarmored' => 'trained' },
                                   :weapon_prof => { 'martial' => 'trained', 'simple' => 'trained' })
        hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 10)
        char.update(:combat => combat, :hp => hp, :pf2_level => 1, :pf2_conditions => {}, :pf2_traits => [],
                    :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                    :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        ABILITIES.each { |name| Pf2eAbilities.create(:character => char, :name => name, :base_val => 14) }

        (in_hand + carried).each do |name|
          item = Pf2egear.create_item(char, 'weapons', name, 1, Global.read_config('pf2e_weapons', name))
          item.update(:equipped => in_hand.include?(name))
        end

        char.encounters.add @encounter
        @encounter.characters.add char
        Combatants.join(@encounter, char.name, 30, :holder => char)

        char
      end

      def fight
        PF2Encounter[@encounter.id]
      end

      def combatant(char)
        Combatants.find(fight, char.name).state
      end

      def scene(target = nil)
        Acting::Scene.new(fight, combatant(@caster), target, @gm, true)
      end

      def cast(spell, target, words = [])
        Acting.cast(scene(target), spell, [ target ], words).state['lines']
      end

      def needed(spell, target, words = [])
        Acting.item_needed(scene(target), spell, [ target ], words)
      end

      def weapon(char, name)
        combatant(char).holder.weapons.to_a.find { |one| one.name == name }
      end

      def strike(char, name)
        Pf2eCombat.attack_descriptor(combatant(char).holder, weapon(char, name))
      end

      def effects_on(char)
        ActiveEffects.on(combatant(char).holder)
      end

      describe "Runic Weapon, cast on someone else" do
        it "should make the weapon named +1 striking" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          cast('Runic Weapon', combatant(ally), [ 'longsword' ])

          expect(strike(ally, 'Longsword').values_at('rune', 'striking')).to eq [ 1, 1 ]
          expect(strike(ally, 'Dagger').values_at('rune', 'striking')).to eq [ 0, 0 ]
        end

        it "should be better heightened" do
          ally = pc('Ally', :in_hand => [ 'Longsword' ])

          cast('Runic Weapon', combatant(ally), [ 'longsword', 'rank 6' ])

          expect(strike(ally, 'Longsword').values_at('rune', 'striking')).to eq [ 2, 2 ]
        end

        it "should take the one weapon in their hands without being told" do
          ally = pc('Ally', :in_hand => [ 'Longsword' ], :carried => [ 'Dagger' ])

          expect(needed('Runic Weapon', combatant(ally))).to be_nil

          cast('Runic Weapon', combatant(ally))

          expect(strike(ally, 'Longsword').values_at('rune', 'striking')).to eq [ 1, 1 ]
        end

        it "should go on a weapon named that is not in their hands" do
          ally = pc('Ally', :in_hand => [ 'Longsword' ], :carried => [ 'Dagger' ])

          expect(needed('Runic Weapon', combatant(ally), [ 'dagger' ])).to be_nil

          cast('Runic Weapon', combatant(ally), [ 'dagger' ])

          expect(strike(ally, 'Dagger').values_at('rune', 'striking')).to eq [ 1, 1 ]
          expect(strike(ally, 'Longsword').values_at('rune', 'striking')).to eq [ 0, 0 ]
        end

        it "should ask which of two weapons in their hands" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          refused = needed('Runic Weapon', combatant(ally))

          expect(refused.code).to eq :item_needed
          expect(refused.args['items'].split(', ')).to contain_exactly('Longsword', 'Dagger')
        end

        it "should ask again when the weapon named is not one of theirs" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          expect(needed('Runic Weapon', combatant(ally), [ 'greatsword' ]).code).to eq :item_needed
        end

        it "should offer what they carry when nothing is in their hands" do
          ally = pc('Ally', :carried => [ 'Dagger' ])

          refused = needed('Runic Weapon', combatant(ally))

          expect(refused.code).to eq :item_needed
          expect(refused.args['items']).to eq 'Dagger'
        end

        it "should refuse a target with no weapon" do
          expect(needed('Runic Weapon', combatant(pc('Ally'))).code).to eq :item_none
        end

        it "should say every locale line a refusal needs" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          [ needed('Runic Weapon', combatant(ally)), needed('Runic Weapon', combatant(pc('Other'))) ].each do |refused|
            expect(t(refused.key, **CharState.symbolize(refused.args))).to_not match(/translation missing|\Apf2e\./i)
          end
        end
      end

      describe "the command" do
        def type(text, who)
          PF2EncounterCastCmd.new(@client, Command.new(text), Character[who.id]).on_command
        end

        before(:each) do
          allow_any_instance_of(PF2EncounterCastCmd).to receive(:spend_the_spell) do
            @spent = true
            nil
          end
        end

        it "should refuse before the spell is spent" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          type("e/cast runic weapon=#{ally.name}", @caster)

          expect(@spent).to be_nil
          expect(@client.failures.join).to include('Longsword', 'Dagger')
          expect(effects_on(ally)).to eq []
        end

        it "should cast it once the caster says which" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          type("e/cast runic weapon=#{ally.name}/longsword", @caster)

          expect(@client.failures).to eq []
          expect(@spent).to be true
          expect(strike(ally, 'Longsword').values_at('rune', 'striking')).to eq [ 1, 1 ]
        end
      end

      describe "what an item is asked to be" do
        it "should hold a spell to the items it can go on" do
          ally = pc('Ally', :in_hand => [ 'Longsword' ])

          expect(needed('Shillelagh', combatant(ally)).code).to eq :item_none
          expect(needed('Shillelagh', combatant(ally), [ 'longsword' ]).code).to eq :item_none
        end

        it "should find the club among what is in their hands" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Club' ])

          expect(needed('Shillelagh', combatant(ally))).to be_nil
        end

        it "should read whether a weapon is in hand, for a spell that asks" do
          ally = pc('Ally', :carried => [ 'Longsword' ])

          expect(needed('Weapon Surge', combatant(ally)).code).to eq :item_none
        end

        it "should read how a weapon reloads, for a spell that asks" do
          bow = pc('Bow', :in_hand => [ 'Hand Crossbow' ])
          sword = pc('Sword', :in_hand => [ 'Longsword' ])

          expect(needed('Helpful Reload', combatant(bow))).to be_nil
          expect(needed('Helpful Reload', combatant(sword)).code).to eq :item_none
        end

        # Every spell a caster can reach this way has to be castable with something a character can hold,
        # or its refusal would stop it being cast at all.
        it "should leave every such spell castable" do
          ally = pc('Ally', :in_hand => [ 'Club' ], :carried => [ 'Hand Crossbow', 'Staff' ])
          holder = combatant(ally).holder

          spells = ActiveEffects.catalogue.keys.select { |name| name.start_with?('Spell Effect: ') }.select do |name|
            Rules.choice_sets(Effects.source(name, Array(ActiveEffects.info(name)['rules'])))
                 .any? { |set| set['owned'] }
          end

          expect(spells).to_not be_empty

          stuck = spells.reject do |name|
            Rules.choice_sets(Effects.source(name, Array(ActiveEffects.info(name)['rules'])))
                 .select { |set| set['owned'] }.all? { |set| Choices.offer(set, holder).any? }
          end

          expect(stuck).to eq []
        end
      end

      describe "spells it does not refuse" do
        it "should leave a spell that resolves by its attack alone" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          expect(needed('Hand of the Apprentice', combatant(ally))).to be_nil
        end

        it "should leave a spell that resolves by its save alone" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          expect(needed('Draw the Lightning', combatant(ally))).to be_nil
        end

        it "should leave a spell that asks nothing about an item" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          expect(needed('Heroism', combatant(ally))).to be_nil
          expect(needed('Resist Energy', combatant(ally))).to be_nil
        end

        it "should leave a creature, which carries nothing" do
          allow(Combatants).to receive(:trusted?).and_return(true)
          PF2EncounterAddCmd.new(@client, Command.new('e/add goblin warrior'), Character[@gm.id]).on_command

          goblin = Combatants.find(fight, '#2').state

          expect(needed('Runic Weapon', goblin)).to be_nil
          expect { cast('Runic Weapon', goblin) }.to_not raise_error
        end

        # Runic Impression asks for a weapon only of someone who said it goes on one.
        it "should ask for an item only when the effect's other answers call for it" do
          ally = pc('Ally', :in_hand => [ 'Longsword', 'Dagger' ])

          expect(needed('Runic Impression', combatant(ally), [ 'unarmed', 'flaming' ])).to be_nil
          expect(needed('Runic Impression', combatant(ally), [ 'weapon', 'flaming' ]).code).to eq :item_needed
          expect(needed('Runic Impression', combatant(ally), [ 'weapon', 'flaming', 'dagger' ])).to be_nil
        end
      end

      describe "an answer that is not an item" do
        it "should reach the effect" do
          ally = pc('Ally')

          cast('Resist Energy', combatant(ally), [ 'fire' ])

          effect = effects_on(ally).first
          built = ActiveEffects.answered(combatant(ally).holder, effect)

          expect(effect.name).to eq 'Spell Effect: Resist Energy'
          expect(built['item']['flags']['system']['rulesSelections'].values).to include 'fire'
        end

        it "should reach the effect alongside its rank" do
          ally = pc('Ally')

          cast('Resist Energy', combatant(ally), [ 'fire', 'rank 4' ])

          expect(effects_on(ally).first.level).to eq 4
        end
      end
    end
  end
end
