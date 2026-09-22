require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # Who pays whom, how much, and what gets written down.
    #
    # Pure: two purses and an amount in, either the two halves of the transfer or a refusal out.
    # `pay` did all of this inline, which is how staff came to be exempt from being *recorded*
    # as well as from being charged - two different exemptions that had grown into one `unless`.
    describe Payment do

      def purse(money, staff: false)
        double(:name => staff ? 'Staff' : 'Player', :pf2_money => money, :is_admin? => staff)
      end

      describe "a player paying a player" do
        it "should take from the payer and give to the payee" do
          outcome = Payment.plan(purse(500), purse(0), 120)

          expect(outcome).to be_ok
          amounts = outcome.state.map { |half| half['amount'] }
          expect(amounts).to eq [ -120, 120 ]
        end

        it "should tie both halves to one reference" do
          halves = Payment.plan(purse(500), purse(0), 120).state

          expect(halves.map { |half| half['ref'] }.uniq.size).to eq 1
          expect(halves.first['ref']).to start_with 'transfer-'
        end

        it "should refuse a payment the payer cannot cover" do
          outcome = Payment.plan(purse(100), purse(0), 120)

          expect(outcome).to be_err
          expect(outcome.code).to eq :insufficient
        end

        it "should allow a payment that empties the purse exactly" do
          expect(Payment.plan(purse(120), purse(0), 120)).to be_ok
        end
      end

      # Staff have unlimited funds - that is deliberate, and stays. What changed is that the
      # movement is now written down: a staff purse going negative is the true record of money
      # having been created, and the entry says who created it.
      describe "staff" do
        it "should not be stopped by an empty purse" do
          expect(Payment.plan(purse(0, :staff => true), purse(0), 5000)).to be_ok
        end

        it "should still have the payment recorded against them" do
          halves = Payment.plan(purse(0, :staff => true), purse(0), 5000).state

          expect(halves.size).to eq 2
          expect(halves.first['amount']).to eq(-5000)
        end

        it "should have a payment to them recorded too" do
          halves = Payment.plan(purse(500), purse(0, :staff => true), 100).state

          expect(halves.size).to eq 2
          expect(halves.last['amount']).to eq 100
        end
      end

      describe "each half" do
        it "should say who the other side was and why" do
          halves = Payment.plan(purse(500), purse(0), 120).state

          expect(halves.first['by']).to eq 'Player'
          expect(halves.first['reason']).to eq 'Payment to Player'
          expect(halves.last['reason']).to eq 'Payment from Player'
        end
      end

      describe "a nonsense amount" do
        it "should refuse zero" do
          expect(Payment.plan(purse(500), purse(0), 0).code).to eq :bad_value
        end

        it "should refuse a negative amount, because direction is the caller's business" do
          expect(Payment.plan(purse(500), purse(0), -50).code).to eq :bad_value
        end
      end
    end
  end
end
