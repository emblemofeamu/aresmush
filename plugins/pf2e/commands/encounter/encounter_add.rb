module AresMUSH
  module Pf2e

    class PF2EncounterAddCmd
      include CommandHandler

      attr_accessor :name, :mod, :encounter_id

      def parse_args
        args = trimmed_list_arg(cmd.args, "=")

        # If only two args are given, encounter_id is the nil.
        args.unshift(nil) unless args[2]

        self.encounter_id = integer_arg(args[0])
        self.name = titlecase_arg(args[1])
        self.mod = integer_arg(args[2])
      end

      def required_args
        [ self.name, self.mod ]
      end

      def handle

        # If they didn't specify the encounter ID, go get it.

        scene = enactor_room.scene

        encounter = self.encounter_id ? PF2Encounter[self.encounter_id] : PF2Encounter.get_encounter_id(enactor, scene)

        if !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        # The enactor needs to be the organizer.

        if !PF2Encounter.is_organizer?(enactor, encounter)
          client.emit_failure t('pf2e.not_organizer')
          return
        end

        initiative = Pf2e.roll_dice.sum + self.mod

        PF2Encounter.add_to_initiative(encounter, self.name, initiative, true)

        client.emit_success t('pf2e.encounter_add_ok',
          :roll => initiative.to_i,
          :encounter => encounter.id,
          :name => self.name
        )
      end

    end
  end
end
