module AresMUSH
  module Pf2e

    class PF2InitJoinCmd
      include CommandHandler

      attr_accessor :encounter_id, :init_stat

      def parse_args
        # Another command that Faraday's argparser doesn't touch, so we roll our own.

        if cmd.args
          args = trimmed_list_arg(cmd.args, "=")

          if args.size >= 2
            self.encounter_id = integer_arg(args[0])
            self.init_stat = trim_arg(args[1])
            # And throw out anything else.
          else
            # If only one option is given, if it translates to a number, interpret as an encounter ID.
            # Otherwise, interpret as an init stat.

            unknown = args[0]

            if (unknown.to_i.to_s == unknown)
              self.encounter_id = integer_arg(unknown)
            else
              self.init_stat = unknown
            end
          end

        end

      end

      def handle
        scene = enactor_room.scene

        encounter = self.encounter_id ?
          PF2Encounter[self.encounter_id] :
          PF2Encounter.get_encounter(enactor, scene)

        if !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        # Can the character join this encounter?

        cannot_join = Pf2e.can_join_encounter(enactor, encounter)

        if cannot_join
          client.emit_failure t('pf2e.encounter_cannot_join', :reason => cannot_join, :id => encounter.id)
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
