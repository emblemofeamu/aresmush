module AresMUSH
  module Pf2e

    # A command whose change to an encounter goes on the encounter's history, so the GM can take it back.
    #
    # Its handler runs inside `History.recording`, in the encounter it names by id or else the one here,
    # and the entry says who typed what. Everyone's sheet is read once between its writes
    # (`SheetReads.during`).
    module Recorded
      def handle
        SheetReads.during { History.recording(recorded_encounter, "#{enactor.name}: #{cmd.raw}") { super } }
      end

      def recorded_encounter
        named = respond_to?(:encounter_id) ? self.encounter_id : nil

        (named.is_a?(Integer) || named.is_a?(String)) && !named.to_s.empty? ? PF2Encounter[named] : Combatants.encounter_here(enactor)
      end
    end

    # A command or a page reads each sheet once between its writes (`SheetReads.during`). The plugin
    # hands out every handler of its own through `wrapped`, so none is left out whatever order they load.
    module ReadsOnce
      def handle(*args)
        SheetReads.during { super }
      end

      def self.wrapped(handler)
        handler.prepend(self) if handler.is_a?(Class) && !(handler < self)
        handler
      end
    end

    # Every command that changes an encounter. Held here, after the commands load, rather than in each.
    [ PF2EncounterActCmd, PF2EncounterStrikeCmd, PF2EncounterCastCmd, PF2EncounterReloadCmd, PF2EncounterAsCmd, PF2EncounterAuraCmd,
      PF2EncounterCoverCmd, PF2EncounterConcealCmd, PF2EncounterTrustCmd, PF2EncounterOptionCmd,
      PF2InitJoinCmd, PF2EncounterAddCmd, PF2EncounterAdjustCmd, PF2EncounterAfflictionCmd, PF2EncounterNextCmd, PF2EncounterPrevCmd, PF2InitModCmd,
      PF2EncounterRemoveCmd, PF2EncounterResyncCmd, PF2DamagePlayerCmd, PF2HealPlayerCmd, PF2ConditionSetCmd, PF2EffectAddCmd,
      PF2EffectRemoveCmd, PF2EncounterRestCmd, PF2EncounterRefocusCmd ].each { |command| command.prepend(Recorded) }
  end
end
