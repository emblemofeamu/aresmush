module AresMUSH
  module Pf2e

    # Where a finished roll message goes, as opposed to how it is calculated. The roll math lives in utils.rb.
    #
    # Private rolls skip all of it and are emitted to the client directly by the command, and logging stays with the commands too, since a private roll is still logged.

    # Sends a roll message to the room, to the room's scene and any encounter active in it, and to the roll channel if one is configured.
    def self.broadcast_roll(room, msg)
      room.emit msg

      scene = room.scene

      if scene
        Scenes.add_to_scene(scene, msg)

        active_encounter = PF2Encounter.scene_active_encounter(scene)
        PF2Encounter.send_to_encounter(active_encounter, msg) if active_encounter
      end

      channel = Global.read_config("pf2e", "roll_channel")
      Channels.send_to_channel(channel, msg) if channel
    end

  end
end
