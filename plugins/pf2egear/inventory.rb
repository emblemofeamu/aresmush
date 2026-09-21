module AresMUSH
  module Pf2egear

    # What a character can carry, one row per category.
    #
    # Fifteen commands opened with the same `case self.category` - which collection to read, and
    # sometimes a rule about how many of that thing may be worn at once. The aliases differ per
    # command too, so `weapon` worked where `weapons` did not, or the other way about.
    #
    #   names      - every spelling a player may type, the first being the canonical one
    #   collection - the character collection the items live in
    #   in_bag     - the same items inside a bag, which the bag model spells differently
    #   model      - the Ohm class, which config also names under item_classes
    #   single     - only one may be equipped at a time (armour, a shield)
    #   stackable  - many of the same thing is one row with a quantity, rather than a row each
    #   investable - the item can be invested, which PF2e limits to ten per day
    #   use_needs  - what has to be true before the item can be used: worn, or invested
    #   in_bags    - the item can be put in a bag
    module Inventory

      CATEGORIES = [
        {
          'names' => %w{weapons weapon}, 'collection' => :weapons, 'in_bag' => :weapons, 'model' => 'PF2Weapon',
          'single' => false, 'stackable' => false, 'investable' => true, 'in_bags' => true,
          'use_needs' => :equipped
        },
        {
          'names' => %w{armor}, 'collection' => :armor, 'in_bag' => :armor, 'model' => 'PF2Armor',
          'single' => true, 'stackable' => false, 'investable' => true, 'in_bags' => true,
          'use_needs' => :equipped
        },
        {
          'names' => %w{shields shield}, 'collection' => :shields, 'in_bag' => :shields, 'model' => 'PF2Shield',
          'single' => true, 'stackable' => false, 'investable' => false, 'in_bags' => true
        },
        {
          # The character keeps these in `magic_items` and a bag keeps them in `magicitem`. A command
          # that guessed wrong raised NoMethodError, which is what bag/store did.
          'names' => %w{magicitem magicitems}, 'collection' => :magic_items, 'in_bag' => :magicitem, 'model' => 'PF2MagicItem',
          'single' => false, 'stackable' => false, 'investable' => true, 'in_bags' => true,
          'use_needs' => :invested
        },
        {
          'names' => %w{bags bag}, 'collection' => :bags, 'in_bag' => nil, 'model' => 'PF2Bag',
          'single' => false, 'stackable' => false, 'investable' => false, 'in_bags' => false
        },
        {
          'names' => %w{gear}, 'collection' => :gear, 'in_bag' => :gear, 'model' => 'PF2Gear',
          'single' => false, 'stackable' => true, 'investable' => false, 'in_bags' => true
        },
        {
          'names' => %w{consumables consumable}, 'collection' => :consumables, 'in_bag' => :consumables, 'model' => 'PF2Consumable',
          'single' => false, 'stackable' => true, 'investable' => false, 'in_bags' => true
        }
      ].freeze

      def self.categories
        CATEGORIES.flat_map { |row| row['names'] }
      end

      # The row for whatever the player typed, or nil.
      def self.row(category)
        asked = category.to_s.downcase

        CATEGORIES.find { |r| r['names'].include?(asked) }
      end

      def self.canonical(category)
        (row(category) || {})['names']&.first
      end

      def self.model(category)
        name = (row(category) || {})['model']

        name && AresMUSH.const_get(name)
      end

      # The character's items of that category. `held` leaves out anything stowed in a bag, which is
      # what a command asking "your third weapon" means.
      def self.all(char, category)
        found = row(category)

        return [] unless found

        Array(char.send(found['collection']).to_a)
      end

      def self.held(char, category)
        Pf2egear.items_in_inventory(all(char, category))
      end

      # The same category's items inside a bag, by the number a bag listing showed.
      def self.in_bag(bag, category, index)
        found = row(category)

        return Pf2e::Err.new(:bad_category, 'pf2e.bad_option', 'element' => 'category',
                             'options' => bag_categories.join(', ')) unless found && found['in_bag']

        item = Array(bag.send(found['in_bag']).to_a)[index.to_i]

        return Pf2e::Err.new(:not_found, 'pf2egear.not_found') unless item

        Pf2e::Ok.new(:state => item)
      end

      def self.bag_categories
        CATEGORIES.select { |row| row['in_bag'] }.flat_map { |row| row['names'] }
      end

      def self.single?(category)
        !!(row(category) || {})['single']
      end

      def self.stackable?(category)
        !!(row(category) || {})['stackable']
      end

      def self.investable?(category)
        !!(row(category) || {})['investable']
      end

      # What has to be true of the item before it can be used: worn for armour and a weapon,
      # invested for a magic item, nothing for a consumable.
      def self.use_needs(category)
        (row(category) || {})['use_needs']
      end

      def self.in_bags?(category)
        !!(row(category) || {})['in_bags']
      end

      # One of a character's items, by the number a listing showed. Returns an Err rather than nil so
      # a command can say which of the two things was wrong.
      def self.item(char, category, index)
        return Pf2e::Err.new(:bad_category, 'pf2e.bad_option', 'element' => 'category',
                             'options' => categories.join(', ')) unless row(category)

        found = held(char, category)[index.to_i]

        return Pf2e::Err.new(:not_found, 'pf2egear.not_found') unless found

        Pf2e::Ok.new(:state => found)
      end
    end
  end
end
