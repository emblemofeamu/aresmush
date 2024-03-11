module AresMUSH
  module Pf2e

    class PF2EncounterEndCmd
      include CommandHandler

      attr_accessor :encounter_id

      def parse_args
        self.encounter_id = integer_arg(cmd.args)
      end

      def handle

        # If they didn't specify the encounter ID, go get it.

        scene = enactor_room.scene

        encounter = self.encounter_id ?
          PF2Encounter[self.encounter_id] :
          PF2Encounter.get_encounter_ID(enactor, scene)

        if !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        if !PF2Encounter.is_organizer?(enactor, encounter)
          client.emit_failure t('pf2e.not_organizer')
          return
        end

        # Do it.

        encounter.update(is_active: false)

        message = t('pf2e.encounter_complete', :id => encounter.id)

        # Emit to the room.
        enactor_room.emit message

        # Log message to the encounter.
        PF2Encounter.send_to_encounter(encounter, message)

        # Log the message to the scene as an OOC message.
        Scenes.add_to_scene(scene, message, Game.master.system_character, false, true)

        # Notify all participants.
        Global.notifier.notify_ooc(:pf2_combat, message) do |char|
          char && scene.participants.include?(char)
        end

      end
    end
  end
end
