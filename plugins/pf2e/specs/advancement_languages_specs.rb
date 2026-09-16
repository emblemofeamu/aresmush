require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement
      describe Languages do

        def config
          ConfigView.fixture(
            'pf2e' => { 'can_select_language' => [ 'common', 'uncommon' ] },
            'pf2e_languages' => {
              'common' => { 'Kamin' => 'desc', 'Silya' => 'desc' },
              'uncommon' => { 'Aklo' => 'desc' },
              'rare' => { 'Mynsandraal' => 'desc' }
            }
          )
        end

        def state(slots: [ 'open' ], known: [], picked: [])
          CharState.build(
            {
              'to_assign' => slots.nil? ? {} : { 'open languages' => slots },
              'advancement' => { 'languages' => picked }
            },
            :sheet => { 'languages' => known },
            :config => config
          )
        end

        it "should fill an open slot and record the pick in the draft" do
          result = Languages.pick(state, 'language' => 'Silya')

          expect(result.ok?).to be true
          expect(result.state['to_assign']['open languages']).to eq [ 'Silya' ]
          expect(result.state['advancement']['languages']).to eq [ 'Silya' ]
        end

        # The draft is the point: a level-up pick becomes a grant when the level is
        # committed, not when it is typed.
        it "should not write a grant" do
          expect(Languages.pick(state, 'language' => 'Silya').grants).to be_empty
        end

        it "should refuse a language the game does not let players select" do
          result = Languages.pick(state, 'language' => 'Mynsandraal')

          expect(result.code).to eq :bad_option
          expect(result.args['element']).to eq 'language'
        end

        it "should refuse a language the character already has" do
          result = Languages.pick(state(:known => [ 'Silya' ]), 'language' => 'Silya')

          expect(result.code).to eq :already_knows
        end

        it "should refuse one already picked earlier in this same advancement" do
          result = Languages.pick(state(:picked => [ 'Silya' ]), 'language' => 'Silya')

          expect(result.code).to eq :already_knows
        end

        it "should refuse when every slot is spent" do
          result = Languages.pick(state(:slots => [ 'Kamin' ]), 'language' => 'Silya')

          expect(result.code).to eq :no_free
        end

        it "should refuse when this level offered no language at all" do
          result = Languages.pick(state(:slots => nil), 'language' => 'Silya')

          expect(result.code).to eq :cannot_assign
        end
      end
    end
  end
end
