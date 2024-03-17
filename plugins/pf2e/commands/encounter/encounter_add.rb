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

        encounter = self.encounter_id ?
          PF2Encounter[self.encounter_id] :
          PF2Encounter.get_encounter(enactor, scene)

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

        # Verify that this character can modify the encounter.

        cannot_modify = Pf2e.can_modify_encounter(enactor, encounter)
        if cannot_modify
          client.emit_failure cannot_modify
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
