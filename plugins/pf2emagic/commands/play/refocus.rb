module AresMUSH
  module Pf2emagic

    class PF2RefocusCmd
      include CommandHandler

      attr_accessor :character

      def parse_args
        self.character = trim_arg(cmd.args)
      end

      def check_permissions
        # Admins can do this on any character, others only on themselves.

        return nil if !self.character
        return nil if enactor.is_admin?
        return t('dispatcher.not_allowed')
      end

      def handle

        char = Pf2e.get_character(self.character, enactor)

        msg = Pf2emagic.do_refocus(char, enactor)

        if msg
          client.emit_failure msg
          return
        end

        client.emit_success t('pf2emagic.refocus_ok')

      end


    end

  end
end
