module AresMUSH
  module Pf2e

    class PF2AdvanceFinishCmd
      include CommandHandler

      # Processes advancement and completes the process.

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        Pf2e.do_advancement(enactor, client)

        client.emit_success t('pf2e.advance_done')

      end

    end
  end
end
