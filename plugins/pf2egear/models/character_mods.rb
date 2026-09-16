module AresMUSH
  class Character

    attribute :pf2_money, :type => DataType::Integer, :default => 1500
    attribute :pf2_gear, :type => DataType::Hash, :default => {'consumables' => {}, 'gear' => {}}
    attribute :pf2_invested_list, :type => DataType::Array, :default => []

    collection :weapons, "AresMUSH::PF2Weapon"
    collection :armor, "AresMUSH::PF2Armor"
    collection :bags, "AresMUSH::PF2Bag"
    collection :shields, "AresMUSH::PF2Shield"
    collection :magic_items, "AresMUSH::PF2MagicItem"
    collection :consumables, "AresMUSH::PF2Consumable"
    collection :gear, "AresMUSH::PF2Gear"

  end
end
