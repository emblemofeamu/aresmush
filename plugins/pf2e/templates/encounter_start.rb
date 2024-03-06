module AresMUSH
  module Pf2e

    class PF2EncounterStart < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :encounter

      def initialize(encounter)
        @encounter = encounter

        super File.dirname(__FILE__) + "/encounter_start.erb"
      end

      def title
        t('pf2e.encounter_start_title')
      end

      def init_stat
        @encounter.init_stat
      end

      def encounter_id
        @encounter.id
      end

      def organizer
        @encounter.organizer
      end

      def roll_init_cmd
        "init/join #{encounter_id}[=<alternate stat>]"
      end

    end
  end
end
