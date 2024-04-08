module AresMUSH
  module Pf2e
    class PF2LanguageUnSetCmd
      include CommandHandler

      attr_accessor :language

      def parse_args
        self.language = titlecase_arg(cmd.args)
      end

      def required_args
        [ self.language ]
      end

      def check_chargen_or_advancement
        if enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def check_abilinfolock
        return t('pf2e.lock_abil_first') if !enactor.pf2_abilities_locked
        return nil
      end

      def handle
        ##### VALIDATION SECTION #####

        # Verify that this character's options left to assign include the listed type.

        to_assign = enactor.pf2_to_assign

        open_languages = to_assign['open languages']

        if !open_languages
          client.emit_failure t('pf2e.cannot_assign_type', :element=>"language")
          return
        end

        # Can the character change that language?

          loc = open_languages.index(self.language)

          if !(loc)
            client.emit_failure t('pf2e.not_in_list', :option=>self.language)
            return
          end

        ##### VALIDATION SECTION END #####

        char_languages = enactor.pf2_lang

        char_languages.delete(self.language)
        open_languages[loc] = 'open'

        to_assign['open languages'] = open_languages

        enactor.pf2_lang = char_languages
        enactor.pf2_to_assign = to_assign

        enactor.save

        client.emit_success t('pf2e.reset_ok', :option=>self.language, :element=>'language')
      end

    end
  end
end
