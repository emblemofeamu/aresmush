module AresMUSH
  module Pf2e
    class PF2EncounterScanCmd
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
          PF2Encounter.get_encounter_id(enactor, scene)

        if !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        if !PF2Encounter.is_organizer?(enactor, encounter)
          client.emit_failure t('pf2e.not_organizer')
          return
        end

        template = PF2EncounterScanTemplate.new(encounter)

        client.emit template.render

      end


    end
  end
end
