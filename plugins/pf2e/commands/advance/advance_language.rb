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
        # Is the argument a language that this character can choose?
        all_lang = Global.read_config('pf2e_languages')
        avail_lang_keys = Global.read_config('pf2e', 'can_select_language')

        avail_lang = []

        avail_lang_keys.each do |key|
          langs = all_lang[key]
          langs.keys.each do |lang|
            avail_lang << lang
          end
        end

        if !avail_lang.include?(self.language)
          client.emit_failure t('pf2e.bad_option',
            :element=>'language',
            :options=>avail_lang.sort.join(", ")
          )
          return
        end

        to_assign = enactor.pf2_to_assign || {}
        advancement = enactor.pf2_advancement || {}

        open_languages = to_assign['open languages']

        if !open_languages
          client.emit_failure t('pf2e.cannot_assign_type', :element=>"language")
          return
        end

        open_languages = Array(open_languages)

        selected_languages = Array(advancement['languages'])
        current_languages = Array(enactor.pf2_lang) + selected_languages

        if current_languages.any? { |lang| lang.to_s.casecmp?(self.language) }
          client.emit_failure t('pf2e.already_knows_language', :language => self.language)
          return
        end

        open_loc = open_languages.index { |lang| lang.to_s.casecmp?('open') }

        if open_loc.nil?
          client.emit_failure t('pf2e.no_free', :element=>'open languages')
          return
        end

        open_languages[open_loc] = self.language
        to_assign['open languages'] = open_languages

        selected_languages = (selected_languages + [self.language]).uniq { |lang| lang.to_s.downcase }
        advancement['languages'] = selected_languages

        enactor.update(pf2_to_assign: to_assign)
        enactor.update(pf2_advancement: advancement)

        client.emit_success t('pf2e.add_ok', :item=>self.language, :list=>'languages')
      end

    end
  end
end
