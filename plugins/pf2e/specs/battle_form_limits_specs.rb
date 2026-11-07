require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # What a battle form takes away. Unless it says otherwise, someone in one can't cast spells or use most
    # manipulate actions that need hands, and their gear is absorbed into them. The GM decides any doubt, so
    # the encounter's GM can add `/force`.
    describe "the limits of a battle form", :dbtest => true do
      include FightBench

      BEAR_FORM = 'Spell Effect: Animal Form (Bear)'.freeze
      DRAGON_FORM = 'Spell Effect: Dragon Form'.freeze

      before(:each) do
        bench!(level: 10)
        add('goblin warrior')
        turn_to(@hero.name)
        @spent = 0
        allow_any_instance_of(PF2EncounterCastCmd).to receive(:spend_the_spell) do
          @spent += 1
          { 'spell name' => 'Fear', 'spell level' => '1', 'tradition' => 'primal' }
        end
      end

      after(:each) { clear_bench! }

      def goblin_number
        Combatants.all(encounter).find { |one| one.label != @hero.name }.number
      end

      def in_form(name, options = [ 'rank 5' ])
        ActiveEffects.apply(hero, name, :options => options, :encounter => encounter)
      end

      def gm_has_hero(text)
        typed(PF2EncounterAsCmd, "e/as #{@hero.name}=#{text}", @gm, FightBench::HITS)
      end

      describe "casting" do
        before(:each) { in_form(BEAR_FORM) }

        it "should be refused before the spell is spent" do
          hero_types("e/cast fear=##{goblin_number}")

          expect(refused.join).to include 'battle form', 'dismiss'
          expect(@spent).to eq 0
        end

        it "should go ahead on the GM's word" do
          gm_has_hero("cast fear=##{goblin_number}/force")

          expect(refused.join).to_not include 'battle form'
          expect(@spent).to eq 1
        end

        it "should not take a player's word for it" do
          hero_types("e/cast fear=##{goblin_number}/force")

          expect(refused.join).to include 'battle form'
          expect(@spent).to eq 0
        end

        it "should be allowed again once the form is over" do
          ActiveEffects.remove_named(hero, BEAR_FORM)

          hero_types("e/cast fear=##{goblin_number}")

          expect(refused.join).to_not include 'battle form'
          expect(@spent).to eq 1
        end
      end

      describe "actions that need hands" do
        it "should be refused in a form without them" do
          in_form(BEAR_FORM)

          hero_types('e/act interact')

          expect(refused.join).to include 'hands', 'Interact'
        end

        it "should go ahead on the GM's word" do
          in_form(BEAR_FORM)

          gm_has_hero('act interact/force')

          expect(refused).to eq []
        end

        it "should work outside a form" do
          hero_types('e/act interact')

          expect(refused).to eq []
        end

        it "should work in a form whose data gives it hands" do
          in_form(DRAGON_FORM, [ 'rank 6', 'forest dragon' ])

          hero_types('e/act interact')

          expect(refused).to eq []
        end

        it "should work in a form whose spell text gives it hands" do
          in_form('Spell Effect: Elemental Form', [ 'rank 5', 'air' ])

          hero_types('e/act interact')

          expect(refused).to eq []
        end

        it "should leave actions that don't need them alone" do
          in_form(BEAR_FORM)

          hero_types('e/act dismiss/animal form')

          expect(refused).to eq []
          expect(BattleForms.active?(hero)).to be false
        end
      end

      describe "gear" do
        it "should keep a shield from being raised, even in a form with hands" do
          in_form(DRAGON_FORM, [ 'rank 6', 'forest dragon' ])

          hero_types('e/act raise a shield')

          expect(refused.join).to include 'absorbed'
        end

        it "should refuse using, drawing, and stowing an item" do
          in_form(BEAR_FORM)

          [ 'e/use consumables=1', 'e/equip weapons=1', 'e/unequip weapons=1' ].each do |text|
            hero_types(text)

            expect(refused.join).to include 'absorbed'
          end
        end

        it "should let them use it again once the form is over" do
          in_form(BEAR_FORM)
          ActiveEffects.remove_named(hero, BEAR_FORM)

          hero_types('e/equip weapons=1')

          expect(refused.join).to_not include 'absorbed'
        end
      end

      describe "a form that lists no attacks" do
        before(:each) { in_form('Spell Effect: Pest Form', [ 'rank 1' ]) }

        it "should leave them with no attacks" do
          expect(Actors.of(hero).attacks).to eq []
        end

        it "should refuse a Strike and say why" do
          hero_types("e/strike ##{goblin_number}=fist")

          expect(refused.join).to include "can't make Strikes"
        end

        it "should say so on the combat sheet" do
          @client.said.clear
          run(PF2EncounterCombatSheetCmd, 'e/csheet', @hero)

          expect(heard).to include t('pf2e.csheet_no_strikes', :source => 'Pest Form')
          expect(heard).to_not include 'Fist:'
        end
      end

      it "should hold for a creature, without breaking what it can do outside one" do
        goblin = Combatants.all(encounter).find { |one| one.label != @hero.name }

        as(goblin.number, 'act interact')
        expect(refused).to eq []

        ActiveEffects.apply(goblin.holder, BEAR_FORM, :options => [ 'rank 5' ], :encounter => encounter)

        as(goblin.number, 'act interact')
        expect(refused.join).to include 'hands'
      end
    end
  end
end
