module AresMUSH
  class Pf2eLevelSnapshot < Ohm::Model
    include ObjectModel

    attribute :level, :type => DataType::Integer
    index :level

    attribute :character_data, :type => DataType::Hash, :default => {}
    attribute :abilities, :type => DataType::Hash, :default => {}
    attribute :skills, :type => DataType::Hash, :default => {}
    attribute :hp, :type => DataType::Hash, :default => {}
    attribute :combat, :type => DataType::Hash, :default => {}
    attribute :magic, :type => DataType::Hash, :default => {}

    reference :character, "AresMUSH::Character"
  end
end
