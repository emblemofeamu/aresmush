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

        # Which way is the money going? A negative value takes rather than gives.

        taking_money = self.value.negative?

        target_char = Pf2e.get_character(self.target, enactor)

        if !target_char
          client.emit_failure t('pf2egear.target_not_found', :name => self.target)
          return
        end

        payer, payee = taking_money ? [ target_char, enactor ] : [ enactor, target_char ]

        actual_value = Pf2egear.convert_money(self.value.abs, self.cointype)

        outcome = Pf2egear::Payment.plan(payer, payee, actual_value)

        if outcome.err?
          # The same refusal reads differently depending on who is short of money.
          if outcome.code == :insufficient && taking_money
            client.emit_failure t('pf2egear.not_enough_target', :target => payer.name, :item => 'money')
          else
            Pf2e::CharState.emit_error!(client, outcome)
          end
          return
        end

        Pf2egear::Payment.post!(outcome.state)

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

        recipient_msg = taking_money ?
          t('pf2egear.your_money_taken',
            :from => enactor.name,
            :value => self.value.abs,
            :cointype => self.cointype
          ) :
          t('pf2egear.you_got_money',
            :from => enactor.name,
            :value => self.value,
            :cointype => self.cointype
          )

        Login.notify(target_char, :pf2_money, recipient_msg, actual_value)

        recipient_client = Login.find_game_client(target_char)
        if recipient_client && target_char != enactor
          recipient_client.emit_ooc recipient_msg
        end

      end

    end
  end
end
