require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Chargen
      describe Boosts do

        # A Khazad wizard partway through chargen: two free boosts, an ancestry slot that
        # may only be Constitution or Wisdom, and a class slot fixed to Intelligence.
        def state(overrides = {})
          data = {
            'baseinfo_locked' => true,
            'boosts' => {
              'free' => [ 'open', 'open' ],
              'ancestry' => [ 'open', [ 'Constitution', 'Wisdom' ] ],
              'charclass' => [ 'Intelligence' ]
            },
            'boosts_working' => {
              'free' => [ 'open', 'open' ],
              'ancestry' => [ 'open', [ 'Constitution', 'Wisdom' ] ],
              'charclass' => [ 'Intelligence' ]
            },
            'abilities' => [ 'Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma' ]
          }.merge(overrides)

          CharState.build(data, :config => ConfigView.fixture({}))
        end

        describe :set do
          it "should fill the first open slot" do
            result = Boosts.set(state, 'type' => 'free', 'ability' => 'Strength')

            expect(result.ok?).to be true
            expect(result.state['boosts_working']['free']).to eq [ 'Strength', 'open' ]
          end

          it "should prefer a constrained slot the ability fits over a plain open one" do
            result = Boosts.set(state, 'type' => 'ancestry', 'ability' => 'Wisdom')

            expect(result.state['boosts_working']['ancestry']).to eq [ 'open', 'Wisdom' ]
          end

          it "should use the open slot for an ability the constrained slot does not allow" do
            result = Boosts.set(state, 'type' => 'ancestry', 'ability' => 'Strength')

            expect(result.state['boosts_working']['ancestry']).to eq [ 'Strength', [ 'Constitution', 'Wisdom' ] ]
          end

          it "should reject an unknown boost type" do
            result = Boosts.set(state, 'type' => 'destiny', 'ability' => 'Strength')

            expect(result.code).to eq :bad_option
            expect(result.args['element']).to eq 'boost type'
          end

          it "should refuse before base info is locked" do
            result = Boosts.set(state('baseinfo_locked' => false), 'type' => 'free', 'ability' => 'Strength')

            expect(result.code).to eq :info_not_locked
            expect(result.key).to eq 'pf2e.lock_info_first'
          end

          it "should reject an ability the character does not have" do
            result = Boosts.set(state, 'type' => 'free', 'ability' => 'Panache')

            expect(result.code).to eq :bad_option
            expect(result.args['element']).to eq 'abilities'
          end

          it "should refuse a duplicate within the same boost type" do
            once = Boosts.set(state, 'type' => 'free', 'ability' => 'Strength')
            twice = Boosts.set(once.state, 'type' => 'free', 'ability' => 'Strength')

            expect(twice.code).to eq :no_duplicate_boosts
          end

          it "should refuse when the type has no slot left" do
            result = Boosts.set(state, 'type' => 'charclass', 'ability' => 'Wisdom')

            expect(result.code).to eq :no_free
            expect(result.args['element']).to eq 'charclass'
          end

          it "should report the assignment to the player" do
            result = Boosts.set(state, 'type' => 'free', 'ability' => 'Strength')

            expect(result.messages.first['key']).to eq 'pf2e.assignment_ok'
            expect(result.messages.first['args']['value']).to eq 'Strength'
          end

          it "should not mutate the state it was given" do
            original = state
            Boosts.set(original, 'type' => 'free', 'ability' => 'Strength')

            expect(original['boosts_working']['free']).to eq [ 'open', 'open' ]
          end
        end

        describe :unset do
          it "should put the slot back to the template value it started from" do
            assigned = Boosts.set(state, 'type' => 'free', 'ability' => 'Strength')
            result = Boosts.unset(assigned.state, 'type' => 'free', 'ability' => 'Strength')

            expect(result.ok?).to be true
            expect(result.state['boosts_working']['free']).to eq [ 'open', 'open' ]
          end

          it "should restore a constrained slot to its list of options, not to open" do
            assigned = Boosts.set(state, 'type' => 'ancestry', 'ability' => 'Wisdom')
            result = Boosts.unset(assigned.state, 'type' => 'ancestry', 'ability' => 'Wisdom')

            expect(result.state['boosts_working']['ancestry']).to eq [ 'open', [ 'Constitution', 'Wisdom' ] ]
          end

          it "should refuse to unset a slot the template fixes to one ability" do
            result = Boosts.unset(state, 'type' => 'charclass', 'ability' => 'Intelligence')

            expect(result.code).to eq :element_locked
            expect(result.key).to eq 'pf2e.element_cglocked'
          end

          it "should refuse when that ability is not assigned to that type" do
            result = Boosts.unset(state, 'type' => 'free', 'ability' => 'Charisma')

            expect(result.code).to eq :boost_not_set
            expect(result.key).to eq 'pf2e.boost_not_assigned'
          end

          it "should report the reset to the player" do
            assigned = Boosts.set(state, 'type' => 'free', 'ability' => 'Strength')
            result = Boosts.unset(assigned.state, 'type' => 'free', 'ability' => 'Strength')

            expect(result.messages.first['key']).to eq 'pf2e.reset_ok'
            expect(result.messages.first['args']['element']).to eq 'free boost'
          end
        end
      end
    end
  end
end
