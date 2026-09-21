module AresMUSH
  class Pf2eCombat < Ohm::Model
    include ObjectModel

    attribute :saves, :type => DataType::Hash, :default => {}

    attribute :perception, :default => 'untrained'
    attribute :class_dc, :default => 'untrained'
    attribute :archetype_class_dcs, :type => DataType::Hash, :default => {}
    attribute :key_abil

    attribute :armor_prof, :type => DataType::Hash, :default => {}

    attribute :weapon_prof, :type => DataType::Hash, :default => {}
    attribute :weapon_group_prof, :type => DataType::Hash, :default => {}

    attribute :unarmed_attacks, :type => DataType::Hash, :default => {}
    attribute :defense, :type => DataType::Hash, :default => {}

    # The Rogue's sneak attack, as a dice expression ('1d6' … '4d6'). Set by the class table at
    # chargen, 5, 11 and 17, and read by `roll sneak attack`.
    attribute :sneak_attack

    reference :character, "AresMUSH::Character"


    ##### CLASS METHODS #####

    def self.get_save_from_char(char,save)
      combat = char.combat

      return 'untrained' if !char.combat

      save_list = combat.saves
      save_list[save]
    end

    def self.get_create_combat_obj(char)
      obj = char.combat

      return obj if obj

      obj = Pf2eCombat.create(character: char)
      char.update(combat: obj)

      return obj
    end

    def self.init_combat_stats(char, info)
      # Used only when initially populating combat.
      combat = get_create_combat_obj(char)

      info.each_pair do |key, value|
        combat.update("#{key}": value)
      end

      return combat
    end

    # How each key in a `combat_stats` block is written.
    #
    # `merge` keys hold a hash of name => proficiency and take the block's entries one at a time.
    # `set` keys hold a single value. A key absent from this table is logged, because a proficiency
    # a class never receives leaves nothing on the sheet to notice.
    STAT_WRITERS = {
      'saves' => 'merge',
      'armor_prof' => 'merge',
      'weapon_prof' => 'merge',
      'weapon_group_prof' => 'merge',
      'unarmed_attacks' => 'merge',
      'defense' => 'merge',
      'perception' => 'set',
      'class_dc' => 'set',
      'key_abil' => 'set',
      'sneak_attack' => 'set'
    }.freeze

    def self.update_combat_stats(char, info)
      # Used when something taken later modifies initial combat stats.
      combat = get_create_combat_obj(char)

      info.each_pair do |key, value|
        name = key.to_s

        # Archetypes nest a whole block per archetype, so it keeps its own arm.
        if name == 'archetype_class_dcs'
          write_archetype_dcs(combat, value)
          next
        end

        case STAT_WRITERS[name]
        when 'merge'
          existing = combat.send(name) || {}
          (value || {}).each_pair { |item, new_value| existing[item] = new_value }
          combat.update(name.to_sym => existing)
        when 'set'
          combat.update(name.to_sym => value)
        else
          Global.logger.error "Unknown combat stat '#{name}' for #{char.name}; it was not applied."
        end
      end

      return combat
    end

    def self.write_archetype_dcs(combat, value)
      existing = combat.archetype_class_dcs || {}

      (value || {}).each_pair do |name, info|
        existing[name] ||= {}

        normalized = (info || {}).each_with_object({}) { |(k, v), out| out[k.to_s] = v }

        existing[name].merge!(normalized)
      end

      combat.update(archetype_class_dcs: existing)
    end

    def self.get_save_bonus(char, save)
      prof_bonus = Pf2e.get_prof_bonus(char, Pf2eCombat.get_save_from_char(char, save))

      mod = Pf2e.get_linked_attr_mod(char, save)
      mod = 0 if !mod

      item = Pf2egear.get_rune_value(Pf2eCombat.get_equipped_armor(char), 'fundamental', 'power')
      item_bonus = item ? item : 0

      prof_bonus + mod + item_bonus
    end

    def self.get_class_dc(char)
      combat_stats = char.combat

      return 0 if !combat_stats

      prof_bonus = Pf2e.get_prof_bonus(char, combat_stats.class_dc)

      key_ability = combat_stats.key_abil ? combat_stats.key_abil : "Strength"
      abil_mod = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, key_ability))

      10 + prof_bonus + abil_mod
    end

    def self.get_archetype_class_dcs(char)
      combat_stats = char.combat

      return {} if !combat_stats

      archetype_dcs = combat_stats.archetype_class_dcs || {}
      return {} if archetype_dcs.empty?

      dc_hash = {}

      archetype_dcs.each_pair do |archetype, info|
        next if !info.is_a?(Hash)

        prof = info['prof'] || info[:prof]
        key_ability = info['key_abil'] || info[:key_abil]

        if key_ability.to_s.strip.empty?
          configured_key_abilities = Array(Global.read_config('pf2e_archetype', archetype, 'key_abil')).compact.map { |a| a.to_s.strip }.reject(&:empty?).uniq
          key_ability = configured_key_abilities.first if configured_key_abilities.size == 1
        end

        next if prof.to_s.strip.empty?
        next if key_ability.to_s.strip.empty?

        prof_bonus = Pf2e.get_prof_bonus(char, prof)
        abil_mod = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, key_ability))

        dc_hash[archetype] = {
          'dc' => 10 + prof_bonus + abil_mod,
          'prof' => prof,
          'key_abil' => key_ability
        }
      end

      dc_hash
    end

    def self.calculate_ac(char)
      armor = get_equipped_armor(char)

      abonus = armor ? armor.ac_bonus : 0
      a_cat = armor ? armor.category : "unarmored"
      prof_with_armor = char.combat.armor_prof[a_cat]
      pbonus = Pf2e.get_prof_bonus(char, prof_with_armor)

      ibonus = Pf2egear.get_rune_value(armor, 'fundamental', 'potency')

      dex_cap = armor ? armor.dex_cap : 99
      dbonus = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, 'Dexterity')).clamp(-99, dex_cap)

      10 + abonus + pbonus + ibonus + dbonus
    end

    def self.get_equipped_armor(char)
      char.armor&.select { |a| a.equipped }.first
    end

    def self.get_equipped_shield(char)
      char.shields&.select { |s| s.equipped }.first
    end

    def self.get_perception(char)
      abil_mod = Pf2e.get_linked_attr_mod(char, 'perception')
      combat_stats = char.combat

      return abil_mod if !combat_stats

      prof_bonus = Pf2e.get_prof_bonus(char, combat_stats.perception)

      item = Pf2egear.bonus_from_item(char, 'Perception')
      item_bonus = item ? item : 0

      abil_mod + prof_bonus + item_bonus
    end

    # Stat block for anything that can be attacked with, by name.
    #
    # Alchemical bombs are martial thrown weapons but they are also one-use items, so they live in pf2e_consumables rather than pf2e_weapons.
    def self.weapon_info(name)
      Global.read_config('pf2e_weapons', name) || Global.read_config('pf2e_consumables', name)
    end

    def self.bomb?(wp_info)
      Array(wp_info['traits']).any? { |t| t.to_s.casecmp?('bomb') }
    end

    def self.get_weapon_prof(char, name)
      combat = char.combat

      char_wp_prof = combat.weapon_prof ? combat.weapon_prof : {}
      group_profs = combat.weapon_group_prof ? combat.weapon_group_prof : {}

      wp_info = weapon_info(name)

      return 'untrained' if !wp_info

      wp_cat = wp_info['category']
      wp_group = wp_info['group']

      prof_list = [ 'untrained' ]

      case wp_cat
      when 'unarmed'
        prof_list << char_wp_prof['unarmed']
      when 'simple'
        prof_list << char_wp_prof['simple']
      when 'martial'
        prof_list << char_wp_prof['martial']
      when 'advanced'
        prof_list << char_wp_prof['advanced']
      end

      # Does character get a proficiency in that particular weapon from their class?
      charclass_list = wp_info['charclass']

      if charclass_list
        if charclass_list.include?(char.pf2_base_info['charclass'])
          prof_list << char_wp_prof['charclass']
        end
      end

      # Check for ancestry weapon familiarity.
      ancestry_list = wp_info['ancestry']

      if ancestry_list
        char_ancestry = char.pf2_base_info['ancestry'].downcase
        Global.logger.debug "Char Ancestry - #{char_ancestry}"
        anc_wp_feat = (["sildanyar","khazad"].include? char_ancestry) ? char_ancestry + "i Weapon Familiarity" : char_ancestry + " Weapon Familiarity"
        Global.logger.debug "anc_wp_feat - #{anc_wp_feat}"
        if (Pf2e.has_feat?(char, anc_wp_feat) && ancestry_list.include?(char_ancestry))
          prof_list << char_wp_prof['ancestry']
        end
      end

      # Does character get a proficiency in that particular weapon from their deity?
      if char_wp_prof['deity']
        deity_weapon = Global.read_config('pf2e_deities', char.pf2_faith['deity'], 'fav_weapon')
        if deity_weapon && name.to_s.downcase == deity_weapon.to_s.downcase
          prof_list << char_wp_prof['deity']
        end
      end

      # Did the character choose this specific weapon, e.g. the advanced weapon picked for a
      # second or later Weapon Proficiency?
      if char_wp_prof['chosen']
        chosen = Pf2e.chosen_weapons(char)
        prof_list << char_wp_prof['chosen'] if chosen.any? { |w| w.to_s.casecmp?(name.to_s) }
      end

      # Alchemical bombs are martial thrown weapons, so the martial category above already
      # covers anyone trained in martial weapons. This is for the alchemist, who gains bombs
      # on a track of their own without ever becoming trained in martial weapons.
      if char_wp_prof['bomb'] && bomb?(wp_info)
        prof_list << char_wp_prof['bomb']
      end

      # Does character get a proficiency in that particular weapon from a weapon group choice?
      if wp_group && group_profs[wp_group]
        group_prof = group_profs[wp_group]
        group_value = group_prof[wp_cat] || group_prof[wp_cat.to_s]
        prof_list << group_value if group_value
      end

      prof_list = prof_list.compact

      # Of everything we've accumulated, the character's proficiency with that weapon is the best one in the list.
      Pf2e.select_best_prof(prof_list)

    end

    # The character's proficiency with one named unarmed attack.
    def self.get_unarmed_prof(char, name, atk_info = nil)
      combat = char.combat

      return 'untrained' if !combat

      char_wp_prof = combat.weapon_prof ? combat.weapon_prof : {}
      group_profs = combat.weapon_group_prof ? combat.weapon_group_prof : {}

      atk_info ||= (combat.unarmed_attacks || {})[name] || {}

      prof_list = [ 'untrained' ]

      # The flat category proficiency.
      prof_list << char_wp_prof['unarmed']

      # A deity's favoured weapon can name an unarmed attack rather than a weapon, the way Navos's is a fist.
      if char_wp_prof['deity']
        faith = char.pf2_faith || {}
        deity_weapon = Global.read_config('pf2e_deities', faith['deity'], 'fav_weapon') if !faith['deity'].blank?
        prof_list << char_wp_prof['deity'] if deity_weapon && name.to_s.casecmp?(deity_weapon.to_s)
      end

      # Did a feat choice name this specific attack?
      if char_wp_prof['chosen']
        chosen = Pf2e.chosen_weapons(char)
        prof_list << char_wp_prof['chosen'] if chosen.any? { |w| w.to_s.casecmp?(name.to_s) }
      end

      # Weapon group proficiency.
      group = atk_info['group']
      if !group.blank?
        group_key = group_profs.keys.find { |g| g.to_s.casecmp?(group.to_s) }
        group_prof = group_key ? group_profs[group_key] : nil
        prof_list << group_prof['unarmed'] if group_prof.is_a?(Hash) && group_prof['unarmed']
      end

      Pf2e.select_best_prof(prof_list.compact)
    end

    def self.get_armor_prof(char, name)

      combat = char.combat

      char_armor_prof = combat.armor_prof

      armor_cat = Global.read_config('pf2e_armor', name, 'category')

      char_armor_prof[armor_cat] ? char_armor_prof[armor_cat] : 'untrained'

    end

    def self.abilmod_with_finesse(char)
      strength = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Strength"))
      dexterity = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Dexterity"))

      dexterity > strength ? dexterity : strength
    end

    def self.get_wpattack_bonus(char, weapon)
      prof = get_weapon_prof(char, weapon.name)
      prof_bonus = Pf2e.get_prof_bonus(char, prof)

      if (weapon.wp_type == 'ranged')
        abil_bonus = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Dexterity"))
      else
        traits = weapon.traits
        # Config writes `Finesse` and chargen writes `finesse`, so the comparison cannot be
        # `include?`: every catalogue weapon used Strength before this.
        abil_bonus = Pf2e.has_trait?(traits, 'finesse') ?
          Pf2eCombat.abilmod_with_finesse(char) :
          Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Strength"))
      end

      potency_rune = Pf2egear.get_rune_value(weapon, 'fundamental', 'potency')

      prof_bonus + abil_bonus + potency_rune
    end

    def self.get_natattack_bonus(char, attack)

    end

    def self.get_damage(char, attack, weapon=nil, twohand=false)
      if weapon
        # twohanddmg represents a one-handed weapon that does more damage when wielded two-handed
        # This is called as a switch in roll, so defaults to false.
        twohanddmg = weapon.wp_damage_2h
        # If the weapon does not change damage for 2h wield, twohand argument is ignored
        twohand = false unless twohanddmg
        base_damage = twohand ? twohanddmg : weapon.wp_damage
        damage_type = weapon.wp_damage_type
      else
        combat = char.combat
        attack = combat.unarmed_attacks[attack.capitalize]
        base_damage = attack ? attack['damage'] : 0
        damage_type = "B"
      end

      # Alchemical Bombs are their own animal, will do all the deets later.

      base_info = char.pf2_base_info
      use_dex_for_dmg = base_info['specialize'] == 'Thief'

      abil_mod = use_dex_for_dmg ? abilmod_with_finesse(char) :
        Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Strength"))

      striking_rune = weapon ? weapon.runes['fundamental']['power'] : false
      striking_rune = 0 if !striking_rune

      number_of_dice = 1 + striking_rune

      dmg_mod = abil_mod + striking_rune

      "#{number_of_dice}#{base_damage}+#{dmg_mod}"
    end

    def self.factory_default(char)
      # This may or may not exist, nothing to do if not.
      combat = char.combat
      return unless combat

      combat.saves = {}
      combat.perception = 'untrained'
      combat.class_dc = 'untrained'
      combat.archetype_class_dcs = {}
      combat.key_abil = nil

      combat.armor_prof = {}
      combat.weapon_prof = {}
      combat.weapon_group_prof = {}
      combat.unarmed_attacks = {}

      combat.save
    end
  end
end
