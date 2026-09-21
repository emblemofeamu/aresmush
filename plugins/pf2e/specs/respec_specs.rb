require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Starting a character over.
    #
    # A respec keeps what the character earned - level, XP, money, inventory - and throws the
    # build away. A reset throws everything away. Both have to take the grant ledger with them:
    # a character with grants is finalized, so leaving the rows behind would mean the next fold
    # writing the old sheet back over the blank one, and chargen commands recording history for a
    # character who is supposed to be in a draft.
    describe "starting a character over", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Respec#{rand(1000000)}")

        builder = AutoBuilder.new(@char)
        builder.build_level_one('Fighter')
        builder.advance_to(3)
        Pf2egear.pay_player(Character[@char.id], -250, 'Spec Vendor', 'a purchase')
        @char = Character[@char.id]
        @money = @char.pf2_money
      end

      after(:each) do
        @char.delete if @char
      end

      def reread
        Character[@char.id]
      end

      def trained_count(char)
        char.skills.to_a.count { |s| s.prof_level != 'untrained' }
      end

      it "should build a character worth starting over" do
        expect(reread.pf2_level).to eq 3
        expect(reread.grants.count).to be > 0
        expect(trained_count(reread)).to be > 0
      end

      describe "a respec" do
        before(:each) { Pf2e.respec_character(reread) }

        it "should keep the level and the xp" do
          expect(reread.pf2_level).to eq 3
          expect(reread.pf2_xp).to be > 0
        end

        it "should keep their money and its history" do
          expect(reread.pf2_money).to eq @money
          expect(Pf2e::Audit.consistent?(reread, 'money')).to be true
        end

        it "should clear the sheet" do
          expect(reread.pf2_feats.values.flatten).to be_empty
          expect(reread.pf2_features.values.flatten).to be_empty
          expect(trained_count(reread)).to eq 0
          expect(Array(reread.pf2_lang)).to be_empty
        end

        it "should take the ledger with it" do
          expect(reread.grants.count).to eq 0
          expect(reread.sheet_caches.count).to eq 0
        end

        it "should leave the character in a draft again" do
          expect(Pf2e::Ledger.drafting?(reread)).to be true
        end

        it "should not let a fold put the old sheet back" do
          Pf2e::Ledger.materialize!(reread)

          expect(trained_count(reread)).to eq 0
        end

        it "should unapprove them" do
          expect(reread.is_approved?).to be false
          expect(reread.chargen_stage).to eq 0
        end
      end

      describe "a reset" do
        before(:each) { Pf2e.reset_character(reread) }

        it "should take the level and the xp too" do
          expect(reread.pf2_level).to eq 1
          expect(reread.pf2_xp).to eq 0
        end

        it "should leave the money balance agreeing with its entries" do
          expect(Pf2e::Audit.consistent?(reread, 'money')).to be true
          expect(Pf2e::Audit.count(reread, 'money')).to eq 0
        end

        it "should take the ledger with it" do
          expect(reread.grants.count).to eq 0
          expect(reread.sheet_caches.count).to eq 0
        end

        it "should leave the character in a draft again" do
          expect(Pf2e::Ledger.drafting?(reread)).to be true
        end
      end
    end
  end
end
