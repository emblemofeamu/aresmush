module AresMUSH
  module Pf2e
    class PF2HealPlayerCmd
      include CommandHandler

      attr_accessor :target, :damage

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.target = trimmed_list_arg(args.arg1)
        self.damage = integer_arg(args.arg2)

      end

      def required_args
        [ self.target, self.damage ]
      end

      def check_is_approved
        return nil if (enactor.is_admin? || enactor.is_approved?)
        return t('dispatcher.not_allowed')
      end

      def check_valid_damage
        return nil if self.damage > 0
        return t('pf2e.bad_value', :item => 'healing amount')
      end

      def handle

        # This command does not check to see if players are capable of healing.
        # It may be necessary to lock this command if players are in an encounter.

        ok_char_list = []
        bad_char_list = []

        target.each do |item|
          char = ClassTargetFinder.find(item, Character, enactor)

          if (char.found?)
            Pf2eHP.modify_damage(char.target, self.damage, true)
            ok_char_list << char.target.name
          else
            bad_char_list << item
          end
        end

        if !(bad_char_list.empty?)
          client.emit_ooc t('pf2e.bad_value_in_list', :items => 'characters', :list => bad_char_list.sort.join(", "))
        end

        client.emit_success t('pf2e.healing_applied_ok', :list => ok_char_list.sort.join(", "), :amount => self.damage)

      end


    end
  end
end
