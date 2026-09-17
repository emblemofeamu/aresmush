module AresMUSH
  module Pf2e
    class PF2RestoreChargenCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :checkpoint

      def parse_args
        self.checkpoint = downcase_arg(cmd.args)
      end

      # Which stages may be rewound to, and whether this character has reached one, is
      # Pf2e::Chargen::Lifecycle.restore. The replay itself is still Pf2e.restore_checkpoint.
      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :restore_stage, 'checkpoint' => self.checkpoint)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e.restore_checkpoint(enactor, self.checkpoint)

        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
