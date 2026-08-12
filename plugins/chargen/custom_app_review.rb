module AresMUSH
  module Chargen
    def self.custom_app_review(char)

      list = []

      ## Did they register?

      if char.player
        altlist = char.player.characters.map { |n| n.name }.sort.join(", ") 
        reg_msg = t('alttracker.app_registration_ok', :alts => altlist)
      else
        reg_msg = t('chargen.oops_missing', :missing => "registration")
      end

      list << Chargen.format_review_status(t('alttracker.reg_check'), reg_msg)


      return list.join("%r")
    end
  end
end
