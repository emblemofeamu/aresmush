module AresMUSH
  module Pf2e

    class PF2AdvanceResetCmd
      include CommandHandler

      # This command has no args and simply clears all the advancement stuff they've done.

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        enactor.advancing = false
        enactor.pf2_advancement = {}
        enactor.pf2_to_assign = {}

        enactor.save

        client.emit_success t('pf2e.adv_reset_ok')

      end
    end
  end
end
