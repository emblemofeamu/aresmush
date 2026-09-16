require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Type 2: a whole chargen expressed as data and run through the central service. No
    # character, no client, no Redis - state in, state out, assert on the state.
    describe CharacterService do
      describe "building a character as a chain of actions" do

        def config
          ConfigView.fixture(
            'pf2e' => {
              'use_alignment' => true,
              'allowed_alignments' => [ 'OL', 'BL', 'WL', 'OT', 'BT', 'WT' ]
            },
            'pf2e_ancestry' => { 'Khazad' => { 'heritages' => [ 'Forge', 'Rock' ] } },
            'pf2e_background' => { 'Acolyte' => {}, 'Artisan' => {} },
            'pf2e_class' => { 'Wizard' => { 'chargen' => { 'charclass_feature' => [ 'Arcane Bond' ] } } },
            'pf2e_specialty' => { 'Wizard' => { 'Department of Null\'s Purview' => {} } },
            'pf2e_deities' => { 'Althea' => { 'allowed_alignments' => [ 'OL', 'BL', 'WL' ] } }
          )
        end

        def fresh_state
          CharState.build({
              'base_info' => { 'ancestry' => '', 'heritage' => '', 'background' => '', 'charclass' => '', 'specialize' => '', 'specialize_info' => '' },
              'faith' => { 'deity' => '', 'alignment' => '', 'sanctification' => '' },
              'boosts' => { 'free' => [ 'open', 'open' ], 'charclass' => [ 'Intelligence' ] },
              'boosts_working' => { 'free' => [ 'open', 'open' ], 'charclass' => [ 'Intelligence' ] },
              'abilities' => [ 'Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma' ]
            },
            :config => config
          )
        end

        def base_info_steps
          [
            [ :set_base_info, { 'element' => 'ancestry', 'value' => 'Khazad' } ],
            [ :set_base_info, { 'element' => 'heritage', 'value' => 'Forge' } ],
            [ :set_base_info, { 'element' => 'background', 'value' => 'Acolyte' } ],
            [ :set_base_info, { 'element' => 'charclass', 'value' => 'Wizard' } ],
            [ :set_base_info, { 'element' => 'specialize', 'value' => 'Null' } ],
            [ :set_base_info, { 'element' => 'alignment', 'value' => 'BL' } ],
            [ :set_base_info, { 'element' => 'deity', 'value' => 'Althea' } ]
          ]
        end

        it "should carry a character from nothing to a complete base info" do
          result = CharacterService.chain(fresh_state, base_info_steps)

          expect(result.ok?).to be true
          expect(result.state['base_info']).to include(
            'ancestry' => 'Khazad',
            'heritage' => 'Forge',
            'background' => 'Acolyte',
            'charclass' => 'Wizard',
            'specialize' => "Department of Null's Purview"
          )
          expect(result.state['faith']['alignment']).to eq 'BL'
          expect(result.state['faith']['deity']).to eq 'Althea'
        end

        it "should collect a message for every step of the build" do
          result = CharacterService.chain(fresh_state, base_info_steps)
          set_messages = result.messages.select { |m| m['key'] == 'pf2e.option_set' }

          expect(set_messages.size).to eq base_info_steps.size
        end

        it "should continue into ability boosts once base info is locked" do
          built = CharacterService.chain(fresh_state, base_info_steps)
          locked = built.state.merge('locks' => built.state['locks'].merge('baseinfo' => true))

          result = CharacterService.chain(locked, [
            [ :set_boost, { 'type' => 'free', 'ability' => 'Constitution' } ],
            [ :set_boost, { 'type' => 'free', 'ability' => 'Wisdom' } ]
          ])

          expect(result.state['boosts_working']['free']).to eq [ 'Constitution', 'Wisdom' ]
        end

        it "should refuse a boost before base info is locked, naming the failing action" do
          built = CharacterService.chain(fresh_state, base_info_steps)

          result = CharacterService.chain(built.state, [ [ :set_boost, { 'type' => 'free', 'ability' => 'Wisdom' } ] ])

          expect(result.err?).to be true
          expect(result.code).to eq :info_not_locked
          expect(result.failed_action).to eq :set_boost
        end

        it "should stop the build at the first bad step and leave the rest unrun" do
          steps = [
            [ :set_base_info, { 'element' => 'ancestry', 'value' => 'Khazad' } ],
            [ :set_base_info, { 'element' => 'heritage', 'value' => 'Cavern' } ],
            [ :set_base_info, { 'element' => 'background', 'value' => 'Acolyte' } ]
          ]

          result = CharacterService.chain(fresh_state, steps)

          expect(result.err?).to be true
          expect(result.code).to eq :bad_option
        end

        it "should let a rebuild reuse the same steps against a used state" do
          once = CharacterService.chain(fresh_state, base_info_steps)
          twice = CharacterService.chain(once.state, base_info_steps)

          expect(twice.ok?).to be true
          expect(twice.state['base_info']['charclass']).to eq 'Wizard'
        end

        it "should keep the original state untouched so a failed build changes nothing" do
          original = fresh_state
          CharacterService.chain(original, base_info_steps)

          expect(original['base_info']['ancestry']).to eq ''
        end
      end
    end
  end
end
