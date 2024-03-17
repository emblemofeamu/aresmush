module AresMUSH
  module Pf2e

    class PF2InitViewCmd
      include CommandHandler

      attr_accessor :encounter_id

      def parse_args
        self.encounter_id = integer_arg(cmd.args)
      end

      def check_valid_encounter
        # They don't have to specify an encounter ID, but if they do, make sure it's valid.
        return nil unless self.encounter_id
        return nil if PF2Encounter[self.encounter_id]
        return t('pf2e.bad_id', :type => 'encounter')
      end

      def handle

        encounter = self.encounter_id ? PF2Encounter[self.encounter_id] : PF2Encounter.get_encounter(enactor, enactor_room.scene)

        # You need to either specify the encounter to view by ID or be in an active encounter.

        if !encounter
          client.emit_failure t('pf2e.not_in_active_encounter')
          return
        end

        template = PF2EncounterViewTemplate.new(encounter, client)

        client.emit template.render

      end

    end
  end
end
