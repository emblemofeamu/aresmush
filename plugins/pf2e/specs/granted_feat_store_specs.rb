require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Where a feat goes when something hands it over.
    #
    # A pick and a grant are the same kind of thing, so they go to the same place: the draft. The
    # sheet's own list is what the materialiser writes from the fold, and a feat written straight
    # there would be erased by the next one. Both commit boundaries read the draft as well as the
    # sheet, so a granted feat becomes history at the same moment a chosen one does.
    describe "a granted feat", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Granted#{rand(1000000)}")
      end

      after(:each) { @char.delete if @char }

      def reread
        Character[@char.id]
      end

      def held
        Pf2e::DraftSheet.of(reread).feats_by_bucket.values.flatten
      end

      it "should go to the draft rather than the sheet" do
        Pf2e.record_feat(@char, 'general', 'Shield Block')

        expect(reread.pf2_advancement['feats']).to eq('general' => [ 'Shield Block' ])
        expect(Array(reread.pf2_feats['general'])).to be_empty
        expect(held).to include 'Shield Block'
      end

      it "should be taken out of either store" do
        Pf2e.record_feat(@char, 'general', 'Shield Block')
        @char.update(:pf2_feats => { 'skill' => [ 'Assurance' ] })

        Pf2e.forget_feat(reread, 'Shield Block')
        Pf2e.forget_feat(reread, 'assurance')

        expect(held).to be_empty
      end

      it "should be recorded, not assigned, so what is there stays" do
        Pf2e.record_feat(@char, 'general', 'Shield Block')
        Pf2e.record_feat(reread, 'general', 'Toughness')

        expect(reread.pf2_advancement['feats']['general']).to eq [ 'Shield Block', 'Toughness' ]
      end

      # The boundary is what turns either store into history.
      it "should reach the ledger when chargen commits" do
        builder = AutoBuilder.new(@char)
        builder.build_level_one('Fighter')
        @char = reread

        granted = held

        expect(granted).to_not be_empty

        Roles.add_role(@char, 'approved')
        @char = reread
        Pf2e::Ledger.commit_chargen!(@char)

        recorded = Character[@char.id].grants.to_a.select { |g| g.kind == 'grant_feat' }.map { |g| g.payload['feat'].to_s }

        expect(granted - recorded).to eq []
        expect(Character[@char.id].pf2_advancement).to eq({})
      end
    end
  end
end
