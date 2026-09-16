require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # The audit as the game actually drives it: XP spent by levelling, refunded by a rollback,
    # charged again by a redo, and money moved by the gear commands.
    describe "the audit in play", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Play#{rand(1000000)}")
      end

      after(:each) do
        Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      def xp_entries
        Audit.page(@char, 'xp', 1, 200)
      end

      # ----------------------------------------------------------------------------
      # XP
      # ----------------------------------------------------------------------------

      it "should record every award, including the ones that used to go unrecorded" do
        # Nominations called award_xp without ever calling record_xp_history, so they moved a
        # total with nothing to show for it. One door means that cannot happen.
        Pf2e.award_xp(@char, 250)
        Pf2e.award_xp(@char, 500, 'Vardama', 'Weekly award')

        expect(Audit.count(@char, 'xp')).to eq 2
        expect(Character[@char.id].pf2_xp).to eq 750
      end

      it "should charge a level-up to the level it bought" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 4)

        expect(builder.summary['level']).to eq 4

        spends = xp_entries.select { |e| e.amount.to_i.negative? }

        # Levels 2, 3 and 4.
        expect(spends.size).to eq 3
        expect(spends.map { |e| e.amount }.uniq).to eq [ -Pf2e::ADVANCEMENT_XP_COST ]
        expect(spends.map { |e| e.reason }).to include 'advance to level 4'

        # Tagged with the transaction that incurred it, which is what lets a rollback find it.
        expect(spends.map { |e| e.ref }.compact.uniq.size).to eq 3
      end

      it "should keep the total and the entries in step through a whole climb" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 6)

        expect(builder.summary['level']).to eq 6
        expect(Audit.consistent?(Character[char.id], 'xp')).to be true
      end

      it "should refund a rollback and charge a redo, leaving both in the history" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 6)

        xp_at_6 = char.pf2_xp
        entries_at_6 = Audit.count(char, 'xp')

        expect(Pf2e.rollback_to_level(char, 5)).to be_nil
        char = Character[char.id]

        # Levels 5 and 6 come back, so two levels' worth of xp does too.
        expect(char.pf2_xp).to eq(xp_at_6 + (2 * Pf2e::ADVANCEMENT_XP_COST))

        refund = Audit.page(char, 'xp', 1, 1).first

        expect(refund.amount).to eq(2 * Pf2e::ADVANCEMENT_XP_COST)
        expect(refund.ref).to eq char.pf2_rollback_marker

        expect(Pf2e.redo_rollback(char)).to be_nil
        char = Character[char.id]

        expect(char.pf2_xp).to eq xp_at_6

        # Nothing was rewritten: the refund and the charge both stand as history.
        expect(Audit.count(char, 'xp')).to eq(entries_at_6 + 2)
        expect(Audit.consistent?(char, 'xp')).to be true
      end

      it "should page the newest entries first" do
        25.times { |i| Pf2e.award_xp(@char, 10, 'Staff', "award #{i + 1}") }

        expect(Audit.page(@char, 'xp', 1, 10).first.reason).to eq 'award 25'
        expect(Audit.total_pages(@char, 'xp', 10)).to eq 3
      end

      # ----------------------------------------------------------------------------
      # Money
      # ----------------------------------------------------------------------------

      it "should record a purse movement and the purse it left behind" do
        @char.update(:pf2_money => 1000)

        Pf2egear.pay_player(@char, -250, 'Item Vendor', 'Purchase Longsword')

        entry = Audit.page(@char, 'money', 1, 1).first

        expect(Character[@char.id].pf2_money).to eq 750
        expect(entry.amount).to eq(-250)
        expect(entry.balance_after).to eq 750
        expect(entry.reason).to eq 'Purchase Longsword'
      end

      # A transfer is one event seen from two sides. Sharing a reference is what makes the two
      # halves matchable - before, they were related only by opposite signs and a timestamp.
      it "should tie the two halves of a payment together" do
        payer = @char
        payee = Character.create(:name => "Payee#{rand(1000000)}")

        payer.update(:pf2_money => 500)
        payee.update(:pf2_money => 0)

        transfer = "transfer-test-1"

        Pf2egear.pay_player(payer, -120, payee.name, "Payment to #{payee.name}", transfer)
        Pf2egear.pay_player(payee, 120, payer.name, "Payment from #{payer.name}", transfer)

        expect(Character[payer.id].pf2_money).to eq 380
        expect(Character[payee.id].pf2_money).to eq 120

        expect(Audit.page(payer, 'money', 1, 1).first.ref).to eq transfer
        expect(Audit.page(payee, 'money', 1, 1).first.ref).to eq transfer

        Audit.delete_all!(payee)
        payee.delete
      end

      it "should keep xp and money in separate histories" do
        Pf2e.award_xp(@char, 500, 'Staff', 'award')
        Pf2egear.pay_player(@char, 50, 'Staff', 'purse')

        expect(Audit.count(@char, 'xp')).to eq 1
        expect(Audit.count(@char, 'money')).to eq 1
        expect(Audit.page(@char, 'xp', 1, 10).first.reason).to eq 'award'
      end
    end
  end
end
