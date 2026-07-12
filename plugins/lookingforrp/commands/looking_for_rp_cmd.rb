module AresMUSH
  module LookingForRp
    class LookingForRpCommand
      include CommandHandler

      attr_accessor :duration

      def parse_args
        self.duration = case cmd.args
            when 'off'
              nil
            when nil
              1
            else
              cmd.args.to_i
            end
      end

      def check_errors
        puts " Duration #{self.duration} #{!self.duration}"
        return "Incorrect syntax. See 'qr lookingforrp' for help." if self.duration && !self.duration.integer?
        return "You can't set yourself 'Looking for RP' for longer than 3 hours." if duration.to_i > 3
      end

      def handle
        puts " Duration #{self.duration}"
        if self.duration.nil?
          LookingForRp.expire(enactor)
          client.emit_success t('lookingforrp.expire')
        else
          LookingForRp.set(enactor, self.duration.to_i)
          client.emit_success t('lookingforrp.set', :duration => self.duration)
          if enactor.looking_for_rp_announce == "on"
            Channels.send_to_channel("RP Requests", t('lookingforrp.rp_request_emit', :name => enactor.name, :duration => self.duration))
          end
        end
      end
    end
  end
end
