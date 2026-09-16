require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Chargen
      describe Skills do

        def config
          ConfigView.fixture(
            'pf2e' => { 'hidden_options' => [] },
            'pf2e_skills' => {
              'Arcana' => { 'key_abil' => 'Intelligence' },
              'Crafting' => { 'key_abil' => 'Intelligence' },
              'Religion' => { 'key_abil' => 'Wisdom' },
              'Stealth' => { 'key_abil' => 'Dexterity' },
              'Khazadi Lore' => { 'key_abil' => 'Intelligence' }
            }
          )
        end

        def state(to_assign = {}, trained = {}, cg_skills = [])
          CharState.build(
            { 'to_assign' => to_assign, 'cg_skills' => cg_skills },
            :sheet => { 'skills' => trained },
            :config => config
          )
        end

        describe :train do
          it "should fill an open free slot" do
            result = Skills.train(state('open skills' => [ 'open', 'open' ]), 'type' => 'free', 'skill' => 'Arcana')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['open skills']).to eq [ 'Arcana', 'open' ]
            expect(result.grants.first['kind']).to eq 'raise_skill'
            expect(result.grants.first['payload']).to include('skill' => 'Arcana', 'to' => 'trained')
          end

          it "should reject an unknown skill type" do
            result = Skills.train(state, 'type' => 'wishes', 'skill' => 'Arcana')

            expect(result.code).to eq :bad_option
            expect(result.args['element']).to eq 'skill type'
          end

          it "should reject a skill that is not in the game" do
            result = Skills.train(state('open skills' => [ 'open' ]), 'type' => 'free', 'skill' => 'Jousting')

            expect(result.code).to eq :bad_skill
            expect(result.key).to eq 'pf2e.bad_option_condensedskill'
          end

          it "should refuse a type the character has nothing to assign for" do
            result = Skills.train(state, 'type' => 'free', 'skill' => 'Arcana')

            expect(result.code).to eq :cannot_assign
          end

          it "should refuse when every free slot is spent" do
            result = Skills.train(state('open skills' => [ 'Crafting' ]), 'type' => 'free', 'skill' => 'Arcana')

            expect(result.code).to eq :no_free
          end

          it "should take a background skill from its list of choices" do
            result = Skills.train(state('bgskill' => [ 'Religion', 'Crafting' ]), 'type' => 'background', 'skill' => 'Religion')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['bgskill']).to eq 'Religion'
          end

          it "should refuse a background skill outside its list" do
            result = Skills.train(state('bgskill' => [ 'Religion' ]), 'type' => 'background', 'skill' => 'Stealth')

            expect(result.code).to eq :bad_option
            expect(result.args['element']).to eq 'skill option'
          end

          it "should record a class skill choice as selected" do
            to_assign = { 'class skill choice' => { 'options' => [ 'Arcana', 'Crafting' ], 'selected' => 'open' } }
            result = Skills.train(state(to_assign), 'type' => 'classchoice', 'skill' => 'Crafting')

            expect(result.state['to_assign']['class skill choice']['selected']).to eq 'Crafting'
          end

          it "should refuse a class skill choice that is already made" do
            to_assign = { 'class skill choice' => { 'options' => [ 'Arcana', 'Crafting' ], 'selected' => 'Arcana' } }
            result = Skills.train(state(to_assign), 'type' => 'classchoice', 'skill' => 'Crafting')

            expect(result.code).to eq :no_free
          end

          it "should refuse a skill the character is already trained in" do
            result = Skills.train(state({ 'open skills' => [ 'open' ] }, { 'Arcana' => 'trained' }), 'type' => 'free', 'skill' => 'Arcana')

            expect(result.code).to eq :already_has_skill
          end

          # The PF2e rule: a background or class skill the character already has becomes a
          # free skill of their choice instead of being wasted.
          it "should turn a duplicate class choice into an extra free skill" do
            to_assign = { 'class skill choice' => { 'options' => [ 'Arcana' ], 'selected' => 'open' }, 'open skills' => [] }
            result = Skills.train(state(to_assign, { 'Arcana' => 'trained' }), 'type' => 'classchoice', 'skill' => 'Arcana')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['class skill choice']['duplicate']).to be true
            expect(result.state['to_assign']['open skills']).to eq [ 'open' ]
            expect(result.messages.first['key']).to eq 'pf2e.skill_choice_duplicate'
          end

          it "should not grant training twice for a duplicate choice" do
            to_assign = { 'class skill choice' => { 'options' => [ 'Arcana' ], 'selected' => 'open' }, 'open skills' => [] }
            result = Skills.train(state(to_assign, { 'Arcana' => 'trained' }), 'type' => 'classchoice', 'skill' => 'Arcana')

            expect(result.grants).to eq []
          end

          it "should not mutate the state it was given" do
            original = state('open skills' => [ 'open' ])
            Skills.train(original, 'type' => 'free', 'skill' => 'Arcana')

            expect(original['to_assign']['open skills']).to eq [ 'open' ]
          end
        end

        describe :untrain do
          it "should free the slot and revoke the training grant" do
            picked = Skills.train(state('open skills' => [ 'open' ]), 'type' => 'free', 'skill' => 'Arcana')
            result = Skills.untrain(picked.state.merge('sheet' => picked.state['sheet'].merge('skills' => { 'Arcana' => 'trained' })), 'type' => 'free', 'skill' => 'Arcana')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['open skills']).to eq [ 'open' ]
            expect(result.revocations.first['match']['skill']).to eq 'Arcana'
          end

          it "should refuse a skill the character does not have" do
            result = Skills.untrain(state('open skills' => [ 'open' ]), 'type' => 'free', 'skill' => 'Arcana')

            expect(result.code).to eq :does_not_have
          end

          it "should refuse a skill locked in by an earlier chargen stage" do
            result = Skills.untrain(state({ 'open skills' => [ 'Arcana' ] }, { 'Arcana' => 'trained' }, [ 'Arcana' ]), 'type' => 'free', 'skill' => 'Arcana')

            expect(result.code).to eq :element_locked
          end

          it "should hand a class choice back to open" do
            to_assign = { 'class skill choice' => { 'options' => [ 'Arcana' ], 'selected' => 'Arcana' } }
            result = Skills.untrain(state(to_assign, { 'Arcana' => 'trained' }), 'type' => 'classchoice', 'skill' => 'Arcana')

            expect(result.state['to_assign']['class skill choice']['selected']).to eq 'open'
          end

          it "should take back the extra free slot when undoing a duplicate choice" do
            to_assign = {
              'class skill choice' => { 'options' => [ 'Arcana' ], 'selected' => 'Arcana', 'duplicate' => true },
              'open skills' => [ 'open' ]
            }
            result = Skills.untrain(state(to_assign, { 'Arcana' => 'trained' }), 'type' => 'classchoice', 'skill' => 'Arcana')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['open skills']).to eq []
            expect(result.state['to_assign']['class skill choice']).to_not have_key 'duplicate'
          end

          it "should refuse to undo a duplicate choice whose free skill is already spent" do
            to_assign = {
              'class skill choice' => { 'options' => [ 'Arcana' ], 'selected' => 'Arcana', 'duplicate' => true },
              'open skills' => [ 'Stealth' ]
            }
            result = Skills.untrain(state(to_assign, { 'Arcana' => 'trained' }), 'type' => 'classchoice', 'skill' => 'Arcana')

            expect(result.code).to eq :free_skill_spent
          end
        end
      end
    end
  end
end
