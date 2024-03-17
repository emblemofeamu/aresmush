module AresMUSH
  module Pf2e

    class PF2EncounterExpireBonusesCmd
      include CommandHandler

      attr_accessor :encounter_id, :term

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_optional_arg2)

        if args.arg2
          self.encounter_id = integer_arg(args.arg1)
          self.term = downcase_arg(args.arg2)
        else
          self.encounter_id = nil
          self.term = downcase_arg(args.arg1)
        end
      end

      def required_args
        [ self.term ]
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

        # Keep separate so that I know which list to modify.
        bonuses = encounter.bonuses
        penalties = encounter.penalties

        delete_bonus = bonuses.keys.select { |b| b.downcase.match? self.term }
        delete_penalty = penalties.keys.select { |p| p.downcase.match? self.term }

        delete_bonus.each do |item|
          bonuses.delete(item)
        end

        delete_penalty.each do |item|
          penalties.delete(item)
        end

        encounter.update(bonuses: bonuses)
        encounter.update(penalties: penalties)

        client.emit_success t('pf2e.encounter_notes_ok', :mod => 'Updated', :id => encounter.id)

      end
    end
  end
end
