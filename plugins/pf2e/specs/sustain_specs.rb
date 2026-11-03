require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Sustain: one action that carries an effect the actor put in place through the end of their next
    # turn, and everything that came with it.
    describe "sustaining an effect", :dbtest => true do
      include FightBench

      ALLOY = 'Effect: Alloy Flesh and Steel'.freeze

      before(:each) do
        bench!(level: 5)
        add('goblin warrior')
        turn_to(@hero.name)
        @client.said.clear
      end

      after(:each) { clear_bench! }

      def goblin
        Combatants.all(encounter).find { |one| one.label != @hero.name }
      end

      def under(holder, name, by = @hero.name)
        ActiveEffects.apply(holder, name, :applied_by => by, :encounter => encounter).state
      end

      def held_by(holder)
        ActiveEffects.on(holder.class[holder.id]).map(&:name)
      end

      def actions_used
        TurnState.turn(hero)['actions'].to_i
      end

      # Past the end of the hero's turn, and round to their next one.
      def to_their_next_turn
        next_turn
        turn_to(@hero.name)
      end

      it "should spend an action and keep the effect through the end of the actor's next turn" do
        under(hero, ALLOY)
        to_their_next_turn
        before = actions_used

        hero_types('e/act sustain/alloy flesh')

        expect(refused).to eq []
        expect(actions_used).to eq before + 1
        expect(heard).to include 'sustains Alloy Flesh and Steel'

        next_turn
        expect(held_by(hero)).to include ALLOY

        turn_to(@hero.name)
        next_turn
        expect(held_by(hero)).to_not include ALLOY
      end

      it "should end the effect if nobody sustains it" do
        under(hero, ALLOY)
        to_their_next_turn
        next_turn

        expect(held_by(hero)).to_not include ALLOY
      end

      it "should take the only sustained effect when none is named" do
        under(hero, ALLOY)
        to_their_next_turn

        hero_types('e/act sustain')
        next_turn

        expect(refused).to eq []
        expect(held_by(hero)).to include ALLOY
      end

      it "should ask which when there are several, and spend nothing" do
        under(hero, ALLOY)
        under(hero, 'Effect: Tidal Shield')
        before = actions_used

        hero_types('e/act sustain')

        expect(refused.join).to include 'Alloy Flesh and Steel', 'Tidal Shield'
        expect(actions_used).to eq before
      end

      it "should refuse someone with nothing to sustain, and spend nothing" do
        before = actions_used

        hero_types('e/act sustain')

        expect(refused.join).to include 'nothing to sustain'
        expect(actions_used).to eq before
      end

      it "should refuse an effect the actor is not sustaining, and spend nothing" do
        under(hero, ALLOY)
        before = actions_used

        hero_types('e/act sustain/tidal shield')

        expect(refused.join).to include 'Alloy Flesh and Steel'
        expect(actions_used).to eq before
      end

      it "should not sustain someone else's effect" do
        under(hero, ALLOY, goblin.label)

        hero_types('e/act sustain')

        expect(refused.join).to include 'nothing to sustain'
      end

      it "should extend nothing by being sustained again in the same turn, and say so" do
        under(hero, ALLOY)
        to_their_next_turn

        hero_types('e/act sustain/alloy flesh')
        before = actions_used
        hero_types('e/act sustain/alloy flesh')

        expect(heard).to include 'no further'
        expect(actions_used).to eq before + 1

        next_turn
        turn_to(@hero.name)
        next_turn
        expect(held_by(hero)).to_not include ALLOY
      end

      it "should keep the effect on everyone it was cast on" do
        under(hero, ALLOY)
        under(goblin.holder, ALLOY)
        to_their_next_turn

        hero_types('e/act sustain/alloy flesh')
        next_turn

        expect(held_by(hero)).to include ALLOY
        expect(held_by(goblin.holder)).to include ALLOY
      end

      it "should keep what an aura put on others along with the aura" do
        under(hero, 'Aura: Protective Wards')
        Auras.enter(hero, goblin.holder, 'protective-ward', 'ally')
        to_their_next_turn

        hero_types('e/act sustain/protective wards')
        next_turn

        expect(refused).to eq []
        expect(held_by(hero)).to include 'Aura: Protective Wards'
        expect(held_by(goblin.holder)).to include 'Spell Effect: Protective Wards'
      end

      it "should be something a GM does for a creature" do
        under(goblin.holder, ALLOY, goblin.label)
        turn_to(goblin.label)

        as(goblin.number, 'act sustain/alloy flesh')
        next_turn

        expect(refused).to eq []
        expect(held_by(goblin.holder)).to include ALLOY
      end

      it "should be taken back by e/undo" do
        effect = under(hero, ALLOY)
        to_their_next_turn
        round = Pf2eEffect[effect.id].sustained_round
        before = actions_used

        hero_types('e/act sustain/alloy flesh')
        expect(Pf2eEffect[effect.id].sustained_round).to_not eq round

        run(Pf2e.get_cmd_handler(@client, Command.new('e/undo'), Character[@gm.id]), 'e/undo')

        expect(Pf2eEffect[effect.id].sustained_round).to eq round
        expect(actions_used).to eq before
      end
    end
  end
end
