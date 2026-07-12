module AresMUSH
  module Scenes
    
    def self.custom_scene_data(viewer)
      return {
        lfrp_icons: LookingForRp.web_list,
        txt_extra_installed: Manage.is_extra_installed?("txt")
      }
    end
  end
end
