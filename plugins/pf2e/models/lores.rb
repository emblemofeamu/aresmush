module AresMUSH
  class Pf2eLores < Ohm::Model
    include ObjectModel
    include FindByName

    attribute :name
    attribute :name_upcase
    attribute :prof_level
    attribute :cg_lore, :type => DataType::Boolean
    index :name_upcase

    before_save :set_upcase_name

    def set_upcase_name
      self.name_upcase = self.name.upcase
    end

    reference :character, "AresMUSH::Character"

    ##### CLASS METHODS #####

    def self.get_linked_attr(name)
      linked_attr = 'Intelligence'
    end

    def self.find_lore(name, char)
      lore = char.lores.find { |s| s.name_upcase == name.upcase }
    end

    def self.get_lore_bonus(char, name)
      has_lore = find_lore(name, char)
      abonus = Pf2eAbilities.get_ability_mod(
        Pf2eAbilities.get_ability_score(char, 'intelligence')
      )
      pbonus = has_lore ? Pf2e.get_prof_bonus(enactor, skill.prof_level) : 0

      abonus + pbonus
    end

    def self.get_lore_prof(char, name)
      lore = find_lore(name, char)
      prof = lore.prof_level
    end

  end
end
