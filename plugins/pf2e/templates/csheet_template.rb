module AresMUSH
  module Pf2e

    class PF2CombatSheetTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :client

      def initialize(char, client)
        @char = char
        @client = client

        @armor = Pf2eCombat.get_equipped_armor(@char)
        @shield = Pf2eCombat.get_equipped_shield(@char)

        super File.dirname(__FILE__) + "/csheet_template.erb"
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def combat_stats
        @char.combat
      end

      def name
        @char.name
      end

      def speed
        base_speed = @char.pf2_movement['base_speed']

        penalty = @armor ? @armor.speed_penalty : 0

        base_speed + penalty
      end

      def movement
        movelist = @char.pf2_movement

        if movelist.size > 2
          return "This character has other forms of movement. Check %x172sheet%xn for details."
        end

        return false
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

      def archetype_class_dcs
        return "--" if !combat_stats

        dcs = Pf2eCombat.get_archetype_class_dcs(@char)
        return "--" if dcs.empty?

        dcs.keys.sort.map do |archetype|
          info = dcs[archetype]
          name = archetype.sub(/ Archetype$/, '')
          prof = info['prof'].to_s[0]&.upcase
          key_abil = info['key_abil'].to_s
          key_abil_short = key_abil.empty? ? "---" : key_abil[0..2].upcase

          "%xh#{name}%xn: #{info['dc']} (#{prof}, #{key_abil_short})"
        end.join(", ")
      end

      def has_archetypes?
        archetype_info = @char.pf2_archetypeinfo || {}
        archetypes = [
          archetype_info['archetype1'],
          archetype_info['archetype2'],
          archetype_info['archetype3'],
          archetype_info['archetype4']
        ].compact.map { |a| a.to_s.strip }.reject(&:empty?)

        !archetypes.empty?
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

      def ac
        Pf2eCombat.calculate_ac(@char)
      end

      def ac_with_shield
        return ac if !(@shield)

        shield_bonus = @shield.ac_bonus

        ac + shield_bonus
      end

      def unarmed_attacks
        unarmed_prof = combat_stats.weapon_prof['unarmed']
        list = []

        attack_list = combat_stats.unarmed_attacks

        attack_list.each do |atk, info|
          list << format_unarmed(@char, atk, info, unarmed_prof)
        end

        list
      end

      def weapons
        weapon_list = Pf2egear.items_in_inventory(@char.weapons)

        list = []

        weapon_list.each_with_index do |w,i|
          next if !w.equipped

          list << format_weapon(char, w, i)
        end

        list
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

      def format_weapon(char,w,i)
        name = w.nickname ? "#{w.nickname} (#{w.name})" : w.name
        bonus = Pf2eCombat.get_wpattack_bonus(char, w)
        prof = Pf2eCombat.get_weapon_prof(char, w.name)[0].upcase
        damage = Pf2eCombat.get_damage(char, w.name, w)
        traits = w.traits.map { |t| titleize_trait(t) }.join(", ")

        "%b%b#{left(i, 3)}%b#{left(name, 40)}%b#{left("#{bonus} (#{prof})",10)}%b#{left(damage, 15)}\n%b%b#{item_color}Traits:%xn #{traits}"
      end

      def format_save(char,name)
        save = "#{item_color}#{name.capitalize}%xn"
        prof = Pf2eCombat.get_save_from_char(char, name)[0].upcase
        bonus = Pf2eCombat.get_save_bonus(char, name)
        "#{left("#{save}: #{bonus} (#{prof})", 26)}"
      end

      def format_unarmed(char, atk_name, atk_info, unarmed_prof)
        damage = atk_info['damage'] + "%b" + atk_info['damage_type']

        traits = atk_info['traits']

        abilmod = traits.include?('finesse') ?
          Pf2eCombat.abilmod_with_finesse(char) :
          Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Strength"))
        prof = Pf2e.get_prof_bonus(char, unarmed_prof)

        bonus = abilmod + prof
        p_str = unarmed_prof[0].upcase

        traits = traits.map { |t| titleize_trait(t) }.join(", ")

        "#{item_color}#{atk_name}:%xn #{bonus} (#{p_str}) #{damage}\n#{item_color}Traits:%xn #{traits}%r"
      end

      def format_condition(condition, value)
        colors = Global.read_config('pf2e', 'condition_colors')
        cond_color = colors[condition.to_s]
        name = "#{cond_color}#{condition}"
        value = value ? "%b#{value}" : ""
        "#{name}#{value}%xn"
      end

      def titleize_trait(trait)
        trait.to_s.split("_").map(&:capitalize).join(" ")
      end

    end
  end
end
