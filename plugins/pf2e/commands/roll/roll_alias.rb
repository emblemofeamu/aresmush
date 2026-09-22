module AresMUSH
  module Pf2e

    class PF2ChangeRollAliasCmd
      include CommandHandler

      attr_accessor :rollalias, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_optional_arg2)

        self.rollalias = trim_arg(args.arg1)
        self.value = trim_arg(args.arg2)
      end

      def required_args
        [ self.rollalias ]
      end

      # Disabled for playtest
      # def check_approval
        # return nil if (enactor.is_approved?) || (enactor.is_admin?)
        # return t('chargen.not_approved')
      # end

      def check_is_word
        return nil if self.rollalias.to_i.zero?
        return t('pf2e.must_be_word')
      end

      def handle
        before = Pf2e::CharState.of(enactor)
        action = self.value ? :set_record : :unset_record

        outcome = Pf2e::CharacterService.call(before, action,
          'record' => 'alias', 'key' => self.rollalias, 'value' => self.value)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)
        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
