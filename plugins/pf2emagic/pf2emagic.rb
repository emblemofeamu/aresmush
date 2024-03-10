$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Pf2emagic

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config("pf2emagic", "shortcuts")
    end

    def self.get_cmd_handler(client, cmd, enactor)
      case cmd.root
      when "addspell"
        return PF2ChargenSpellsCmd
      when "prepare"
        return PF2PrepareSpellCmd
      when "unprepare"
        return PF2UnprepareSpellCmd
      when "spell"
        return PF2DisplaySpellCmd
      when "magic"
        return PF2MagicDisplayCmd
      when "refocus"
        return PF2RefocusCmd
      when "spellbook"
        return PF2MagicSpellbookCmd
      when 'dfont'
        return PF2DivineFontCmd
      end
    end

    def self.get_event_handler(event_name)
      nil
    end

    def self.get_web_request_handler(request)
      nil
    end

  end
end
