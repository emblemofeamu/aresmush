require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement
      describe Raises do

        ABILITIES = %w(Strength Dexterity Constitution Intelligence Wisdom Charisma).freeze

        def config
          ConfigView.fixture(
            'pf2e' => {
              'prof_progression' => %w(untrained trained expert master legendary),
              'min_level_for_prof' => [ 1, 1, 3, 7, 15 ]
            },
            'pf2e_skills' => {
              'Acrobatics' => {}, 'Arcana' => {}, 'Stealth' => {}, 'Khazadi Lore' => {}
            }
          )
        end

        def state(to_assign:, level: 6, skills: {}, lores: {}, scores: {}, advancement: {})
          CharState.build(
            {
              'to_assign' => to_assign,
              'advancement' => advancement,
              'level' => level,
              'abilities' => ABILITIES,
              'ability_scores' => { 'Intelligence' => 10 }.merge(scores)
            },
            :sheet => { 'skills' => skills, 'lores' => lores },
            :config => config
          )
        end

        describe "ability boosts" do
          def boost_state(slots: Array.new(4, 'open'), scores: {})
            state(:to_assign => { 'raise ability' => slots }, :scores => scores)
          end

          it "should take all four boosts at once" do
            result = Raises.set(boost_state, 'type' => 'ability', 'value' => 'Strength, Dexterity, Wisdom, Charisma')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise ability']).to eq %w(Charisma Dexterity Strength Wisdom)
            expect(result.state['advancement']['raise ability']).to eq %w(Charisma Dexterity Strength Wisdom)
          end

          it "should refuse fewer than four" do
            result = Raises.set(boost_state, 'type' => 'ability', 'value' => 'Strength, Dexterity')

            expect(result.code).to eq :boost_count
          end

          it "should refuse the same ability twice" do
            result = Raises.set(boost_state, 'type' => 'ability', 'value' => 'Strength, Strength, Wisdom, Charisma')

            expect(result.code).to eq :boost_unique
          end

          it "should refuse an ability that is not one of the six" do
            result = Raises.set(boost_state, 'type' => 'ability', 'value' => 'Luck, Dexterity, Wisdom, Charisma')

            expect(result.code).to eq :bad_option
          end

          it "should refuse an ability already boosted at this level" do
            slots = [ 'Strength', 'open', 'open', 'open' ]
            result = Raises.set(state(:to_assign => { 'raise ability' => slots }), 'type' => 'ability', 'value' => 'Strength, Dexterity, Wisdom, Charisma')

            expect(result.code).to eq :no_free
          end

          # Raising Intelligence past an even score moves the modifier, and PF2e hands out a
          # skill and a language when it does.
          it "should hand out a skill and a language when the Intelligence modifier moves" do
            result = Raises.set(boost_state(:scores => { 'Intelligence' => 12 }), 'type' => 'ability', 'value' => 'Intelligence, Dexterity, Wisdom, Charisma')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise skill']).to eq [ 'open untrained' ]
            expect(result.state['to_assign']['open languages']).to eq [ 'open' ]
            expect(result.messages.last['key']).to eq 'pf2e.adv_int_mod_bonus'
          end

          # At 18 and above a boost is worth 1 rather than 2, so 18 -> 19 leaves the
          # modifier where it was and nothing extra is owed.
          it "should not hand anything out when the modifier does not move" do
            result = Raises.set(boost_state(:scores => { 'Intelligence' => 18 }), 'type' => 'ability', 'value' => 'Intelligence, Dexterity, Wisdom, Charisma')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise skill']).to be_nil
            expect(result.state['to_assign']['open languages']).to be_nil
          end
        end

        describe "skill increases" do
          it "should spend an open slot on a named skill" do
            result = Raises.set(state(:to_assign => { 'raise skill' => [ 'open' ] }, :skills => { 'Arcana' => 'trained' }), 'type' => 'skill', 'value' => 'Arcana')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise skill']).to eq [ 'Arcana' ]
          end

          it "should refuse a skill the game does not have" do
            result = Raises.set(state(:to_assign => { 'raise skill' => [ 'open' ] }), 'type' => 'skill', 'value' => 'Basketweaving')

            expect(result.code).to eq :bad_skill
          end

          it "should refuse a raise the character is not high enough level for" do
            # Trained -> expert needs level 3, and this character is levelling into 3.
            result = Raises.set(state(:to_assign => { 'raise skill' => [ 'open' ] }, :level => 1, :skills => { 'Arcana' => 'trained' }), 'type' => 'skill', 'value' => 'Arcana')

            expect(result.code).to eq :not_minimum_level
            expect(result.args['level']).to eq 3
          end

          it "should refuse a trained skill for a slot reserved for untrained ones" do
            result = Raises.set(state(:to_assign => { 'raise skill' => [ 'open untrained' ] }, :skills => { 'Arcana' => 'trained' }), 'type' => 'skill', 'value' => 'Arcana')

            expect(result.code).to eq :untrained_only
          end

          it "should let an untrained skill take an untrained-only slot" do
            result = Raises.set(state(:to_assign => { 'raise skill' => [ 'open untrained' ] }), 'type' => 'skill', 'value' => 'Stealth')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise skill']).to eq [ 'Stealth' ]
          end

          it "should refuse a non-lore skill for a lore slot" do
            result = Raises.set(state(:to_assign => { 'raise skill' => [ 'open lore' ] }, :skills => { 'Arcana' => 'trained' }), 'type' => 'skill', 'value' => 'Arcana')

            expect(result.code).to eq :lore_required
          end

          it "should prefer the lore slot for a lore, leaving the general one open" do
            result = Raises.set(
              state(:to_assign => { 'raise skill' => [ 'open', 'open lore' ] }, :lores => { 'Khazadi Lore' => 'trained' }),
              'type' => 'skill', 'value' => 'Khazadi Lore'
            )

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise skill']).to eq [ 'open', 'Khazadi Lore' ]
          end

          # With nothing left open the slot is being re-picked, which replaces what is there
          # rather than failing - the same way the command has always behaved.
          it "should replace an already-chosen raise when nothing is open" do
            result = Raises.set(state(:to_assign => { 'raise skill' => [ 'Acrobatics' ] }, :skills => { 'Arcana' => 'trained' }), 'type' => 'skill', 'value' => 'Arcana')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise skill']).to eq 'Arcana'
          end

          it "should treat a bare open marker as an open slot" do
            result = Raises.set(state(:to_assign => { 'raise skill' => 'open' }, :skills => { 'Arcana' => 'trained' }), 'type' => 'skill', 'value' => 'Arcana')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise skill']).to eq [ 'Arcana' ]
          end
        end

        describe "restricted skill increases" do
          it "should accept one of the listed skills" do
            result = Raises.set(state(:to_assign => { 'raise skill choice' => [ 'Acrobatics', 'Stealth' ] }), 'type' => 'skill choice', 'value' => 'Stealth')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['raise skill choice']).to eq 'Stealth'
          end

          it "should refuse a skill that is not on the list" do
            result = Raises.set(state(:to_assign => { 'raise skill choice' => [ 'Acrobatics', 'Stealth' ] }), 'type' => 'skill choice', 'value' => 'Arcana')

            expect(result.code).to eq :bad_skill_choice
          end
        end

        it "should refuse a raise the level did not offer" do
          result = Raises.set(state(:to_assign => {}), 'type' => 'skill', 'value' => 'Arcana')

          expect(result.code).to eq :bad_option
        end

        it "should refuse a type that is not a raise at all" do
          result = Raises.set(state(:to_assign => { 'raise skill' => [ 'open' ] }), 'type' => 'morale', 'value' => 'Arcana')

          expect(result.code).to eq :bad_option
        end
      end
    end
  end
end
