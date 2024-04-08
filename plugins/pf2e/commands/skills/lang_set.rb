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

        # Is the argument a language that this character can choose?

        all_lang = Global.read_config('pf2e_languages')
        avail_lang_keys = Global.read_config('pf2e', 'can_select_language')

        avail_lang = []

        avail_lang_keys.each do |key|
          langs = all_lang[key]
          langs.keys.each do |l|
            avail_lang << l
          end
        end

        if !avail_lang.include?(self.language)
          client.emit_failure t('pf2e.bad_option',
            :element=>'language',
            :options=>avail_lang.sort.join(", ")
          )
          return
        end

        # Verify that this character's options left to assign include the listed type.

        to_assign = enactor.pf2_to_assign

        open_languages = to_assign['open languages']

        if !open_languages
          client.emit_failure t('pf2e.cannot_assign_type', :element=>"language")
          return
        end

        # Does that character already have that language?

        char_languages = enactor.pf2_lang

        if char_languages.include?(self.language)
          client.emit_failure t('pf2e.already_has', :item => 'language')
          return
        end

        # Does this character have an available open language to assign?

          loc = open_languages.index("open")

          if !(loc)
            client.emit_failure t('pf2e.no_free', :element=>'open languages')
            return
          end

        ##### VALIDATION SECTION END #####

        char_languages << self.language
        open_languages[loc] = self.language

        to_assign['open languages'] = open_languages

        enactor.pf2_lang = char_languages
        enactor.pf2_to_assign = to_assign

        enactor.save

        client.emit_success t('pf2e.add_ok', :item=>self.language, :list=>'languages')
      end

    end
  end
end
