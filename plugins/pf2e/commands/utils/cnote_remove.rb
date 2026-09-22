module AresMUSH
  module Pf2e
    class PF2RemoveCnoteCmd
      include CommandHandler

      attr_accessor :character, :notename

      def parse_args
        # Argument pattern: [character/]notename
        args = trimmed_list_arg(cmd.args,"/")

        char_specified = args[1] ? true : false

        self.character = char_specified ? args[0] : nil
        self.notename = char_specified ? downcase_arg(args[1]) : downcase_arg(args[0])
      end

      def required_args
        [ self.notename ]
      end

      def

      def check_permissions
        # Any character may view their own; only people who can see alts can see others'.

        return nil if !self.character
        return nil if enactor.has_permission?('manage_alts')
        return t('dispatcher.not_allowed')
      end

      def handle

        # If no argument, code assumes reference is to self.

        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        before = Pf2e::CharState.of(char)
        outcome = Pf2e::CharacterService.call(before, :unset_record, 'record' => 'cnote', 'key' => self.notename)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(char, before, outcome)
        Pf2e::CharState.emit_messages!(client, outcome)

      end
    end
  end
end
