require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Chargen
      describe Languages do

        def config
          ConfigView.fixture(
            'pf2e' => { 'can_select_language' => [ 'common', 'uncommon' ] },
            'pf2e_languages' => {
              'common' => { 'Kamin' => 'desc', 'Silya' => 'desc', 'Khazdul' => 'desc' },
              'uncommon' => { 'Aklo' => 'desc' },
              'rare' => { 'Mynsandraal' => 'desc' },
              'secret' => { 'Wildsong' => 'desc' }
            }
          )
        end

        def state(open_languages: [ 'open', 'open' ], known: [])
          CharState.build(
            { 'to_assign' => { 'open languages' => open_languages } },
            :sheet => { 'languages' => known },
            :config => config
          )
        end

        describe :learn do
          it "should take a slot and grant the language" do
            result = Languages.learn(state, 'language' => 'Silya')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['open languages']).to eq [ 'Silya', 'open' ]
            expect(result.grants.first['kind']).to eq 'add_language'
            expect(result.grants.first['payload']['language']).to eq 'Silya'
          end

          it "should refuse a rare language, which players may not select" do
            result = Languages.learn(state, 'language' => 'Mynsandraal')

            expect(result.code).to eq :bad_option
            expect(result.args['element']).to eq 'language'
          end

          it "should refuse the druid-only secret language" do
            expect(Languages.learn(state, 'language' => 'Wildsong').code).to eq :bad_option
          end

          it "should allow an uncommon language" do
            result = Languages.learn(state, 'language' => 'Aklo')

            expect(result.state['to_assign']['open languages']).to eq [ 'Aklo', 'open' ]
            expect(result.grants.first['payload']['language']).to eq 'Aklo'
          end

          it "should refuse when the character has no language picks at all" do
            blank = CharState.build({ 'to_assign' => {} }, :config => config)

            expect(Languages.learn(blank, 'language' => 'Silya').code).to eq :cannot_assign
          end

          it "should refuse a language the character already knows" do
            result = Languages.learn(state(:known => [ 'Silya' ]), 'language' => 'Silya')

            expect(result.code).to eq :already_has
          end

          it "should refuse when every slot is spent" do
            result = Languages.learn(state(:open_languages => [ 'Kamin', 'Khazdul' ]), 'language' => 'Silya')

            expect(result.code).to eq :no_free
          end

          it "should report the addition" do
            result = Languages.learn(state, 'language' => 'Silya')

            expect(result.messages.first['key']).to eq 'pf2e.add_ok'
            expect(result.messages.first['args']['item']).to eq 'Silya'
          end

          it "should not mutate the state it was given" do
            original = state
            Languages.learn(original, 'language' => 'Silya')

            expect(original['to_assign']['open languages']).to eq [ 'open', 'open' ]
          end
        end

        describe :forget do
          it "should free the slot and revoke the grant" do
            picked = Languages.learn(state, 'language' => 'Silya')
            result = Languages.forget(picked.state, 'language' => 'Silya')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['open languages']).to eq [ 'open', 'open' ]
            expect(result.revocations.first['kind']).to eq 'add_language'
            expect(result.revocations.first['match']['language']).to eq 'Silya'
          end

          it "should refuse a language the character did not choose in chargen" do
            result = Languages.forget(state(:known => [ 'Kamin' ]), 'language' => 'Kamin')

            expect(result.code).to eq :not_in_list
            expect(result.key).to eq 'pf2e.not_in_list'
          end

          it "should refuse when the character has no language picks at all" do
            blank = CharState.build({ 'to_assign' => {} }, :config => config)

            expect(Languages.forget(blank, 'language' => 'Silya').code).to eq :cannot_assign
          end

          it "should report the reset" do
            picked = Languages.learn(state, 'language' => 'Silya')
            result = Languages.forget(picked.state, 'language' => 'Silya')

            expect(result.messages.first['key']).to eq 'pf2e.reset_ok'
            expect(result.messages.first['args']['element']).to eq 'language'
          end
        end
      end
    end
  end
end
