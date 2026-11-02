module AresMUSH
  module Pf2egear

    # Putting things in a bag and taking them out. A stack can split: part of it goes, and the part that
    # goes joins a stack already there made the same way, so what lasts until the next rest stays apart
    # from what they bought.
    module Stowing

      # `quantity` is how many, or nothing for all of them. Answers an Ok with how many moved.
      def self.store(bag, category, item, quantity = nil)
        moving = quantity || Bulk.count(item)
        refused = held_back(item, moving) || worn(item) || over_limit(bag, item, moving)

        return refused if refused

        beside = Inventory.stackable?(category) ? Inventory.bag_contents(bag).select { |one| one.is_a?(item.class) } : []

        move(item, moving, bag, beside)
      end

      def self.retrieve(char, category, item, quantity = nil)
        moving = quantity || Bulk.count(item)
        refused = held_back(item, moving)

        return refused if refused

        move(item, moving, nil, Inventory.stackable?(category) ? Inventory.held(char, category) : [])
      end

      # Why they can't move this many: an encounter has it, or they haven't got that many.
      def self.held_back(item, moving)
        held = Pf2e::Equipment.held_by(item)

        return Pf2e::Err.new(:in_encounter, 'pf2egear.item_in_encounter', :item => item.name, :id => held.id) if held
        return nil if moving <= Bulk.count(item)

        Pf2e::Err.new(:not_enough, 'pf2egear.bag_not_enough', :name => item.name, :have => Bulk.count(item))
      end

      def self.worn(item)
        worn = (item.respond_to?(:equipped) && item.equipped) || (item.respond_to?(:invested) && item.invested)

        worn ? Pf2e::Err.new(:worn, 'pf2egear.bag_item_worn', :name => item.name) : nil
      end

      # What the bag says it holds. A limit of nothing is no limit.
      def self.over_limit(bag, item, moving)
        stowed = Inventory.bag_contents(bag)
        adding = Bulk.each_of(item) * moving
        load = Bulk.sum(stowed)
        heaviest = (bag.max_item_bulk.to_f * Bulk::TENTHS).round
        capacity = bag.capacity.to_i * Bulk::TENTHS
        most = bag.max_items.to_i
        items = stowed.sum { |one| Bulk.count(one) }

        if heaviest.positive? && Bulk.each_of(item) > heaviest
          return Pf2e::Err.new(:too_big, 'pf2egear.bag_item_too_big', :name => item.name, :bag => bag.name, :max => Bulk.shown(heaviest))
        end

        if capacity.positive? && load + adding > capacity
          return Pf2e::Err.new(:bag_full, 'pf2egear.bag_full', :bag => bag.name, :load => Bulk.shown(load),
                               :capacity => bag.capacity, :adding => Bulk.shown(adding))
        end

        return nil unless most.positive? && items + moving > most

        Pf2e::Err.new(:too_many, 'pf2egear.bag_too_many', :bag => bag.name, :max => most, :held => items)
      end

      # The destination is written first, so nothing is lost if the second write never happens.
      def self.move(item, moving, bag, beside)
        whole = moving >= Bulk.count(item)
        same = beside.find { |one| one.id != item.id && alike?(one, item) }

        if same
          same.update(:quantity => same.quantity.to_i + moving)
          whole ? item.delete : item.update(:quantity => item.quantity.to_i - moving)
        elsif whole
          item.update(:bag => bag)
        else
          item.class.create(item.attributes.except(:created_at, :updated_at).merge(:quantity => moving, :bag => bag))
          item.update(:quantity => item.quantity.to_i - moving)
        end

        Pf2e::Ok.new(:state => moving)
      end

      def self.alike?(one, other)
        one.name == other.name && one.granted_by == other.granted_by && one.expires == other.expires
      end
    end
  end
end
