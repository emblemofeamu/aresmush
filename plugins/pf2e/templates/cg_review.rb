module AresMUSH
  module Pf2e

    class PF2CGReviewDisplay < ErbTemplateRenderer
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
        @abil_lock = @char.pf2_abilities_locked
        @class_features_info = @charclass_info['chargen']
        @to_assign = @char.pf2_to_assign
        @boosts = @char.pf2_boosts_working

        super File.dirname(__FILE__) + "/cg_review.erb"
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

      def is_devotee
        alert = @charclass_info['use_deity'] ? "%xh%xy!%xn" : ""
      end

      def alignment
        @faith_info['alignment']
      end

      def has_code
        if (@charclass == 'Champion') || (@charclass == 'Cleric')

          d_edicts = Global.read_config('pf2e_deities',
                      @faith_info['deity'],
                      'edicts')
          d_anathema = Global.read_config('pf2e_deities',
                      @faith_info['deity'],
                      'anathema')

          de = d_edicts ? d_edicts : []
          da = d_anathema ? d_anathema : []

          d_code = de + da
        else
          d_code = []
        end

        s_code = []
        s_edicts = @subclass_info['edicts']
        s_anathema = @subclass_info['anathema']

        s_edicts.each { |e| s_code << e } if s_edicts
        s_anathema.each { |a| s_code << a } if s_anathema

        code = d_code + s_code

        if code.empty?
          nil
        else
          code.join("%r")
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

        traits = a_traits + h_traits + c_traits.uniq.sort
      end

      def free_boosts
        @baseinfolock ? @to_assign['open boost'] : 4
      end

      def ancestry_boosts
        if @baseinfolock
          list = @boosts['ancestry']
          list.sort.join(", ")
        else
          list = @ancestry_info["abl_boosts"] ? @ancestry_info["abl_boosts"] : "?"
          list.is_a?(Array) ? list.join(" and ") : list
        end
      end

      def free_ancestry_boosts
        if @baseinfolock
          @to_assign['open anboost'] ? @to_assign['open anboost'] : 0
        else
          @ancestry_info["abl_boosts_open"] ? @ancestry_info["abl_boosts_open"] : 0
        end
      end

      def ancestry_flaw
        @ancestry_info["abl_flaw"] ? @ancestry_info["abl_flaw"] : "None."
      end

      def background_boosts
        if @baseinfolock
          list = @boosts['background']
          list.sort.join(", ")
        else
          list = @background_info["req_abl_boosts"] ? @background_info["req_abl_boosts"] : []
          list.empty? ? "None required" : list.join(" or ")
        end
      end

      def free_bg_boosts
        if @baseinfolock
          @to_assign['open bgboost'] ? @to_assign['open bgboost'] : 0
        else
          @background_info["abl_boosts_open"] ? @background_info["abl_boosts_open"] : 0
        end
      end

      def charclass_boosts
        if @baseinfolock
          list = @boosts['charclass']
          list.sort.join(", ")
        else
          @charclass_info["key_abil"] ? @charclass_info["key_abil"].join(" or ") : "Class not set."
        end
      end

      def con_mod
        if @abil_lock
          con_mod = Pf2e.get_ability_mod(Pf2eAbilities.get_ability_score(@char, "Constitution"))
        else
          con_mod = "CON Mod"
        end
      end

      def int_mod
        if @abil_lock
          int_mod = Pf2e.get_ability_mod(Pf2eAbilities.get_ability_score(@char, "Intelligence"))
        else
          int_mod = "INT Mod"
        end
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
        @ancestry_info['languages'] ? @ancestry_info['languages'].sort.join(", ") : "Tradespeak"
      end

      def skills

        return t('pf2e.not_selected_yet', :element => "Character class") if !@class_features_info
        charclass_skills = @class_features_info['class_skills'] ? @class_features_info['class_skills'] : []

        open_skills = @class_features_info['skills_open']

        "#{charclass_skills.join} + #{open_skills}"
      end

      def bg_skills
        @to_assign['bgskill'].join(" or ") if @baseinfolock
      end

      def messages
        if @abil_lock
          t('pf2e.cg_and_abil_lock_ok')
        elsif @baseinfolock
          msgs = Pf2eAbilities.abilities_messages(@char)
          msgs ? msgs : t('pf2e.abil_options_ok')
        else
          msgs = Pf2e.chargen_messages(@ancestry, @heritage, @background, @charclass, @subclass, @char.pf2_faith, @subclass_option)
          msgs ? msgs : t('pf2e.cg_options_ok')
        end
      end

    end
  end
end
