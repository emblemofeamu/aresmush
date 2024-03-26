module AresMUSH
  module Pf2e
    class PF2CronEventHandler

      def on_event(event)

        if (Cron.is_cron_match?(Global.read_config("pf2e", "daily_prep_cron"), event.time))
          Character.all.each do |char|
            if !(char.is_admin) && char.is_approved? && char.pf2_auto_refresh

              msg = PF2e.do_daily_prep(char)

              datetime = OOCTime.local_short_date_and_time(char, Time.now)

              msg = t('pf2e.autorest_done', :time => datetime) unless msg

              Login.notify(char, :daily_prep, msg, char.id)
            end
          end
        end

      end

    end
  end
end
