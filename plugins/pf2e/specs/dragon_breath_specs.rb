require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # A dragon's breath in three hands: a caster in Dragon Form, a Dragon Instinct barbarian, and a draconic
    # sorcerer's focus spell. Each takes the dragon's damage and rolls the target's save against a DC.
    describe "breathing as a dragon", :dbtest => true do
      include FightBench

      FORM = 'Spell Effect: Dragon Form'.freeze
      RAGE = 'Effect: Rage'.freeze

      before(:each) do
        bench!(level: 12, hp: 200)
        add('goblin warrior')
        turn_to(@hero.name)
        @client.said.clear
      end

      after(:each) { clear_bench! }

      def goblin
        Combatants.all(encounter).find { |one| one.label != @hero.name }
      end

      def goblin_hp
        goblin.holder.class[goblin.holder.id].hp_left.to_i
      end

      def actions_used
        TurnState.turn(hero)['actions'].to_i
      end

      def in_form(dragon, rank = 6)
        ActiveEffects.apply(hero, FORM, :options => [ "rank #{rank}", dragon, 'tradition primal' ], :encounter => encounter)
      end

      def caster_stats
        allow(DragonBreath).to receive(:caster_stats).and_return('spell_abil' => 'Wisdom', 'prof_level' => 'expert')
      end

      describe "in Dragon Form" do
        before(:each) { caster_stats }

        it "should spend two actions, roll the target's save, and deal the dragon's damage" do
          in_form('forest dragon')
          before = goblin_hp
          used = actions_used

          hero_types("e/act dragon breath=##{goblin.number}", FightBench::LOW)

          expect(refused).to eq []
          expect(actions_used).to eq used + 2
          expect(heard).to include 'Reflex', 'piercing', '30-foot cone'
          expect(goblin_hp).to be < before
        end

        it "should use the dragon's save, and its shape" do
          in_form('brine dragon')

          hero_types("e/act dragon breath=##{goblin.number}")

          expect(heard).to include 'bludgeoning', '100-foot line', 'Reflex'
        end

        it "should use a Fortitude save where the dragon's calls for one" do
          in_form('ossuary dragon')

          hero_types("e/act dragon breath=##{goblin.number}")

          expect(heard).to include 'void', 'Fortitude'
        end

        it "should deal 10d6 at 6th rank and 14d6 from 8th" do
          in_form('forest dragon')
          expect(DragonBreath.from_form(hero).state['formula']).to eq '10d6'

          ActiveEffects.remove_named(hero, FORM)
          in_form('forest dragon', 8)
          expect(DragonBreath.from_form(hero).state['formula']).to eq '14d6'
        end

        it "should reach everyone named, rolling its damage once" do
          add('goblin warrior')
          in_form('forest dragon')
          others = Combatants.all(encounter).reject { |one| one.label == @hero.name }

          hero_types("e/act dragon breath=#{others.map { |one| "##{one.number}" }.join(',')}", FightBench::LOW)

          expect(refused).to eq []
          expect(heard.scan('Reflex').size).to eq 2
        end

        it "should refuse someone not in the form" do
          hero_types("e/act dragon breath=##{goblin.number}")

          expect(refused.join).to_not eq ''
        end

        it "should refuse with no one in the area, spending nothing" do
          in_form('forest dragon')
          used = actions_used

          hero_types('e/act dragon breath')

          expect(refused.join).to include 'e/act'
          expect(actions_used).to eq used
        end

        it "should need 1d4 rounds before it can be used again" do
          in_form('forest dragon')

          hero_types("e/act dragon breath=##{goblin.number}")
          used = actions_used
          hero_types("e/act dragon breath=##{goblin.number}")

          expect(refused.join).to include 'again'
          expect(actions_used).to eq used

          encounter.update(:round => encounter.round.to_i + 4)
          hero_types("e/act dragon breath=##{goblin.number}")

          expect(refused).to eq []
        end

        it "should come back with e/undo" do
          in_form('forest dragon')
          before = goblin_hp

          hero_types("e/act dragon breath=##{goblin.number}", FightBench::LOW)
          run(Pf2e.get_cmd_handler(@client, Command.new('e/undo'), Character[@gm.id]), 'e/undo')

          expect(goblin_hp).to eq before
          hero_types("e/act dragon breath=##{goblin.number}")
          expect(refused).to eq []
        end
      end

      it "should ask for a DC from a caster the game can't work one out for" do
        in_form('forest dragon')
        allow(DragonBreath).to receive(:caster_stats).and_return(nil)

        hero_types("e/act dragon breath=##{goblin.number}")
        expect(refused.join).to include 'DC'

        hero_types("e/act dragon breath=##{goblin.number}/25")
        expect(refused).to eq []
        expect(heard).to include 'DC 25'
      end

      describe "Dragon's Rage Breath" do
        before(:each) do
          @hero.update(:pf2_feats => { 'charclass' => [ "Dragon's Rage Breath" ] },
                       :pf2_base_info => { 'charclass' => 'Barbarian', 'specialize' => 'Dragon', 'specialize_info' => 'Brine' })
        end

        it "should use their instinct's damage, with a level's worth of dice, while raging" do
          ActiveEffects.apply(hero, RAGE, :encounter => encounter)
          before = goblin_hp
          used = actions_used

          expect(DragonBreath.from_rage(hero).state['formula']).to eq '12d6'

          hero_types("e/act dragon's rage breath=##{goblin.number}", FightBench::LOW)

          expect(refused).to eq []
          expect(actions_used).to eq used + 2
          expect(heard).to include 'bludgeoning', 'Reflex', '30-foot cone'
          expect(goblin_hp).to be < before
        end

        it "should only work while raging" do
          hero_types("e/act dragon's rage breath=##{goblin.number}")

          expect(refused.join).to include 'rag'
        end

        it "should not belong to someone without the feat" do
          @hero.update(:pf2_feats => {})
          ActiveEffects.apply(hero, RAGE, :encounter => encounter)

          hero_types("e/act dragon's rage breath=##{goblin.number}")

          expect(refused.join).to_not eq ''
        end
      end

      describe "the Dragon Breath spell" do
        before(:each) do
          allow_any_instance_of(PF2EncounterCastCmd).to receive(:spend_the_spell)
            .and_return('spell name' => 'Dragon Breath', 'spell level' => '6', 'spell_abil' => 'Charisma', 'prof_level' => 'expert')
        end

        def sorcerer(dragon)
          @hero.update(:pf2_base_info => { 'charclass' => 'Sorcerer', 'specialize' => 'Draconic', 'specialize_info' => dragon })
        end

        it "should deal their dragon's damage from Ea's table" do
          sorcerer('Ossuary')

          hero_types("e/cast dragon breath=##{goblin.number}/focus", FightBench::LOW)

          expect(refused).to eq []
          expect(heard).to include 'void', 'Reflex'
        end

        it "should say untyped for someone with no dragon" do
          mechanics = Acting.spell_mechanics('Dragon Breath').last

          expect(DragonBreath.typed(hero, 'Dragon Breath', mechanics)).to eq mechanics
        end

        it "should leave other spells alone" do
          sorcerer('Terra')
          mechanics = Acting.spell_mechanics('Fear').last

          expect(DragonBreath.typed(hero, 'Fear', mechanics)).to eq mechanics
        end
      end
    end
  end
end
