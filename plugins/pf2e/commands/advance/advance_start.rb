module AresMUSH
  module Pf2e

    class PF2ADvancementStartCmd
      include CommandHandler

      def check_approval
        return nil if enactor.is_approved?
        return t('pf2e.not_approved')
      end

      def handle
        state = Pf2e::CharState.of(enactor)

        # Whether they are in an encounter is the one part only the live game can answer.
        blocked = Pf2e::Advancement::Plan.can_advance(state,
          'in_encounter' => PF2Encounter.in_active_encounter?(enactor))

        return if Pf2e::CharState.emit_error!(client, blocked)

        level = enactor.pf2_level + 1
        charclass = enactor.pf2_base_info['charclass']

        # What this level gives: the class table, with the specialty's own entry merged over
        # it where there is one.
        info = Pf2e::Advancement::Plan.for_level(state, level)

        # Staging the picks is still the legacy path; it writes the draft this level will
        # spend, and returns the lines telling the player what is now theirs to choose.
        msg = Pf2e.assess_advancement(enactor, info)

        client.emit_ooc msg.join("%r%%%b")
        client.emit_success t('pf2e.advance_started', :level => level, :charclass => charclass)

        template = Pf2e::PF2AdvanceReviewTemplate.new(enactor, client)
        client.emit template.render
      end

    end
  end
end
