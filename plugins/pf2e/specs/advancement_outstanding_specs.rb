require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement
      describe Outstanding do

        def state(to_assign)
          CharState.build({ 'to_assign' => to_assign }, :config => ConfigView.fixture({}))
        end

        it "should report nothing outstanding on an empty draft" do
          expect(Outstanding.labels(state({}))).to eq []
          expect(Outstanding.any?(state({}))).to be false
        end

        it "should list a class feature waiting for a pick, with its options" do
          current = state('class option' => { 'Path to Perfection' => %w(Will Fortitude Reflex) })

          expect(Outstanding.labels(current)).to eq [ 'Path to Perfection' ]
          expect(Outstanding.class_option(current, 'path to perfection')).to eq [ 'Path to Perfection', %w(Fortitude Reflex Will) ]
        end

        # Once chosen, the feature is stored as the bare value rather than a list.
        it "should drop a class feature once it has been chosen" do
          current = state('class option' => { 'Path to Perfection' => 'Reflex' })

          expect(Outstanding.labels(current)).to eq []
          expect(Outstanding.class_option(current, 'Path to Perfection')).to be_nil
        end

        it "should list feat slots by type, and only the open ones" do
          current = state('feats' => { 'charclass' => [ 'open' ], 'skill' => [ 'Assurance' ] })

          expect(Outstanding.labels(current)).to eq [ 'charclass feat' ]
        end

        # A feat choice keeps its key after it is resolved, so listing by key alone told
        # players to pick things they had already picked.
        it "should list a feat choice only while one of its slots is open" do
          expect(Outstanding.labels(state('feat choice' => { 'Stylish Tricks' => [ 'open' ] }))).to eq [ 'Stylish Tricks' ]
          expect(Outstanding.labels(state('feat choice' => { 'Stylish Tricks' => [ 'Additional Lore' ] }))).to eq []
        end

        it "should gather every source into one sorted list" do
          current = state(
            'class option' => { 'Path to Perfection' => %w(Fortitude) },
            'feat choice' => { 'Stylish Tricks' => [ 'open' ] },
            'feats' => { 'general' => [ 'open' ] }
          )

          expect(Outstanding.labels(current)).to eq [ 'Path to Perfection', 'Stylish Tricks', 'general feat' ]
          expect(Outstanding.any?(current)).to be true
        end

        it "should read a class feature whose options are the hash keys" do
          current = state('class option' => { 'Blessing of the Devoted' => { 'Blessed Shield' => {}, 'Blessed Armament' => {} } })

          expect(Outstanding.class_option(current, 'Blessing of the Devoted')).to eq [ 'Blessing of the Devoted', [ 'Blessed Armament', 'Blessed Shield' ] ]
        end
      end
    end
  end
end
