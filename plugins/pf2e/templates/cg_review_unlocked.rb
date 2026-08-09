module AresMUSH
  module Pf2e

    class PF2CGReviewUnlockDisplay < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :client

      def initialize(char, client)
        @char = char
        @client = client

        base_info = @char.pf2_base_info
        @ancestry = base_info['ancestry']
        @heritage = base_info['heritage']
        @background = base_info['background']
        @charclass = base_info['charclass']
        @subclass = base_info['specialize']
        @subclass_option = base_info['specialize_info']

        @ancestry_info = @ancestry.blank? ? {} : Global.read_config('pf2e_ancestry', @ancestry)
        @heritage_info = @heritage.blank? ? {} : Global.read_config('pf2e_heritage', @heritage)
        @background_info = @background.blank? ? {} : Global.read_config('pf2e_background', @background)
        @charclass_info = @charclass.blank? ? {} : Global.read_config('pf2e_class', @charclass)
        @subclass_info = @subclass.blank? ? {} : Global.read_config('pf2e_specialty', @charclass, @subclass)
        @faith_info = @char.pf2_faith

        @baseinfolock = @char.pf2_baseinfo_locked
        @class_features_info = @charclass_info['chargen']
        @subclass_features_info = @subclass_info['chargen']
        @to_assign = @char.pf2_to_assign
        @boosts = @char.pf2_boosts_working

        super File.dirname(__FILE__) + "/cg_review_unlocked.erb"
      end

      def baseinfolock
        @baseinfolock
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def name
        @char.name
      end

      def unset
      # Shown when there's an option the character still has to choose.
        "%xh%xrUNSET%xn"
      end

      def not_applicable
      # Shown when there's an option that doesn't apply, or can't be chosen until an earlier one is.
        "-"
      end

      def show(value)
        value.blank? ? unset : value
      end

      def base_info_set
      # Everything the character must choose has been chosen, so they can commit info.
        Pf2e.base_info_set?(@char.pf2_base_info, @faith_info)
      end

      def has_ancestry
        !@ancestry.blank?
      end

      def has_background
        !@background.blank?
      end

      def has_charclass
        !@charclass.blank?
      end

      def show_sofar
      # Ancestry sets size, speed and part of the HP; class sets the rest of it.
        has_ancestry || has_charclass
      end

      def hp_incomplete
      # HP is only complete once both ancestry and class are set, since each contributes part of the total.
        if has_ancestry && !has_charclass
          t('pf2e.cg_hp_incomplete_class')
        elsif has_charclass && !has_ancestry
          t('pf2e.cg_hp_incomplete_ancestry')
        end
      end

      def show_traits
      # Traits come from ancestry, heritage, and class.
        has_ancestry || has_charclass
      end

      def show_boosts
      # Boosts come from ancestry, background, and class.
        has_ancestry || has_background || has_charclass
      end

      def show_skills
      # Trained skills come from the character's class, class specialty, background, and (if a cleric or champion) deity.
        has_charclass || has_background
      end

      def show_other
      # Senses and special abilities come from the character's ancestry, heritage, and background; starting languages come from ancestry.
        has_ancestry || has_background
      end

      def ancestry
        show(@ancestry)
      end

      def heritage
        show(@heritage)
      end

      def background
        show(@background)
      end

      def charclass
        show(@charclass)
      end

      def subclass
        return not_applicable if !Pf2e.needs_specialty?(@charclass)
        show(@subclass)
      end

      def subclass_option
        return not_applicable if !Pf2e.needs_specialty_choice?(@charclass, @subclass)
        show(@subclass_option)
      end

      def deity
        return show(@faith_info['deity']) if use_deity
        @faith_info['deity'].blank? ? not_applicable : @faith_info['deity']
      end

      def use_deity
        Pf2e.needs_deity?(@charclass)
      end

      def is_devotee
        use_deity ? " %xh%xy(REQ)%xn" : ""
      end

      def deity_optional
      # Reminder for a character who has picked a class that doesn't require a deity, so that they can pick a deity if they want to for the funsies.
        has_charclass && !use_deity && @faith_info['deity'].blank?
      end

      def alignment
        show(@faith_info['alignment'])
      end

      def sanctification
        if Pf2e.uses_sanctification?(@charclass)
          show(@faith_info['sanctification'])
        end
      end

      def has_code

        d_edicts = []
        d_anathema = []

        if use_deity
          if !(@faith_info['deity'].blank?)

            d_edicts = Global.read_config('pf2e_deities',
                        @faith_info['deity'],
                        'edicts')
            d_anathema = Global.read_config('pf2e_deities',
                        @faith_info['deity'],
                        'anathema')
          end
        end

        s_edicts = @subclass_info['edicts'] ? @subclass_info['edicts'] : []
        s_anathema = @subclass_info['anathema'] ? @subclass_info['anathema'] : []

        edicts = s_edicts + d_edicts
        anathema = s_anathema + d_anathema

        code = edicts + anathema

        if code.empty?
          nil
        else
          t('pf2e.char_has_code', :edicts=>edicts.join("%r"), :anathema=>anathema.join("%r"))
        end
      end

      def ahp
        ancestry_hp = @heritage_info['ancestry_HP'] ?
                      @heritage_info['ancestry_HP'] :
                      @ancestry_info["HP"]

        ahp = ancestry_hp ? ancestry_hp : 0
      end

      def chp
        class_hp = @charclass_info["HP"] ? @charclass_info["HP"] : 0
      end

      def size
        return not_applicable if !has_ancestry
        @ancestry_info["Size"] ? @ancestry_info["Size"] : "M"
      end

      def speed
        return not_applicable if !has_ancestry
        speed = @ancestry_info["Speed"] ? @ancestry_info["Speed"] : "?"
        "#{speed} feet"
      end

      def traits
        a_traits = @ancestry_info["traits"] ? @ancestry_info["traits"] : []
        h_traits = @heritage_info["traits"] ? @heritage_info["traits"] : []

        traits = (a_traits + h_traits).uniq.difference([ "" ]).sort.map { |t| t.titlecase }
      end

      def free_boosts
        free = 4
      end

      def collapse_open_boosts(msg)
      # Roll any "open" entries up into a single "N open" count, e.g. ["open", "open"] => "2 open".
        open_count = msg.count { |item| item == "open" }
        named = msg.reject { |item| item == "open" }
        named << "#{open_count} open" if open_count > 0
        named.join(", ")
      end

      def ancestry_boosts
        list = @ancestry_info["abl_boosts"] ? @ancestry_info["abl_boosts"] : "?"

        return list if !list.is_a?(Array)

        msg = list.map { |item| item.is_a?(Array) ? item.join(" and ") : item }
        collapse_open_boosts(msg)
      end

      def bg_boosts
        list = @background_info["abl_boosts"] ? @background_info["abl_boosts"] : []

        return "None." if list.empty?

        msg = list.map { |item| item.is_a?(Array) ? item.join(" or ") : item }
        collapse_open_boosts(msg)
      end

      def key_ability

        key_ability = @subclass_info['key_abil'] ?
          @subclass_info['key_abil'] :
          @charclass_info['key_abil']

        return "Not set." if !key_ability

        if key_ability.is_a?(Array)
          key_ability.flatten.join(" or ")
        else
          key_ability
        end

      end

      def con_mod
        con_mod = "CON Mod"
      end

      def int_mod
        int_mod = "Int MOD"
      end

      def specials
        ainfo = @ancestry_info["special"] ? @ancestry_info["special"] : []
        hinfo = @heritage_info["special"] ? @heritage_info["special"] : []
        binfo = @background_info["special"] ? @background_info["special"] : []
        specials = ainfo + hinfo + binfo.flatten

        if specials.include?("Low-Light Vision") && @heritage_info["change_vision"]
          specials = specials - [ "Low-Light Vision" ] + [ "Darkvision" ]
        end
        specials.empty? ? "No special abilities or senses." : specials.sort.join(", ")
      end

      def languages
      # Ancestry is the usual source, but a heritage, background, class, or specialty can grant one too.
        sources = [ @ancestry_info, @heritage_info, @background_info, @class_features_info, @subclass_features_info ]

        langs = sources.select { |source| source.is_a?(Hash) }.flat_map { |source| Array(source['languages']) }

        langs.empty? ? "Kamin" : langs.uniq.sort.join(", ")
      end

      def charclass_skills
        return [] if !@class_features_info
        charclass_skills = @class_features_info['skills'] ? @class_features_info['skills'] : []
      end

      def subclass_skills
        return [] if !@subclass_features_info

        subclass_skills = @subclass_features_info['skills'] ? @subclass_features_info['skills'] : []
      end

      def deity_skills
        return [] if (!use_deity || @faith_info['deity'].blank?)

        divine_skill = Global.read_config('pf2e_deities', deity, 'divine_skill').split
      end

      def bg_skills
        return [] if !@background_info

        bg_skills = @background_info['skills'] ? @background_info['skills'] : []
      
      end

      def all_skills
        charclass_skills + subclass_skills + bg_skills + deity_skills
      end

      def unique_skills
        all_skills.difference([ "open" ]).uniq
      end

      def open_skills
        all_skills.size - unique_skills.size
      end

      def skills_summary
      # Named skills are locked in as soon as their source is chosen. The number of open skills a class grants isn't
      # known until a class is picked, and INT-based open skills aren't known until abilities are set in the next stage.
        parts = []
        parts << unique_skills.join(", ") unless unique_skills.empty?

        if has_charclass
          parts << "#{open_skills} open" if open_skills > 0
        else
          parts << "your class's number of open skills"
        end

        parts << "your INT modifier"
        parts.join(" + ")
      end

      def errors
      # Memoized because the template asks for this three times and each pass re-reads config.
        return @errors if defined?(@errors)

        @errors = Pf2e.chargen_messages(@ancestry, @heritage, @background, @charclass, @subclass, @char.pf2_faith, @subclass_option, @to_assign)
      end

      def has_messages
        !!errors
      end

      def show_message_section
      # With nothing outstanding, the commit prompt alone says everything an all-clear line would.
        has_messages || base_info_set
      end

      def commit_prompt
        t('pf2e.cg_stage_commit_prompt', :checkpoint => 'info')
      end

    end
  end
end
