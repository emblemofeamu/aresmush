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

  end
end