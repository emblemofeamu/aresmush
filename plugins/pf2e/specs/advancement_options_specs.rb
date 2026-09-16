require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement
      describe Options do

        def state(pending:, slot: 'class option', saves: {}, advancement: {})
          CharState.build(
            {
              'to_assign' => { slot => pending },
              'advancement' => advancement,
              'saves' => saves
            },
            :config => ConfigView.fixture({})
          )
        end

        # The three shapes a pending feature arrives in, all of which the command accepts.
        describe :option_list do
          it "should read a hash carrying an options list" do
            expect(Options.option_list('options' => [ 'Fortitude', 'Reflex' ])).to eq [ 'Fortitude', 'Reflex' ]
          end

          it "should read a hash whose keys are the options" do
            expect(Options.option_list('Blessed Armament' => {}, 'Blessed Shield' => {})).to eq [ 'Blessed Armament', 'Blessed Shield' ]
          end

          it "should read a plain list" do
            expect(Options.option_list([ 'Fortitude', 'Reflex', 'Will' ])).to eq [ 'Fortitude', 'Reflex', 'Will' ]
          end

          it "should read a list of label and info pairs" do
            expect(Options.option_list([ [ 'Axes', {} ], [ 'Bows', {} ] ])).to eq [ 'Axes', 'Bows' ]
          end
        end

        describe :choose do
          it "should record the pick in the draft" do
            result = Options.choose(state(:pending => { 'Path to Perfection' => %w(Fortitude Reflex Will) }), 'feature' => 'Path to Perfection', 'value' => 'Reflex')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['class option']['Path to Perfection']).to eq 'Reflex'
            expect(result.state['advancement']['charclass_feature option']['Path to Perfection']).to eq 'Reflex'
          end

          it "should match the option however the player capitalised it" do
            result = Options.choose(state(:pending => { 'Path to Perfection' => %w(Fortitude Reflex Will) }), 'feature' => 'path to perfection', 'value' => 'reflex')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['class option']['Path to Perfection']).to eq 'Reflex'
          end

          it "should choose from a hash whose keys are the options" do
            pending = { 'Blessing of the Devoted' => { 'Blessed Armament' => {}, 'Blessed Shield' => {} } }
            result = Options.choose(state(:pending => pending), 'feature' => 'Blessing of the Devoted', 'value' => 'Blessed Shield')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['class option']['Blessing of the Devoted']).to eq 'Blessed Shield'
          end

          it "should refuse a value that is not on the list" do
            result = Options.choose(state(:pending => { 'Path to Perfection' => %w(Fortitude Reflex Will) }), 'feature' => 'Path to Perfection', 'value' => 'Perception')

            expect(result.code).to eq :bad_option
          end

          it "should refuse a feature this level did not offer" do
            result = Options.choose(state(:pending => { 'Path to Perfection' => %w(Fortitude) }), 'feature' => 'Fighter Weapon Mastery', 'value' => 'Axes')

            expect(result.code).to eq :not_an_option
          end

          it "should refuse when nothing is pending at all" do
            blank = CharState.build({ 'to_assign' => {} }, :config => ConfigView.fixture({}))
            result = Options.choose(blank, 'feature' => 'Path to Perfection', 'value' => 'Fortitude')

            expect(result.code).to eq :not_an_option
          end
        end

        # Player Core: the second path must be a different save, and the third must raise one
        # of the two already taken to legendary.
        describe "the Path to Perfection family" do
          it "should allow any save for the first" do
            result = Options.choose(state(:pending => { 'Path to Perfection' => %w(Fortitude Reflex Will) }), 'feature' => 'Path to Perfection', 'value' => 'Fortitude')

            expect(result.ok?).to be true
          end

          it "should refuse a second path on a save already taken" do
            result = Options.choose(
              state(:pending => { 'Second Path to Perfection' => %w(Fortitude Reflex Will) }, :saves => { 'Path to Perfection' => [ 'Fortitude' ] }),
              'feature' => 'Second Path to Perfection', 'value' => 'Fortitude'
            )

            expect(result.code).to eq :bad_option
          end

          it "should allow a second path on a different save" do
            result = Options.choose(
              state(:pending => { 'Second Path to Perfection' => %w(Fortitude Reflex Will) }, :saves => { 'Path to Perfection' => [ 'Fortitude' ] }),
              'feature' => 'Second Path to Perfection', 'value' => 'Reflex'
            )

            expect(result.ok?).to be true
          end

          it "should refuse a third path on a save that is not already master" do
            result = Options.choose(
              state(:pending => { 'Third Path to Perfection' => %w(Fortitude Reflex Will) }, :saves => { 'Path to Perfection' => %w(Fortitude Reflex) }),
              'feature' => 'Third Path to Perfection', 'value' => 'Will'
            )

            expect(result.code).to eq :bad_option
          end

          it "should allow a third path on a save already made master" do
            result = Options.choose(
              state(:pending => { 'Third Path to Perfection' => %w(Fortitude Reflex Will) }, :saves => { 'Path to Perfection' => %w(Fortitude Reflex) }),
              'feature' => 'Third Path to Perfection', 'value' => 'Fortitude'
            )

            expect(result.ok?).to be true
          end
        end
      end
    end
  end
end
