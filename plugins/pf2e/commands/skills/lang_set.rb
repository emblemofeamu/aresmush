module AresMUSH
  module Pf2e
    class PF2LanguageSetCmd
      include CommandHandler

      attr_accessor :language

      def parse_args
        self.language = titlecase_arg(cmd.args)
      end

      def check_chargen_or_advancement
        if enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif !Pf2e.in_chargen?(enactor)
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def check_abilinfolock
        return t('pf2e.lock_abil_first') if !enactor.pf2_abilities_locked
        return nil
      end

      # Shell only: the rules live in Pf2e::Chargen::Languages and are unit tested there.
      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :learn_language, 'language' => self.language)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome, :source_type => 'chargen', :source_ref => 'language pick', :effective_level => 1)
        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
