module AresMUSH
  class PF2Armor < Ohm::Model
    include ObjectModel

    attribute :name, :default => "Armor"
    attribute :bulk, :type => DataType::Float, :default => 0
    attribute :traits, :type => DataType::Array, :default => []
    attribute :level, :type => DataType::Integer, :default => 1
    attribute :price, :type => DataType::Integer, :default => 0
    attribute :talisman, :type => DataType::Array, :default => []
    attribute :category, :default => ""
    attribute :nickname
    attribute :ac_bonus, :type => DataType::Integer, :default => 0
    attribute :dex_cap, :type => DataType::Integer, :default => 0
    attribute :check_penalty, :type => DataType::Integer, :default => 0
    attribute :speed_penalty, :type => DataType::Integer, :default => 0
    attribute :min_str, :type => DataType::Integer, :default => 10
    attribute :group, :default => ""
    attribute :runes, :type => DataType::Hash, :default => { 'fundamental' => {} , 'property' => {} }
    attribute :invested, :type => DataType::Boolean, :default => false
    attribute :invest_on_refresh, :type => DataType::Boolean
    attribute :equipped, :type => DataType::Boolean, :default => false
    attribute :use, :type => DataType::Hash, :default => {}

    reference :character, "AresMUSH::Character"
    reference :bag, "AresMUSH::PF2Bag"

  end
end
