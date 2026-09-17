module AresMUSH
  module Pf2egear

    # A transfer of money between two purses, decided before anything is written.
    #
    # One event, two halves: the payer's and the payee's. They share a reference, so a history can
    # show the pair as one transfer instead of two movements with opposite signs.
    #
    # Pure, taking two purses and an amount and returning the halves or a refusal, so the rules can
    # be proven without a database.
    #
    # Staff are exempt from the sufficiency check and are not exempt from being recorded. Those are
    # separate decisions. A staff purse going negative is an accurate record of money created, and
    # the entry names who created it.
    module Payment

      def self.plan(payer, payee, amount, at: Time.now)
        amount = amount.to_i

        return Pf2e::Err.new(:bad_value, 'pf2egear.bad_value') unless amount.positive?

        unless covers?(payer, amount)
          return Pf2e::Err.new(:insufficient, 'pf2egear.not_enough_you', 'item' => 'money')
        end

        Pf2e::Ok.new(:state => halves(payer, payee, amount, reference(at)))
      end

      # Staff have unlimited funds; everyone else needs the coin.
      def self.covers?(payer, amount)
        return true if payer.is_admin?

        payer.pf2_money.to_i >= amount
      end

      def self.halves(payer, payee, amount, ref)
        [
          { 'char' => payer, 'amount' => -amount, 'by' => payee.name, 'reason' => "Payment to #{payee.name}", 'ref' => ref },
          { 'char' => payee, 'amount' => amount, 'by' => payer.name, 'reason' => "Payment from #{payer.name}", 'ref' => ref }
        ]
      end

      def self.reference(at)
        "transfer-#{at.to_i}-#{rand(100000)}"
      end

      # The imperative half: post both rows. Nothing decides anything here.
      def self.post!(halves)
        halves.each do |half|
          Pf2egear.pay_player(half['char'], half['amount'], half['by'], half['reason'], half['ref'])
        end
      end
    end
  end
end
