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

      def ancestry
        @ancestry
      end

      def heritage
        @heritage
      end

      def background
        @background
      end

      def charclass
        @charclass
      end

      def subclass
        @subclass
      end

      def subclass_option
        @subclass_option
      end

      def deity
        @faith_info['deity']
      end

      def use_deity
        @charclass_info['use_deity']
      end

      def is_devotee
        alert = use_deity ? " %xh%xy(REQ)%xn" : ""
      end

      def alignment
        @faith_info['alignment']
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
        @ancestry_info["Size"] ? @ancestry_info["Size"] : "M"
      end

      def speed
        @ancestry_info["Speed"] ? @ancestry_info["Speed"] : "?"
      end

      def traits
        a_traits = @ancestry_info["traits"] ? @ancestry_info["traits"] : []
        h_traits = @heritage_info["traits"] ? @heritage_info["traits"] : []
        c_traits = @charclass_info ? [ @charclass.downcase ] : []

        traits = a_traits + h_traits + c_traits.uniq.difference([ "" ]).sort
      end

      def free_boosts
        free = 4
      end

      def ancestry_boosts
        list = @ancestry_info["abl_boosts"] ? @ancestry_info["abl_boosts"] : "?"

        msg = []
        if list.is_a?(Array)
          list.each do |item|
            if item.is_a?(Array)
              msg << item.join( " and ")
            else
              msg << item
            end
          end

          msg.join(", ")
        else
          list
        end

      end

      def bg_boosts
        list = @background_info["abl_boosts"] ? @background_info["abl_boosts"] : []

        return "None." if list.empty?

        msg = []

        list.each do |item|
          if item.is_a?(Array)
            msg << item.join(" or ")
          else
            msg << item
          end
        end

        msg.join(", ")
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
        @ancestry_info['languages'] ? @ancestry_info['languages'].uniq.sort.join(", ") : "Kamin"
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

      def errors
        msgs = Pf2e.chargen_messages(@ancestry, @heritage, @background, @charclass, @subclass, @char.pf2_faith, @subclass_option, @to_assign)
        msgs ? msgs : t('pf2e.cg_options_ok')
      end

    end
  end
end
