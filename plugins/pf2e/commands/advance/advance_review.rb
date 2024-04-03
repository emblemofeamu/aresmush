module AresMUSH
  module Pf2e

    class PF2AdvanceReviewCmd
      include CommandHandler

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        template = PF2AdvanceReviewTemplate.new(enactor)
        client.emit template.render
      end


    end
  end
end
