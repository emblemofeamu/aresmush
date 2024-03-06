module AresMUSH
  module Pf2e

    class PF2CGReviewLockDisplay < ErbTemplateRenderer
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

        @magic = @char.magic

        super File.dirname(__FILE__) + "/cg_review_locked.erb"
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
        use_deity ? " %xh%xy(REQ)%xn" : ""
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
          t('pf2e.char_has_code',
            :edicts=>edicts.join("%r"),
            :anathema=>anathema.join("%r")
          )
        end
      end

      def ahp
        ancestry_hp = @heritage_info['ancestry_HP'] ?
                      @heritage_info['ancestry_HP'] :
                      @ancestry_info["HP"]

        ancestry_hp ? ancestry_hp : 0
      end

      def chp
        @charclass_info["HP"] ? @charclass_info["HP"] : 0
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

        a_traits + h_traits + c_traits.uniq.difference([ "" ]).sort
      end

      def free_boosts
        open_list = @boosts['free']
        still_free = open_list.count("open")
        assigned = open_list.difference([ "open" ]).empty? ?
                   "None assigned" :
                   open_list.difference([ "open" ]).sort.join(", ")

        "#{assigned} plus #{still_free} free"
      end

      def ancestry_boosts
        list = @boosts['ancestry']
        list.sort.join(", ")
      end

      def ancestry_flaw
        @ancestry_info["abl_flaw"] ? @ancestry_info["abl_flaw"] : "None."
      end

      def bg_boosts
        list = @boosts['background']
        if list.is_a?(Array)
          list = list.map do |v|
            if v.is_a?(Array)
              v.join(" or ")
            else
              v
            end
          end
        end
        list.join(", ")
      end

      def key_ability
        list = @boosts['charclass']

        if list.is_a?(Array)
          list.sort.join(" or ")
        else
          list
        end
      end

      def con_mod
        Pf2eAbilities.abilmod(Pf2eAbilities.get_score(@char, "Constitution"))
      end

      def int_mod
        Pf2eAbilities.abilmod(Pf2eAbilities.get_score(@char, "Intelligence"))
      end

      def specials
        @char.pf2_special.join(", ")
      end

      def languages
        @char.pf2_lang.sort.join(", ")
      end

      def existing_skills
        char_skills = @char.skills

        list = []

        char_skills.each do |skill|
          list << skill.name if skill.prof_level == 'trained'
        end

        list.sort.join(", ")
      end

      def open_skills
        @to_assign['open skills'].count("open")
      end

      def open_languages
        extra_lang = @to_assign['open languages']
        extra_lang ? extra_lang.count("open") : 0
      end

      def bglore_choice
        options = @to_assign['bglore']

        return false if !options

        options.sort.join(" or ")
      end

      def feats
        @char.pf2_feats.values.flatten.sort.join(", ")
      end

      def lock_msg
        return t('pf2e.msg_cgandabil_lock') if @char.pf2_abilities_locked
        return t('pf2e.msg_cglock')
      end

      def errors
        messages = []

        # Abilities
        abil_msgs = Pf2eAbilities.abilities_messages(@char)
        if abil_msgs
          abil_msgs.each do |msg|
            messages << msg
          end
        else
          abil_lock = @char.pf2_abilities_locked
          ok_msg = abil_lock ? t('pf2e.abil_lock_ok') : t('pf2e.abil_options_ok')
          messages << ok_msg
        end

        # Skills
        skill_msgs = Pf2eSkills.skills_messages(@char)
        if skill_msgs
          skill_msgs.each do |msg|
            messages << msg
          end
        else
          messages << t('pf2e.skill_options_ok')
        end

        # Languages
        open_lang = @char.pf2_to_assign['open languages'] ? @char.pf2_to_assign['open languages'] : []

        if open_lang.include?('open')
          messages << t('pf2e.unassigned_lang')
        end

        # Feats
        feat_msgs = Pf2e.feat_messages(@char)
        if feat_msgs
          feat_msgs.each do |msg|
            messages << msg
          end
        else
          messages << t('pf2e.feats_are_ok')
        end

        # Magic

        magic_msgs = Pf2emagic.cg_magic_warnings(@magic)

        if magic_msgs
          magic_msgs.each do |msg|
            messages << msg
          end
        else
          messages << t('pf2emagic.cg_magic_ok')

          # Count repertoire spells to assign.
          rep = @to_assign['repertoire']

          if rep
            rlist = []
            rep.each_pair do |k,v|
              rlist << "#{k}: #{v.count("open")}"
            end
            rcount = rlist.join(", ")

            messages << t('pf2emagic.cg_rep_spells', :rcount => rcount)
          end

          # Count spellbook spells to assign.

          sbook = @to_assign['spellbook']

          if sbook
            slist = []
            sbook.each_pair do |k,v|
              slist << "#{k}: #{v.count("open")}"
            end
            scount = slist.join(", ")

            messages << t('pf2emagic.cg_spellbook_spells', :rcount => scount)
          end

        end

        messages.join("%r")
      end

    end
  end
end
