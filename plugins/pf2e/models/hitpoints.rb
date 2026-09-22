module AresMUSH
  class Pf2eHP < Ohm::Model
    include ObjectModel


    attribute :ancestry_hp, :type => DataType::Integer, :default => 0
    attribute :charclass_hp, :type => DataType::Integer, :default => 0
    attribute :damage, :type => DataType::Integer, :default => 0
    attribute :temp_max, :type => DataType::Integer, :default => 0
    attribute :temp_current, :type => DataType::Integer, :default => 0
    attribute :temp_hp, :type => DataType::Integer, :default => 0


    reference :character, "AresMUSH::Character"



    ##### CLASS METHODS #####

    def self.display_character_hp(char)
      hp = char.hp

      return "---" if !hp

      current = get_current_hp(char)
      max = get_max_hp(char)
      percent = max.zero? ? 0 : ((current.to_f / max.to_f) * 100).to_i
      hp_color = "%xg" if percent > 75
      hp_color = "%xc" if percent.between?(50,75)
      hp_color = "%xy" if percent.between?(25,50)
      hp_color = "%xr" if percent < 25
      "#{hp_color}#{current}%xn / #{max} (#{percent}%)"

    end

    def self.get_dying_value(char)

      previous_value = char.pf2e_conditions['Dying'] ? Pf2e.get_condition_value(char, 'Dying') : 1
      wounded_value = Pf2e.get_condition_value(char, 'Wounded')
      dying_value = previous_value + wounded_value
      doomed_value = Pf2e.get_condition_value(char, 'Doomed')

    end

    def self.modify_damage(char, amount, healing=false, is_dm=false)

      hp = get_hp_obj(char)
      max_hp = get_max_hp(char)
      existing_damage = hp.damage

      if healing
        if (existing_damage == max_hp)
          wounded = char.pf2e_conditions['Wounded'] ? Pf2e.get_condition_value(char, 'Wounded') : 0
          wounded_value = 1 + wounded
          Pf2e.set_condition(char, 'Wounded', wounded_value)
          Pf2e.remove_condition(char, 'Dying')
        end

        hp.update(damage: (existing_damage - amount).clamp(0,max_hp))
        return
      end

      # Deduct from temp_hp first, if any, overflow goes to HP.

      temp_hp = hp.temp_hp

      # Amount expects an integer, conversion not required.

      damage = temp_hp - amount

      hp.temp_hp = damage

      if damage.negative?

        extra_damage = damage.abs
        hp.temp_hp = 0

        new_damage = existing_damage + extra_damage

        # Check to see if this damage puts the character in Dying.
        if (new_damage >= max_hp && is_dc)
          hp.damage = max_hp
          dying_value = char.pf2e_conditions['Dying'] ? Pf2e.get_condition_value(char, 'Dying') : 1
          wounded_value = Pf2e.get_condition_value(char, 'Wounded')
          doomed_value = Pf2e.get_condition_value(char, 'Doomed')

          if dying_value >= (4 - doomed_value)
            # If this is true, the character is dead.
            if is_dc
              char.update(pf2_is_dead: true)
            end

            Pf2e.set_condition char, 'Dying', dying_value.clamp(0,(4 - doomed_value))
          else
            Pf2e.set_condition char, 'Dying', dying_value
          end

          hp.save
          return
        end

        hp.damage = new_damage
        hp.save
      end
    end

    def self.get_hp_obj(char)
      char.hp
    end

    # A character who has not committed base info has no HP row yet, and approving one used to
    # raise `undefined method 'ancestry_hp' for nil`. No row means no hit points.
    def self.get_max_hp(char)
      hp = get_hp_obj(char)

      return 0 unless hp

      con_mod = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, "Constitution"))
      ancestry_hp = hp.ancestry_hp
      charclass_hp = hp.charclass_hp
      level = char.pf2_level
      # drain_value = Pf2e.get_condition_value(char, 'Drained')
      # For right now, until I do conditions, it's just 0
      drain_value = 0

      (charclass_hp + con_mod - drain_value) * level + ancestry_hp
    end

    def self.get_current_hp(char)
      hp = get_hp_obj(char)

      return 0 unless hp

      get_max_hp(char) - hp.damage.to_i
    end

    def self.factory_default(char)
      # This may or may not exist, nothing to do if not.
      hp = char.hp
      return unless hp

      hp.damage = 0
      hp.ancestry_hp = 0
      hp.charclass_hp = 0
      hp.temp_max = 0
      hp.temp_current = 0
      hp.temp_hp = 0

      hp.save
    end

  end
end
