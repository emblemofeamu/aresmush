module AresMUSH
  module Pf2e

    class PF2InitJoinCmd
      include CommandHandler

      attr_accessor :encounter_id, :init_stat

      def parse_args
        args = trimmed_list_arg(cmd.args, "=")

        self.encounter_id = integer_arg(args[0])
        self.init_stat = args[1]

      end

      def required_args
        [ self.encounter_id ]
      end

      def handle
        encounter = PF2Encounter[self.encounter_id]

        if !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        # Can the character join this encounter?

        cannot_join = Pf2e.can_join_encounter(enactor, encounter)

        if cannot_join
          client.emit_failure t('pf2e.encounter_cannot_join', :reason => cannot_join, :id => self.encounter_id)
          return
        end

        # If they specified an init stat, error if invalid, otherwise use the one
        # specified by the organizer.

        init_stat = self.init_stat ? self.init_stat : encounter.init_stat

        if !Pf2e.is_valid_init_stat?(init_stat)
          client.emit_failure t('pf2e.not_unique')
          return
        end

        # Calculate initiative and add the enactor to the encounter participants list.
        roll = [ "1d20", init_stat ]

        initiative = Pf2e.parse_roll_string(enactor, roll)['total']

        PF2Encounter.add_to_initiative(encounter, enactor.name, initiative)

        # Set management for later use.

        enactor.encounters.add encounter
        encounter.characters.add enactor

        @message = t('pf2e.encounter_joined_ok',
          :roll => initiative,
          :encounter => encounter.id,
          :name => enactor.name
        )

        # Emit to the room.
        enactor_room.emit @message

        # Log to the encounter.
        PF2Encounter.send_to_encounter(encounter, @message)

        # Log to the scene as an OOC message.

        scene = encounter.scene
        Scenes.add_to_scene(scene, @message, Game.master.system_character, false, true)

      end
    end
  end
end
