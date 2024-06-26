module AresMUSH
  module Pf2e

    class PF2EncounterBonusPenaltyCmd
      include CommandHandler

      attr_accessor :encounter_id, :bonus, :target_list

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_optional_arg2)

        if args.arg2
          self.encounter_id = integer_arg(args.arg1)
          list = trimmed_list_arg(args.arg2, "/")
          self.bonus = list[0]
          self.target_list = list[1]
        else
          self.encounter_id = nil
          list = trimmed_list_arg(args.arg1, "/")
          self.bonus = list[0]
          self.target_list = list[1]
        end
      end

      def required_args
        [ self.bonus, self.target_list ]
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

        if cmd.switch_is? "bonus"
          list = encounter.bonuses
          list[self.bonus] = self.target_list
          encounter.update(bonuses: list)
        elsif cmd.switch_is? "penalty"
          list = encounter.penalties
          list[self.bonus] = self.target_list
          encounter.update(penalties: list)
        else
          # Do nothing.
        end

        client.emit_success t('pf2e.encounter_notes_ok', :mod => cmd.switch.capitalize, :id => encounter.id)
      end


    end
  end
end
