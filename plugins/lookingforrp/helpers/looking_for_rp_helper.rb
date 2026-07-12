module AresMUSH
  module LookingForRp

    def self.set(char, duration, type="scene")
      end_at = LookingForRp.end_at(duration)
      char.update(looking_for_rp_expires_at: end_at)
      char.update(looking_for_rp: true)
      char.update(looking_for_rp_type: type)
      data = {
        lfrp_icons: LookingForRp.web_list,
        type: 'lfrp_set'
      }
      Global.client_monitor.notify_web_clients(:new_lfrp_activity, "#{data.to_json}", true) do |char|
        true 
      end
    end

    def self.end_at(duration)
      Time.now + duration.hour
    end

    def self.expire(char)
      char.update(looking_for_rp: false)
      data = {
        lfrp_icons: LookingForRp.web_list,
        type: 'lfrp_expired'
      }
      Global.client_monitor.notify_web_clients(:new_lfrp_activity, "#{data.to_json}", true) do |char|
        true 
      end
    end

    def self.is_lfrp(char)
      if !char
        false
      else
        char.is_looking_for_rp
      end
    end

    def self.chars_looking_for_rp
      Chargen.approved_chars.select { |c| c.looking_for_rp == true }
    end

    def self.type_marker(char)
      case char.looking_for_rp_type
      when "scene"
        return ""
      when "text"
        return "#"
      end
    end

    def self.web_list
      chars_looking_for_rp.map { |c| { name: c.name, icon: Website.icon_for_char(c) , lfrp_type: c.looking_for_rp_type} }
    end

    def self.char_names
      chars_looking_for_rp.map { |c| c.name }
    end

    def build_web_LFRP_data(char)
      {
        name: char.name,
        icon: Website.icon_for_char(char),
        lfrp_type: char.looking_for_rp_type
      }
    end

    def self.announce_toggle_on(char)
      char.update(looking_for_rp_announce: "on")
    end

    def self.announce_toggle_off(char)
      char.update(looking_for_rp_announce: "off")
    end

  end
end