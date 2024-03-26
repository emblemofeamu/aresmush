module AresMUSH
  class Pf2eCombat < Ohm::Model
    include ObjectModel

    attribute :saves, :type => DataType::Hash, :default => {}

    attribute :perception, :default => 'untrained'
    attribute :class_dc, :default => 'untrained'
    attribute :key_abil

    attribute :armor_prof, :type => DataType::Hash, :default => {}

    attribute :weapon_prof, :type => DataType::Hash, :default => {}

    attribute :unarmed_attacks, :type => DataType::Hash, :default => {}
    attribute :defense, :type => DataType::Hash, :default => {}

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

    def self.modify_combat_stats(char, info)
      # Used when something taken later modifies initial combat stats.
      combat = get_create_combat_obj(char)

      info.each_pair do |key, value|
        case key
        when 'saves'
          saves = combat.saves
          value.each_pair do |save, new_value|
            saves[save] = new_value
          end
          combat.update(saves: saves)
        when 'armor_prof'
          profs = combat.armor_prof
          value.each_pair do |type, new_prof|
            profs[type] = new_prof
          end
          combat.update(armor_prof: profs)
        when 'perception'
          combat.update("#{key}": value)
        when 'class_dc'
          combat.update("#{key}": value)
        when 'weapon_prof'
          profs = combat.weapon_prof
          value.each_pair do |type, new_prof|
            profs[type] = new_prof
          end
          combat.update(weapon_prof: profs)
        when 'unarmed_attacks'
          unarmed = combat.unarmed_attacks

          value.each_pair do |attack, info|
            unarmed[attack] = info
          end

          combat.update(unarmed_attacks: unarmed)
        end
      end

      return combat
    end

    def self.get_save_bonus(char, save)
      prof_bonus = Pf2e.get_prof_bonus(char, Pf2eCombat.get_save_from_char(char, save))

      mod = Pf2e.get_linked_attr_mod(char, save)
      mod = 0 if !mod

      item = Pf2egear.get_rune_value(Pf2eCombat.get_equipped_armor(char), 'fundamental', 'resilient')
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

    def self.get_weapon_prof(char, name)
      combat = char.combat

      char_wp_prof = combat.weapon_prof ? combat.weapon_prof : {}

      wp_info = Global.read_config('pf2e_weapons', name)
      wp_cat = wp_info['category']

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
        char_ancestry = char.pf2_base_info['ancestry']
        anc_wp_feat = char_ancestry + " Weapon Familiarity"

        if (Pf2e.has_feat?(char, anc_wp_feat) && ancestry_list.include?(char_ancestry))
          prof_list << char_wp_prof['ancestry']
        end
      end

      # Does character get a proficiency in that particular weapon from their deity?
      if char_wp_prof['deity']
        deity_weapon = Global.read_config('pf2e_deities', char.pf2_faith['deity'], 'fav_weapon')

        prof_list << char_wp_prof['deity'] if name == deity_weapon
      end

      prof_list = prof_list.compact

      # Of everything we've accumulated, the character's proficiency with that weapon is the best one in the list.
      Pf2e.select_best_prof(prof_list)

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
        abil_bonus = traits.include?('finesse') ?
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
      use_dex_for_dmg = base_info['specialty'] == 'Thief'

      abil_mod = use_dex_for_dmg ? abilmod_with_finesse(char) :
        Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Strength"))

      striking_rune = weapon ? weapon.runes['fundamental']['striking'] : false
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
      combat.key_abil = nil

      combat.armor_prof = {}
      combat.weapon_prof = {}
      combat.unarmed_attacks = {}

      combat.save
    end
  end
end
