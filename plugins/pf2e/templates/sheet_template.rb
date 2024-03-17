module AresMUSH
  module Pf2e

    class Pf2eSheetTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :section, :client, :base_info, :faith_info

      def initialize(char, section, client, base_info, faith_info)
        @char = char
        @section = section
        @client = client
        @base_info = base_info
        @faith_info = faith_info

        super File.dirname(__FILE__) + "/sheet_template.erb"
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def section
        @section
      end

      def subclass_list
        Global.read_config('pf2e', 'subclass_names')
      end

      def name
        @char.name
      end

      def ancestry
        @base_info['ancestry']
      end

      def heritage
        @base_info['heritage']
      end

      def background
        @base_info['background']
      end

      def charclass
        @base_info['charclass']
      end

      def subclass
        @base_info['specialize'] ? @base_info['specialize'] : "N/A"
      end

      def subclass_name
        subclass_list[charclass] ? subclass_list[charclass] : "Specialty"
      end

      def subclass_option
        @base_info['specialize_info'].blank? ?
                  "" :
                  "/" + @base_info['specialize_info']
      end

      def traits
        @char.pf2_traits.sort.join(", ")
      end

      def level
        @char.pf2_level
      end

      def xp
        @char.pf2_xp
      end

      def faith
        @char.group('Faith')
      end

      def region
        @char.group('Region')
      end

      def deity
        @faith_info['deity']
      end

      def alignment
        @faith_info['alignment']
      end

      def has_code
        if (@faith_info['edicts']) || (@faith_info['anathema'])
          t('pf2e.has_code')
        end
      end

      def abilities
        abil_list = @char.abilities

        return [] if !abil_list

        list = []
        abil_list.each_with_index do |a,i|
          name = a.name
          score = a.mod_val ? a.mod_val : a.base_val
          list << format_ability(name, score, i)
        end

        list
      end

      def skills
        skills = @char.skills

        return [] if skills.empty?

        filter_skills = skills.to_a.delete_if { |s| s.prof_level == 'untrained' }

        sort_skills = filter_skills.sort_by { |s| s.name }

        list = []
        sort_skills.each_with_index do |s,i|
          list << format_skill(@char, s, i)
        end

        list
      end

      def hp
        Pf2eHP.display_character_hp(@char)
      end

      def temp_hp
        hp = @char.hp

        return "---" if !hp

        temp_hp = hp.temp_hp

        "#{temp_hp}"
      end

      def class_dc
        return "--" if !combat_stats
        dc = Pf2eCombat.get_class_dc(@char)
        prof = combat_stats.class_dc[0].upcase
        "#{dc} (#{prof})"
      end

      def perception
        return "--" if !combat_stats
        bonus = Pf2eCombat.get_perception(@char)
        prof = combat_stats.perception[0].upcase
        "#{bonus} (#{prof})"
      end

      def saves
        saves = %w{fortitude reflex will}
        list = []
        saves.each do |s|
          list << format_save(@char, s)
        end

        list
      end

      def specials
        @char.pf2_special.sort.join(", ")
      end

      def conditions
        cond = @char.pf2_conditions
        if cond.empty?
          value = "None active."
        else
          list = []
          cond.each do |c,v|
            list << format_condition(c,v)
          end

          value = list.sort.join(", ")
        end

        value
      end

      def feats
        charclass_list = @char.pf2_feats['charclass']
        ancestry_list = @char.pf2_feats['ancestry']
        general_list = @char.pf2_feats['general']
        skill_list = @char.pf2_feats['skill']
        dedication_list = @char.pf2_feats['dedication'] || []

        list = []

        charclass_list.each do |c|
          list << format_feat(c,'charclass')
        end

        ancestry_list.each do |a|
          list << format_feat(a,'ancestry')
        end

        general_list.each do |g|
          list << format_feat(g,'general')
        end

        skill_list.each do |s|
          list << format_feat(s,'skill')
        end

        dedication_list.each do |d|
          list << format_feat(d,'dedication')
        end

        list.sort.join(", ")
      end

      def features
        @char.pf2_features.sort.join(", ")
      end

      def languages
        lang = @char.pf2_lang
        lang.empty? ? "None set." : lang.sort.join(", ")
      end

      def base_speed
        @char.pf2_movement['base_speed'].to_s + " feet"
      end

      def movement
        list = []

        movelist = @char.pf2_movement

        movelist.each_pair do |type, value|

          next if type == "Size"
          next if type == "base_speed"

          fmt_type = type.split("_").each { |word| word.capitalize! }.join(" ")
          list << "%xh#{fmt_type}%xn: #{value}'"
        end

        list.sort.join(", ")
      end

      def size
        @char.pf2_movement["Size"]
      end

      def combat_stats
        @char.combat
      end

      def armor_prof
        list = []

        armor_profs = combat_stats.armor_prof

        alist = armor_profs.keys.sort

        alist.each_with_index do |atype,i|
          prof = armor_profs[atype]

          list << format_profs(atype, prof, i)
        end

        list.join(", ")
      end

      def weapon_prof
        list = []

        w_profs = combat_stats.weapon_prof

        wlist = w_profs.keys.sort

        wlist.each_with_index do |wtype,i|
          prof = w_profs[wtype]

          list << format_profs(wtype, prof, i)
        end

        list.join(", ")
      end

      def magic_stats
        @char.magic
      end

      def no_magic_msg
        "%r#{t('pf2emagic.not_caster')}"
      end

      def magic_header
        "%b%b#{item_color}#{left("Class", 15)}#{left("Tradition", 14)}#{left("Prof", 8)}#{left("Spell Atk Bonus", 21)}#{left("Spell DC", 16)}%xn"
      end

      def spell_dcs
        dc_list = magic_stats.tradition

        list = []

        dc_list.each_pair do |key, value|
          list << format_spell_dc(key, value)
        end

        list
      end

      def known_for
        known_for = @char.pf2_known_for.sort

        list = []

        known_for.each_with_index do |k,i|
          list << format_known_for(k,i)
        end

        list
      end

      def format_ability(abil, score, i)
        name = "#{item_color}#{abil.capitalize}%xn"
        linebreak = i % 3 == 0 ? "%r" : ""
        mod = "(#{Pf2eAbilities.abilmod(score)})"
        "#{linebreak}#{left(name, 13)}: #{left(score, 2)} #{left(mod, 9)}"
      end

      def format_condition(condition, value)
        colors = Global.read_config('pf2e', 'condition_colors')
        cond_color = colors[condition.to_s]
        name = "#{cond_color}#{condition}"
        cv = value['value'] ? "/#{value['value']}" : ""
        "#{name}#{cv}%xn"
      end

      def format_known_for(string, i)
        linebreak = i % 2 == 0 ? "%r" : ""

        "#{linebreak}#{left(string, 37)}%b"
      end

      def format_skill(char, s, i)
        name = s.name
        fmt_name = "#{item_color}#{name}%xn"
        linked_attr = print_linked_attr(name)
        skill_mod = "%xh#{Pf2eSkills.get_skill_bonus(char, name)}%xn"
        linebreak = i % 2 == 1 ? "" : "%r"
        proflevel = " (#{s.prof_level[0].upcase})"
        "#{linebreak}#{left(fmt_name + linked_attr,21)} #{left(skill_mod + proflevel, 17)}"
      end

      def format_profs(name, prof, i)
        fmt_name = "%xh#{name.capitalize}%xn"
        fmt_prof = prof[0].upcase

        "#{fmt_name}: #{fmt_prof}"
      end

      def format_feat(name, type)
        fmt_type = type.upcase[0..1]

        "#{name} (%xh%xx#{fmt_type}%xn)"
      end

      def format_save(char,name)
        save = "#{item_color}#{name.capitalize}%xn"
        prof = Pf2eCombat.get_save_from_char(char, name)
        bonus = Pf2eCombat.get_save_bonus(char, name)
        "#{left("#{save}: #{bonus} (#{prof[0].upcase})", 26)}"
      end

      def format_spell_dc(charclass, trad_info)
        dc = PF2Magic.get_spell_dc(@char, charclass)
        trad = Pf2e.pretty_string(trad_info[0])
        prof = Pf2e.pretty_string(trad_info[1].slice(0).upcase)
        atk = PF2Magic.get_spell_attack_bonus(@char, charclass)

        "%b%b#{left(charclass,15)}#{left(trad,14)}#{left(prof, 8)}#{left(atk,22)}#{left(dc, 16)}"
      end

      def print_linked_attr(skill)
        apt = Pf2eSkills.get_linked_attr(skill)
        " %xh%xx(#{apt[0..2].upcase})%xn"
      end

    end
  end
end
