module AresMUSH
  module Pf2e

    class PF2AdminResetCmd
      include CommandHandler

      attr_accessor :character

      def parse_args
        self.character = trim_arg(cmd.args)
      end

      def required_args
        [ self.character ]
      end

      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      def handle
        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        Pf2e.reset_character(char)

        client.emit_success t('pf2e.admin_reset_ok', :name => char.name)

      end

    end

  end
end
