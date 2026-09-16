require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Chargen
      describe BaseInfo do

        def config
          ConfigView.fixture(
            'pf2e' => {
              'use_alignment' => true,
              'allowed_alignments' => [ 'OL', 'BL', 'WL', 'OT', 'BT', 'WT' ],
              'subclass_names' => { 'Wizard' => 'Thesis', 'Champion' => 'Cause' }
            },
            'pf2e_ancestry' => {
              'Khazad' => { 'heritages' => [ 'Forge', 'Rock', 'Ancient-Blooded' ] },
              'Sildanyar' => { 'heritages' => [ 'Cavern', 'Woodland' ] }
            },
            'pf2e_background' => { 'Acolyte' => {}, 'Artisan' => {} },
            'pf2e_class' => {
              'Wizard' => { 'chargen' => { 'charclass_feature' => [ 'Arcane Bond', 'Arcane Thesis' ] } },
              'Cleric' => { 'chargen' => { 'charclass_feature' => [ 'Divine Font' ] } },
              'Champion' => { 'allowed_sanctifications' => [ 'Holy', 'Unsanctified' ], 'chargen' => {} }
            },
            'pf2e_specialty' => {
              'Wizard' => { 'Department of Mana Syntaxia' => { 'choose' => { 'options' => { 'Improved Familiar Attunement' => {}, 'Spell Substitution' => {} } } } },
              'Champion' => { 'Beacon' => { 'allowed_alignments' => [ 'WL' ], 'allowed_sanctifications' => [ 'Holy' ] } },
              'Cleric' => { 'Cloistered' => {} }
            },
            'pf2e_deities' => {
              'Althea' => { 'allowed_alignments' => [ 'OL', 'BL', 'WL' ], 'allowed_sanctifications' => [ 'Holy' ] },
              'Maugrim' => { 'allowed_alignments' => [ 'OT', 'BT' ], 'allowed_sanctifications' => [ 'Unholy' ] }
            }
          )
        end

        def state(base_info = {}, faith = {})
          CharState.build({ 'base_info' => base_info, 'faith' => faith }, :config => config)
        end

        describe "resolving the element and value" do
          it "should reject an element that is not part of chargen" do
            result = BaseInfo.set(state, 'element' => 'hairstyle', 'value' => 'braided')

            expect(result.code).to eq :bad_element
          end

          it "should resolve a partial value to the one option it matches" do
            result = BaseInfo.set(state, 'element' => 'ancestry', 'value' => 'khaz')

            expect(result.state['base_info']['ancestry']).to eq 'Khazad'
          end

          it "should refuse a value matching more than one option" do
            result = BaseInfo.set(state, 'element' => 'ancestry', 'value' => 'a')

            expect(result.code).to eq :multiple_matches
          end

          it "should refuse a value matching nothing" do
            result = BaseInfo.set(state, 'element' => 'ancestry', 'value' => 'Dwarf')

            expect(result.code).to eq :bad_option
          end

          it "should require an ancestry before a heritage" do
            result = BaseInfo.set(state, 'element' => 'heritage', 'value' => 'Forge')

            expect(result.code).to eq :ancestry_not_set
          end

          it "should offer only that ancestry's heritages" do
            result = BaseInfo.set(state('ancestry' => 'Khazad'), 'element' => 'heritage', 'value' => 'Cavern')

            expect(result.code).to eq :bad_option
          end

          it "should require a class before a specialty" do
            result = BaseInfo.set(state, 'element' => 'specialize', 'value' => 'Beacon')

            expect(result.code).to eq :charclass_not_set
          end
        end

        describe "clearing dependent choices" do
          it "should clear the heritage when the ancestry changes" do
            result = BaseInfo.set(state('ancestry' => 'Khazad', 'heritage' => 'Forge'), 'element' => 'ancestry', 'value' => 'Sildanyar')

            expect(result.state['base_info']['heritage']).to eq ''
          end

          it "should clear the specialty and its option when the class changes" do
            before = state('charclass' => 'Wizard', 'specialize' => 'Department of Mana Syntaxia', 'specialize_info' => 'Spell Substitution')
            result = BaseInfo.set(before, 'element' => 'charclass', 'value' => 'Cleric')

            expect(result.state['base_info']['specialize']).to eq ''
            expect(result.state['base_info']['specialize_info']).to eq ''
          end

          it "should clear the specialty option when the specialty changes" do
            before = state('charclass' => 'Wizard', 'specialize' => 'Department of Mana Syntaxia', 'specialize_info' => 'Spell Substitution')
            result = BaseInfo.set(before, 'element' => 'specialize', 'value' => 'Mana')

            expect(result.state['base_info']['specialize_info']).to eq ''
          end

          it "should clear a sanctification that the new class cannot have" do
            before = state({ 'charclass' => 'Cleric' }, { 'sanctification' => 'Holy', 'deity' => 'Althea' })
            result = BaseInfo.set(before, 'element' => 'charclass', 'value' => 'Wizard')

            expect(result.state['faith']['sanctification']).to eq ''
          end
        end

        describe "cross-checks" do
          it "should refuse a deity whose allowed alignments exclude the character's" do
            before = state({}, { 'alignment' => 'WT' })
            result = BaseInfo.set(before, 'element' => 'deity', 'value' => 'Althea')

            expect(result.code).to eq :deity_alignment_mismatch
            expect(result.key).to eq 'pf2e.cg_deity_alignment_mismatch'
          end

          it "should refuse an alignment the already-chosen deity does not allow" do
            before = state({}, { 'deity' => 'Maugrim' })
            result = BaseInfo.set(before, 'element' => 'alignment', 'value' => 'OL')

            expect(result.code).to eq :deity_alignment_mismatch
          end

          it "should allow a deity whose alignments include the character's" do
            before = state({}, { 'alignment' => 'BL' })
            result = BaseInfo.set(before, 'element' => 'deity', 'value' => 'Althea')

            expect(result.ok?).to be true
            expect(result.state['faith']['deity']).to eq 'Althea'
          end

          it "should refuse Champion for a deity that does not permit champions" do
            before = state({}, { 'deity' => 'Maugrim' })
            result = BaseInfo.set(before, 'element' => 'charclass', 'value' => 'Champion')

            expect(result.code).to eq :champion_deity_mismatch
          end

          it "should refuse a champion cause the character's alignment does not allow" do
            before = state({ 'charclass' => 'Champion' }, { 'alignment' => 'OL' })
            result = BaseInfo.set(before, 'element' => 'specialize', 'value' => 'Beacon')

            expect(result.code).to eq :champion_specialty_alignment_mismatch
          end

          it "should refuse sanctification on a class that has none" do
            result = BaseInfo.set(state('charclass' => 'Wizard'), 'element' => 'sanctification', 'value' => 'Holy')

            expect(result.code).to eq :sanctification_wrong_class
          end

          it "should require a deity before a cleric's sanctification" do
            result = BaseInfo.set(state('charclass' => 'Cleric'), 'element' => 'sanctification', 'value' => 'Holy')

            expect(result.code).to eq :sanctification_needs_deity
          end

          it "should accept a sanctification the deity allows" do
            before = state({ 'charclass' => 'Cleric' }, { 'deity' => 'Althea', 'alignment' => 'BL' })
            result = BaseInfo.set(before, 'element' => 'sanctification', 'value' => 'Holy')

            expect(result.ok?).to be true
            expect(result.state['faith']['sanctification']).to eq 'Holy'
          end
        end

        describe "results" do
          it "should report what was set" do
            result = BaseInfo.set(state, 'element' => 'ancestry', 'value' => 'Khazad')

            expect(result.messages.first['key']).to eq 'pf2e.option_set'
            expect(result.messages.first['args']['option']).to eq 'Khazad'
          end

          it "should hint at the heritages available for a new ancestry" do
            result = BaseInfo.set(state, 'element' => 'ancestry', 'value' => 'Khazad')
            hint = result.messages.find { |m| m['key'] == 'pf2e.cg_ancestry_heritages' }

            expect(hint).to_not be_nil
            expect(hint['type']).to eq 'ooc'
          end

          it "should emit no grants - chargen picks become grants at commit, not before" do
            result = BaseInfo.set(state, 'element' => 'charclass', 'value' => 'Wizard')

            expect(result.grants).to eq []
          end

          it "should not mutate the state it was given" do
            original = state('ancestry' => 'Khazad', 'heritage' => 'Forge')
            BaseInfo.set(original, 'element' => 'ancestry', 'value' => 'Sildanyar')

            expect(original['base_info']['heritage']).to eq 'Forge'
          end
        end
      end
    end
  end
end
