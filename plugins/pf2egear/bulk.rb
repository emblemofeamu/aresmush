module AresMUSH
  module Pf2egear

    # What a character's things come to, counted one way for everyone who asks.
    #
    # Counted in tenths of a Bulk, as integers: ten light items are one Bulk, and a total is rounded down
    # to whole Bulk once, at the end, so 6 Bulk and 7 light is 6.
    #
    # A holder's total is worked out once between writes, because `held_conditions` asks for it hundreds of
    # times a command (`Pf2e::SheetReads.memo`).
    module Bulk

      TENTHS = 10
      EXTRADIMENSIONAL = 'extradimensional'.freeze

      def self.tracked?
        !!Global.read_config('pf2e_gear_options', 'use_encumbrance')
      end

      # How many of the thing a row stands for. Only gear and consumables have a quantity.
      def self.count(item)
        item.respond_to?(:quantity) ? item.quantity.to_i : 1
      end

      def self.each_of(item)
        (item.bulk.to_f * TENTHS).round
      end

      def self.sum(items)
        items.sum { |item| each_of(item) * count(item) }
      end

      # What a bag adds to whoever carries it, given what is stowed in it: its own bulk, and its contents
      # less what it takes the weight of. An extradimensional bag's contents weigh nothing out here.
      def self.carrying(bag, stowed)
        return each_of(bag) if Pf2e.has_trait?(bag.traits, EXTRADIMENSIONAL)

        each_of(bag) + [ stowed - (bag.bulk_bonus.to_f * TENTHS).round, 0 ].max
      end

      # Everything together. An item whose bag has gone counts as loose, as `items_in_inventory` lists it.
      def self.tally(items, bags)
        by_bag = items.group_by { |item| item.bag_id.to_s }
        ours = bags.map { |bag| bag.id.to_s }
        loose = items.reject { |item| ours.include?(item.bag_id.to_s) }

        sum(loose) + bags.sum { |bag| carrying(bag, sum(by_bag[bag.id.to_s] || [])) }
      end

      def self.whole(tenths)
        tenths / TENTHS
      end

      # Tenths as a player reads them: 3, or 1.5.
      def self.shown(tenths)
        (tenths % TENTHS).zero? ? tenths / TENTHS : tenths.to_f / TENTHS
      end

      # What is in a bag, against what it holds. A bag with no limit on its Bulk may limit its items instead.
      def self.fill(bag)
        stowed = Inventory.bag_contents(bag)

        return "#{shown(sum(stowed))} / #{bag.capacity}" if bag.capacity.to_i.positive?
        return "#{stowed.sum { |item| count(item) }} / #{bag.max_items} items" if bag.max_items.to_i.positive?

        shown(sum(stowed)).to_s
      end

      # A holder's total, in tenths.
      def self.total(holder)
        Pf2e::SheetReads.memo(holder, :bulk) do
          tally(Inventory.bag_categories.map { |name| Inventory.canonical(name) }.uniq.flat_map { |name| Inventory.all(holder, name) },
                Inventory.all(holder, 'bags'))
        end
      end

      def self.carried(holder)
        whole(total(holder))
      end

      # More than the limit: at a limit of 6, 6 Bulk and 7 light is not encumbered, and 7 Bulk is.
      def self.encumbered?(holder)
        tracked? && carried(holder) > Pf2egear.encumbered_at(holder)
      end

      def self.over_maximum?(holder)
        tracked? && carried(holder) > Pf2egear.max_bulk(holder)
      end

      # How far over they are, or nothing: `:encumbered`, or `:maximum` past that.
      def self.standing(holder)
        return :maximum if over_maximum?(holder)

        encumbered?(holder) ? :encumbered : nil
      end

      # What to tell someone whose standing has just got worse, or nothing.
      def self.warning(holder, before)
        now = standing(holder)

        return nil if now.nil? || now == before || (now == :encumbered && before == :maximum)

        t(now == :maximum ? 'pf2egear.over_maximum_warning' : 'pf2egear.encumbered_warning',
          :carried => carried(holder), :limit => Pf2egear.encumbered_at(holder), :max => Pf2egear.max_bulk(holder))
      end
    end
  end
end
