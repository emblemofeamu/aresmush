module AresMUSH
  module Pf2e

    class PF2KnownForCmd
      include CommandHandler

      attr_accessor :character, :blurb

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.character = trim_arg(args.arg1)
        self.blurb = trim_arg(args.arg2)
      end

      def required_args
        [ self.character, self.blurb ]
      end

      def check_is_admin
        return nil if enactor.is_admin?
        return t('dispatcher.not_allowed')
      end

      def handle

        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        before = Pf2e::CharState.of(char)
        outcome = Pf2e::CharacterService.call(before, :add_record, 'record' => 'known_for', 'value' => self.blurb)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(char, before, outcome)
        Pf2e::CharState.emit_messages!(client, outcome)

      end

    end

  end
end