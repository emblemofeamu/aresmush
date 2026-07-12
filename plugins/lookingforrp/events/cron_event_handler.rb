module AresMUSH
  module LookingForRp
    class LookingForRpCronEventHandler

      def on_event(event)
        looking_for_rp_cron = Global.read_config("lookingforrp", "cron")
       if Cron.is_cron_match?(looking_for_rp_cron, event.time)
          Global.logger.debug "Expiring Looking for RP flags."

          chars = LookingForRp.chars_looking_for_rp.select { |c| c.looking_for_rp_expires_at < Time.now }

          chars.each do |c|
            Global.logger.debug "Expiring Looking for RP flag for #{c.name}"
            LookingForRp.expire(c)
          end
        end
      end

    end
  end
end
