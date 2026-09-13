module AresMUSH
  module Pf2e

    class PF2AdminRollbackCmd
      include CommandHandler

      attr_accessor :character, :level

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.character = trim_arg(args.arg1)
        self.level = trim_arg(args.arg2)
      end

      def required_args
        [ self.character, self.level ]
      end

      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      def check_level_is_a_number
        return nil if self.level.to_s.match?(/\A\d+\z/)
        return t('pf2e.rollback_bad_level')
      end

      def handle
        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        target = self.level.to_i

        failure = Pf2e.can_rollback_to?(char, target)

        if failure
          client.emit_failure failure
          return
        end

        previous = target - 1
        refund = (char.pf2_level - previous) * Pf2e::ADVANCEMENT_XP_COST

        error = Pf2e.rollback_to_level(char, target, enactor)

        if error
          client.emit_failure error
          return
        end

        client.emit_success t('pf2e.rollback_ok',
          :name => char.name,
          :level => previous,
          :target => target,
          :xp => refund)

        # Tell them, if they are connected, since their sheet just changed underneath them.
        char_client = Login.find_game_client(char)
        char_client.emit_ooc t('pf2e.rollback_notice', :level => target) if char_client
      end

    end

  end
end
