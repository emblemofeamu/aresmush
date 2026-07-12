$:.unshift File.dirname(__FILE__)

module AresMUSH
  module LookingForRp

    def self.plugin_version
      "1.0"
    end

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config("lookingforrp", "shortcuts")
    end

    def self.install_setup
      Character.all.each { |c| c.update(looking_for_rp_announce: 'on') }
    end

    def self.get_cmd_handler(client, cmd, enactor)
      case cmd.root
      when 'lookingforrp'
        case cmd.switch
        when "off"
          return LookingForRpOffCommand
        when "text"
          return LookingForRpTextCommand
        when "announce"
          return LookingForRpAnnounceCommand
        when nil
          return LookingForRpCommand
        end


      end
      nil
    end

    def self.get_event_handler(event_name)
      case event_name
      when "CronEvent"
        return LookingForRpCronEventHandler
      end
      nil
    end

    def self.get_web_request_handler(request)
      case request.cmd
      when "setLFRP"
        return SetLFRPHandler
      when "unsetLFRP"
        return UnsetLFRPHandler
      when "LFRPData"
        return LookingForRpRequestHandler
      else 
        nil
      end
    end

  end
end
