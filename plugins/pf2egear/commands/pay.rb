module AresMUSH
  module Pf2egear
    class PF2PayCmd
      include CommandHandler

      attr_accessor :cointype, :target, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.target = titlecase_arg(args.arg1)

        money = args.arg2 ? list_arg(args.arg2): []
        self.value = integer_arg(money[0])
        self.cointype = downcase_arg(money[1])
      end

      def required_args
        [ self.target, self.cointype, self.value ]
      end

      def check_valid_value
        return nil unless self.value.zero?
        return t('pf2egear.bad_value')
      end

      def check_valid_cointype
        cointypes = %w(pp platinum gp gold sp silver cp copper)

        return nil if cointypes.include?(self.cointype)
        return t('pf2egear.bad_cointype')
      end

      def check_can_pay
        # A negative value in this command takes money.
        # Usually only admins can do this.
        return nil if self.value.positive?
        return nil if enactor.has_permission?('take_money')
        return t('dispatcher.not_allowed')
      end

      def handle

        # Which way is the money going?

        taking_money = self.value.negative?

        target_char = Pf2e.get_character(self.target, enactor)

        if taking_money
          payer = target_char
          payee = enactor
        else
          payer = enactor
          payee = target_char
        end

        staff_payer = payer.is_admin?
        staff_payee = payee.is_admin?

        # Does the person paying have enough money?
        from_purse = payer.pf2_money

        has_enough = true if staff_payer || (from_purse - self.value) >= 0

        if !has_enough
          fail_msg = taking_money ?
            t('pf2egear.not_enough_target',
            :target => payer.name,
            :item=>'money'
            ) :
            t('pf2egear.not_enough_you',
            :item => 'money'
          )

          client.emit_failure fail_msg
          return
        end

        # Let's do it.

        to_purse = payee.pf2_money

        actual_value = Pf2egear.convert_money(self.value, self.cointype)

        from_purse = from_purse - actual_value

        to_purse = to_purse + actual_value

        # Don't bother tracking money totals for a staffer.
        payer.update(pf2_money: from_purse) unless staff_payer
        payee.update(pf2_money: to_purse) unless staff_payee

        success_msg = taking_money ?
                t('pf2egear.money_taken_ok',
                  :cointype => self.cointype,
                  :value => self.value.abs,
                  :payer => payer.name
                ) :
                t('pf2egear.money_paid_ok',
                  :cointype => self.cointype,
                  :value => self.value,
                  :payee => payee.name
                )

        client.emit_success success_msg

        recipient_msg = t('pf2egear.you_got_money',
          :from => enactor.name,
          :value => self.value,
          :cointype => self.cointype
        )

        Pf2egear.record_money_history(payee, payer.name, actual_value, "Payment from #{payer.name}")

        Login.notify(target_char, :pf2_money, recipient_msg, actual_value)

      end

    end
  end
end
