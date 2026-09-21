module AresMUSH
  module Pf2e

    # Settles one of the things the archetype's Dedication feat left open: its specialty, that
    # specialty's own choice, the key ability for its class DC, its deity, its sanctification.
    #
    # Which values are legal and what the pick does to the draft is Advancement::ArchetypePicks.
    # What the pick then hands over - trained skills, spellcasting, granted feats and features -
    # goes through Advancement::Onboarding, the same rows that apply an archetype's own
    # dedication block, and that half needs the live character rather than the draft.
    class PF2AdvanceArchetypeCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :type, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.type = downcase_arg(args.arg1)
        self.value = downcase_arg(args.arg2)
      end

      def required_args
        [ self.type, self.value ]
      end

      def handle
        state = Pf2e::CharState.of(enactor)

        outcome = Pf2e::Advancement::ArchetypePicks.set(state, self.type, self.value)
        return if Pf2e::CharState.emit_error!(client, outcome)

        to_assign = outcome.state['to_assign']
        advancement = outcome.state['advancement']

        # Skills go through the training helper, spellcasting through the magic object and
        # features onto the sheet, so this part takes the character. It adds to the same two
        # draft hashes, which are then written once.
        messages = Pf2e::Advancement::ArchetypePicks.deliver(enactor, outcome.state, self.type)

        enactor.pf2_archetypeinfo = outcome.state['archetypes']
        enactor.pf2_to_assign = to_assign
        enactor.pf2_advancement = advancement
        enactor.save

        Pf2e::Advancement::FeatGain.emit!(client, messages)
        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end

  end
end
