module AresMUSH
  module Pf2e

    class PF2EncounterRestartCmd
      include CommandHandler

      attr_accessor :encounter_id

      def parse_args
        self.encounter_id = integer_arg(cmd.args)
      end

      # Most of the encounter commands will try to fish for an encounter ID if none is given.
      # For this one, the encounter ID must be explicitly specified.

      def required_args
        [ self.encounter_id ]
      end

      def handle

        encounter = PF2Encounter[self.encounter_id]

        if !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        # Verify that this character can modify the encounter.

        cannot_modify = Pf2e.can_modify_encounter(enactor, encounter)
        if cannot_modify
          client.emit_failure cannot_modify
          return
        end

        # You cannot restart an encounter if the scene to which it is tied is not running.



        encounter.update(is_active: true)

        @message = t('pf2e.encounter_restarted', :id => encounter.id)

        # Emit to the room.
        enactor_room.emit @message

        # Log the init start in the encounter.
        PF2Encounter.send_to_encounter(encounter, @message)

        # Log the initiative message to the scene as an OOC message.
        Scenes.add_to_scene(scene, @message, Game.master.system_character, false, true)

        # Notify all participants that an encounter has started.
        Global.notifier.notify_ooc(:pf2_combat, @message) do |char|
          char && scene.participants.include?(char)
        end

      end



    end

  end
end
