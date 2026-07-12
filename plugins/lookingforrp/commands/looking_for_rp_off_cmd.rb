module AresMUSH
  module LookingForRp
    class LookingForRpOffCommand
      include CommandHandler

      def handle
        LookingForRp.expire(enactor)
        client.emit_success t('lookingforrp.expire')
      end

    end
  end
end
