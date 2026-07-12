module AresMUSH
  module LookingForRp
    class SetLFRPHandler
      def handle(request)
        puts request.args
        enactor = request.enactor
        time = request.args['hours'].to_i
        type = request.args['textType']

        error = Website.check_login(request)
        return error if error

        if !type
          LookingForRp.set(enactor, time)
          if enactor.looking_for_rp_announce == "on"
            Channels.send_to_channel("RP Requests", t('lookingforrp.rp_request_emit', :name => enactor.name, :duration => time))
          end
        else
          LookingForRp.set(enactor, time, "text")
          if enactor.looking_for_rp_announce == "on"
            Channels.send_to_channel("RP Requests", t('lookingforrp.rp_request_emit_txt', :name => enactor.name, :duration => time))
          end
        end
        {
        }
      end
    end
  end
end