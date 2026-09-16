module AresMUSH
  module Pf2e

    class PF2AdvanceLanguageCmd
      include CommandHandler

      attr_accessor :language

      def parse_args
        self.language = titlecase_arg(cmd.args)
      end

      def required_args
        [ self.language ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :advance_language, 'language' => self.language)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)
        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
