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
        found = Pf2e::Encounters::Finder.find(enactor, scene, self.encounter_id)

        return if Pf2e::CharState.emit_error!(client, found)

        encounter = found.state

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
