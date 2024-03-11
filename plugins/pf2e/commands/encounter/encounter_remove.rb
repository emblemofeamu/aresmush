module AresMUSH
  module Pf2e

    class PF2EncounterRemoveCmd
      include CommandHandler

      attr_accessor :name, :encounter_id

      def parse_args
        args = trimmed_list_arg(cmd.args, "=")

        # If only one arg is given, encounter_id is the nil.
        args.unshift(nil) unless args[1]

        self.encounter_id = integer_arg(args[0])
        self.name = downcase_arg(args[1])
      end

      def required_args
        [ self.name ]
      end

      def handle

        # If they didn't specify the encounter ID, go get it.

        scene = enactor_room.scene

        encounter = self.encounter_id ?
          PF2Encounter[self.encounter_id] :
          PF2Encounter.get_encounter_id(enactor, scene)

        if !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        # The enactor needs to be the organizer.

        if !PF2Encounter.is_organizer?(enactor, encounter)
          client.emit_failure t('pf2e.not_organizer')
          return
        end

        initlist = encounter.participants

        index = initlist.index { |i| i[1].downcase.match? self.name }

        if !index
          client.emit_failure t('pf2e.not_found')
          return
        end

        PF2Encounter.remove_from_initiative(encounter, index)

        client.emit_success t('pf2e.encounter_remove_ok',
          :encounter => encounter.id,
          :name => initlist[index][1]
        )

      end

    end
  end
end
