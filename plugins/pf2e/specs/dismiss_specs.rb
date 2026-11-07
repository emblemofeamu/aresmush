require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Dismiss: one action that ends an effect which says it can be dismissed, for whoever it says may.
    describe "dismissing an effect", :dbtest => true do
      include FightBench

      PEST = 'Spell Effect: Pest Form'.freeze
      UNTAMED = 'Spell Effect: Untamed Form'.freeze
      VAPOR = 'Spell Effect: Vapor Form'.freeze

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

      def under(holder, name, by = @hero.name, **options)
        ActiveEffects.apply(holder, name, :applied_by => by, :encounter => encounter, **options).state
      end

      def held_by(holder)
        ActiveEffects.on(holder.class[holder.id]).map(&:name)
      end

      def actions_used
        TurnState.turn(hero)['actions'].to_i
      end

      it "should spend an action, end the effect, and tell the room" do
        under(hero, PEST)
        before = actions_used

        hero_types('e/act dismiss/pest form')

        expect(refused).to eq []
        expect(held_by(hero)).to_not include PEST
        expect(BattleForms.active?(hero)).to be false
        expect(actions_used).to eq before + 1
        expect(heard).to include 'dismisses Pest Form'
      end

      it "should ask for a name, and spend nothing, even with only one to dismiss" do
        under(hero, PEST)
        before = actions_used

        hero_types('e/act dismiss')

        expect(refused.join).to include 'Pest Form'
        expect(held_by(hero)).to include PEST
        expect(actions_used).to eq before
      end

      it "should refuse someone with nothing to dismiss" do
        hero_types('e/act dismiss')

        expect(refused.join).to include 'nothing to dismiss'
      end

      it "should refuse an effect that can't be dismissed, and spend nothing" do
        under(hero, 'Effect: Alloy Flesh and Steel')
        before = actions_used

        hero_types('e/act dismiss/alloy flesh')

        expect(refused.join).to include "can't be dismissed"
        expect(actions_used).to eq before
      end

      it "should refuse someone else's effect" do
        under(goblin.holder, PEST, goblin.label)

        hero_types('e/act dismiss/pest form')

        expect(refused.join).to include "isn't"
        expect(held_by(goblin.holder)).to include PEST
      end

      it "should refuse a name nothing here goes by" do
        under(hero, PEST)

        hero_types('e/act dismiss/heroism')

        expect(refused.join).to include 'heroism'
      end

      it "should end the effect on everyone the caster put it on" do
        under(hero, PEST)
        under(goblin.holder, PEST)

        hero_types('e/act dismiss/pest form')

        expect(held_by(hero)).to_not include PEST
        expect(held_by(goblin.holder)).to_not include PEST
      end

      it "should cover every shape of a family" do
        under(hero, 'Spell Effect: Animal Form (Bear)')

        hero_types('e/act dismiss/animal form')

        expect(refused).to eq []
        expect(held_by(hero)).to eq []
      end

      describe "an effect its holder may dismiss" do
        it "should be theirs, whoever cast it" do
          under(hero, VAPOR, goblin.label)

          hero_types('e/act dismiss/vapor form')

          expect(refused).to eq []
          expect(held_by(hero)).to_not include VAPOR
        end

        it "should end only on them" do
          under(hero, VAPOR)
          under(goblin.holder, VAPOR)

          hero_types('e/act dismiss/vapor form')

          expect(held_by(hero)).to_not include VAPOR
          expect(held_by(goblin.holder)).to include VAPOR
        end

        it "should not be the caster's to end on someone else" do
          under(goblin.holder, VAPOR)

          hero_types('e/act dismiss/vapor form')

          expect(refused.join).to include "isn't"
          expect(held_by(goblin.holder)).to include VAPOR
        end
      end

      describe "an effect a GM added" do
        before(:each) { under(hero, PEST, @gm.name) }

        it "should be the holder's to dismiss, and the room should hear a GM added it" do
          hero_types('e/act dismiss/pest form')

          expect(refused).to eq []
          expect(held_by(hero)).to_not include PEST
          expect(heard).to include 'which a GM added', 'e/undo'
        end

        it "should come back with e/undo" do
          before = actions_used

          hero_types('e/act dismiss/pest form')
          run(Pf2e.get_cmd_handler(@client, Command.new('e/undo'), Character[@gm.id]), 'e/undo')

          expect(held_by(hero)).to include PEST
          expect(BattleForms.active?(hero)).to be true
          expect(actions_used).to eq before
        end
      end

      describe "an effect that came with another" do
        before(:each) do
          under(hero, UNTAMED)
          under(hero, 'Spell Effect: Animal Form (Bear)', :granted_by => UNTAMED)
        end

        it "should end with what brought it" do
          hero_types('e/act dismiss/untamed form')

          expect(refused).to eq []
          expect(held_by(hero)).to eq []
        end

        it "should say which effect to dismiss instead" do
          hero_types('e/act dismiss/animal form')

          expect(refused.join).to include 'Untamed Form'
          expect(held_by(hero)).to include UNTAMED
        end
      end

      it "should be something a GM does for a creature, spending its action" do
        under(goblin.holder, PEST, goblin.label)
        turn_to(goblin.label)

        as(goblin.number, 'act dismiss/pest form')

        expect(refused).to eq []
        expect(held_by(goblin.holder)).to_not include PEST
        expect(TurnState.turn(goblin.holder)['actions'].to_i).to eq 1
      end

      # Untamed Form's text here leaves it out, and Form Control and Perfect Form Control both say it can be.
      describe "the table" do
        FROM_ELSEWHERE = [ UNTAMED ].freeze

        def spells
          Global.config_reader.config.select { |name, _| name.start_with?('pf2e_spells') }.values
                .flat_map { |file| spell_rows(file) }.to_h
        end

        def spell_rows(rows)
          rows.flat_map do |name, info|
            next [] unless info.is_a?(Hash)

            info.key?('base_level') || info.key?('effect') ? [ [ name, info ] ] : spell_rows(info)
          end
        end

        def says_dismiss?(info)
          info.to_s.match?(/\bcan dismiss\b/i)
        end

        def effects_of(spell)
          ActiveEffects.catalogue.keys.select do |name|
            name == "Spell Effect: #{spell}" || name.start_with?("Spell Effect: #{spell} (")
          end
        end

        it "should list every effect whose spell says it can be dismissed" do
          missing = spells.select { |_name, info| says_dismiss?(info) }.keys
                          .flat_map { |name| effects_of(name) }
                          .reject { |effect| Dismissing.who(effect) }

          expect(missing).to eq []
        end

        it "should list only spells that say so" do
          listed = (Global.read_config('pf2e_dismissible') || {}).keys
                                                                .select { |name| name.start_with?('Spell Effect: ') }

          unsaid = (listed - FROM_ELSEWHERE).reject { |name| says_dismiss?(spells[name.sub('Spell Effect: ', '')]) }

          expect(unsaid).to eq []
        end

        it "should name only effects that exist, as caster or holder" do
          (Global.read_config('pf2e_dismissible') || {}).each do |name, who|
            expect(ActiveEffects.catalogue.keys.any? { |one| one == name || one.start_with?("#{name} (") }).to be(true), name
            expect(%w{caster holder}).to include who
          end
        end
      end
    end
  end
end
