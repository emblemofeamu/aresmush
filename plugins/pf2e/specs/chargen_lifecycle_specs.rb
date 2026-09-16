require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Chargen
      describe Lifecycle do

        def config
          ConfigView.fixture(
            'pf2e' => { 'subclass_names' => { 'Wizard' => 'Thesis', 'Champion' => 'Cause', 'Cleric' => 'Doctrine' } },
            'pf2e_class' => {
              'Wizard' => {},
              'Fighter' => {},
              'Cleric' => { 'use_deity' => true },
              'Champion' => { 'use_deity' => true, 'allowed_sanctifications' => [ 'Holy', 'Unsanctified' ] }
            },
            'pf2e_specialty' => {
              'Wizard' => { 'Department of Mana Syntaxia' => { 'choose' => { 'options' => { 'Spell Substitution' => {} } } } },
              'Cleric' => { 'Cloistered' => {} },
              'Champion' => { 'Beacon' => { 'allowed_sanctifications' => [ 'Holy' ] } }
            },
            'pf2e_background' => { 'Acolyte' => {}, 'Blessed' => { 'needs_deity' => true } },
            'pf2e_deities' => { 'Althea' => { 'allowed_sanctifications' => [ 'Holy' ] } }
          )
        end

        def state(base_info = {}, faith = {}, checkpoint = 'start', chargen_stage = 4)
          CharState.build(
            { 'base_info' => base_info, 'faith' => faith, 'checkpoint' => checkpoint, 'chargen_stage' => chargen_stage },
            :config => config
          )
        end

        def complete_wizard
          state(
            { 'ancestry' => 'Khazad', 'heritage' => 'Forge', 'background' => 'Acolyte', 'charclass' => 'Wizard',
              'specialize' => 'Department of Mana Syntaxia', 'specialize_info' => 'Spell Substitution' },
            { 'alignment' => 'BL' }
          )
        end

        describe :commit do
          it "should accept a complete base info stage" do
            result = Lifecycle.commit(complete_wizard, 'stage' => 'info')

            expect(result.ok?).to be true
            expect(result.state['checkpoint']).to eq 'info'
            expect(result.state['locks']['baseinfo']).to be true
          end

          it "should reject a stage that is not a checkpoint" do
            result = Lifecycle.commit(complete_wizard, 'stage' => 'vibes')

            expect(result.code).to eq :bad_option
          end

          it "should refuse to skip a stage" do
            result = Lifecycle.commit(complete_wizard, 'stage' => 'skills')

            expect(result.code).to eq :wrong_stage
          end

          it "should refuse to commit the same stage twice" do
            once = Lifecycle.commit(complete_wizard, 'stage' => 'info')
            twice = Lifecycle.commit(once.state, 'stage' => 'info')

            expect(twice.code).to eq :wrong_stage
          end

          it "should list everything missing from an empty base info" do
            result = Lifecycle.commit(state, 'stage' => 'info')

            expect(result.code).to eq :incomplete
            expect(result.args['msg']).to include 'missing_ancestry'
            expect(result.args['msg']).to include 'missing_charclass'
          end

          it "should require a heritage once an ancestry is chosen" do
            result = Lifecycle.commit(state({ 'ancestry' => 'Khazad' }), 'stage' => 'info')

            expect(result.args['msg']).to include 'missing_heritage'
          end

          it "should require a specialty for a class that has them" do
            result = Lifecycle.commit(
              state({ 'ancestry' => 'Khazad', 'heritage' => 'Forge', 'background' => 'Acolyte', 'charclass' => 'Wizard' }, { 'alignment' => 'BL' }),
              'stage' => 'info'
            )

            expect(result.args['msg']).to include 'missing_subclass'
          end

          it "should require the specialty's own choice when it has one" do
            result = Lifecycle.commit(
              state({ 'ancestry' => 'Khazad', 'heritage' => 'Forge', 'background' => 'Acolyte', 'charclass' => 'Wizard', 'specialize' => 'Department of Mana Syntaxia' }, { 'alignment' => 'BL' }),
              'stage' => 'info'
            )

            expect(result.args['msg']).to include 'missing_subclass_info'
          end

          it "should not require a specialty for Fighter, which has none" do
            result = Lifecycle.commit(
              state({ 'ancestry' => 'Khazad', 'heritage' => 'Forge', 'background' => 'Acolyte', 'charclass' => 'Fighter' }, { 'alignment' => 'BL' }),
              'stage' => 'info'
            )

            expect(result.ok?).to be true
          end

          it "should require a deity for a class that venerates one" do
            result = Lifecycle.commit(
              state({ 'ancestry' => 'Khazad', 'heritage' => 'Forge', 'background' => 'Acolyte', 'charclass' => 'Cleric', 'specialize' => 'Cloistered' }, { 'alignment' => 'BL', 'sanctification' => 'Holy' }),
              'stage' => 'info'
            )

            expect(result.args['msg']).to include 'missing_deity'
          end

          it "should require a deity for a background that demands one" do
            result = Lifecycle.commit(
              state({ 'ancestry' => 'Khazad', 'heritage' => 'Forge', 'background' => 'Blessed', 'charclass' => 'Fighter' }, { 'alignment' => 'BL' }),
              'stage' => 'info'
            )

            expect(result.args['msg']).to include 'missing_deity'
          end

          it "should require a sanctification for a cleric" do
            result = Lifecycle.commit(
              state({ 'ancestry' => 'Khazad', 'heritage' => 'Forge', 'background' => 'Acolyte', 'charclass' => 'Cleric', 'specialize' => 'Cloistered' }, { 'alignment' => 'BL', 'deity' => 'Althea' }),
              'stage' => 'info'
            )

            expect(result.args['msg']).to include 'missing_sanctification'
          end

          it "should refuse a sanctification the deity does not allow" do
            result = Lifecycle.commit(
              state({ 'ancestry' => 'Khazad', 'heritage' => 'Forge', 'background' => 'Acolyte', 'charclass' => 'Cleric', 'specialize' => 'Cloistered' }, { 'alignment' => 'BL', 'deity' => 'Althea', 'sanctification' => 'Unholy' }),
              'stage' => 'info'
            )

            expect(result.args['msg']).to include 'sanctification_invalid'
          end

          it "should refuse when chargen has not been started" do
            result = Lifecycle.commit(complete_wizard.merge('chargen_stage' => 0), 'stage' => 'info')

            expect(result.code).to eq :not_in_chargen
          end
        end

        describe :restore do
          it "should move the checkpoint back to an earlier stage" do
            at_skills = complete_wizard.merge('checkpoint' => 'skills')
            result = Lifecycle.restore(at_skills, 'checkpoint' => 'info')

            expect(result.ok?).to be true
            expect(result.state['checkpoint']).to eq 'info'
          end

          it "should refuse a stage the character has not reached" do
            result = Lifecycle.restore(complete_wizard.merge('checkpoint' => 'info'), 'checkpoint' => 'skills')

            expect(result.code).to eq :stage_not_reached
          end

          it "should refuse an unknown stage" do
            expect(Lifecycle.restore(complete_wizard, 'checkpoint' => 'vibes').code).to eq :bad_option
          end
        end

        describe :reset do
          it "should ask for confirmation the first time" do
            result = Lifecycle.reset(state, 'confirm' => false)

            expect(result.ok?).to be true
            expect(result.state['reset_pending']).to be true
            expect(result.messages.first['key']).to eq 'pf2e.are_you_sure'
          end

          it "should refuse a confirmation that was never asked for" do
            result = Lifecycle.reset(state, 'confirm' => true)

            expect(result.code).to eq :reset_first
          end

          it "should go ahead once confirmed" do
            asked = Lifecycle.reset(state, 'confirm' => false)
            result = Lifecycle.reset(asked.state, 'confirm' => true)

            expect(result.ok?).to be true
            expect(result.state['reset_pending']).to be false
            expect(result.state['do_reset']).to be true
          end

          it "should remind the player to confirm if they repeat the bare command" do
            asked = Lifecycle.reset(state, 'confirm' => false)
            result = Lifecycle.reset(asked.state, 'confirm' => false)

            expect(result.messages.first['key']).to eq 'pf2e.must_confirm'
            expect(result.state['do_reset']).to be_falsey
          end
        end
      end
    end
  end
end
