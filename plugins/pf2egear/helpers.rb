module AresMUSH
  module Pf2egear

    def self.convert_money(value, type)
      case type
      when "platinum", "pp"
        multiplier = 1000
      when "gold", "gp"
        multiplier = 100
      when "silver", "sp"
        multiplier = 10
      when "copper", "cp"
        multiplier = 1
      else
        return nil
      end

      value * multiplier
    end

    def self.display_money(money)
      cp = money % 10
      sp = (money/10) % 10
      gp = (money/100) % 10
      pp = (money/1000)

      cp_msg = cp > 0 ? " #{cp} cp " : " "
      sp_msg = sp > 0 ? " #{sp} sp " : " "
      gp_msg = gp > 0 ? " #{gp} gp " : " "
      pp_msg = pp > 0 ? " #{pp} pp " : " "

      # Displaying 0cp for a free item
      cp_msg = cp == 0 && sp == 0 && gp == 0 && pp == 0 ? "0 cp" : cp_msg

      msg = pp_msg + gp_msg + sp_msg + cp_msg
      msg.squeeze(" ").strip
    end

    # The one door for moving a character's purse, in either direction. Negative takes.
    #
    # Records the transaction and moves the total together, so a purse cannot move without a
    # line saying why - which is what buy, sell and pay each had to remember separately, and
    # what pay_player never did at all.
    def self.pay_player(char, amount, paid_by = 'System', reason = nil, ref = nil)
      Pf2e::Audit.post(char, 'money', amount, :by => paid_by, :reason => reason, :ref => ref)
    end

    def self.reset_gear(char, preserve_money=false)
      char.pf2_gear = {'consumables' => {}, 'gear' => {}}

      unless preserve_money
        char.pf2_money = STARTING_MONEY
        # The entries are the record and the total is their sum, so a balance set back to the
        # starting figure leaves no transactions behind to disagree with it.
        Pf2e::Audit.delete_all!(char, 'money')
      end

      # Every category, from the table, so a new kind of item is cleared without this being edited.
      Inventory::CATEGORIES.each do |row|
        Array(char.send(row['collection'])&.to_a).each { |item| item.delete }
      end

      char.save
    end

    def self.display_shield_hp(item)
      hp = item.hp
      dmg = item.damage
      cur_hp = hp - dmg
      broken = (cur_hp <= hp / 2) ? "%xr" : ""

      "#{broken}#{cur_hp}%xn / #{hp}"
    end

    def self.items_in_inventory(list)
      # A bag is carried rather than kept in one, and has no bag of its own to ask about.
      list.filter { |item| !(item.respond_to?(:bag) && item.bag) }
    end

    # What a character can carry, and the point at which it tells.
    #
    # PF2e sets these at 10 + Strength and 5 + Strength, and a feat raises them - Hefty Hauler by two
    # each. The feat says so itself, as an `inventory.bulk` write, so nothing here names the feat.
    def self.max_bulk(char)
      10 + Pf2e.ability_mod(char, 'Strength') + Pf2e::Paths.held(char, 'maxaddend').to_i
    end

    def self.encumbered_at(char)
      5 + Pf2e.ability_mod(char, 'Strength') + Pf2e::Paths.held(char, 'encumberedafteraddend').to_i
    end

    # Gives a character an item the shop sells.
    #
    # Gear and consumables stack: many of the same thing is one row with a quantity. Everything else
    # is one row per item, because a weapon carries its own runes and a bag its own contents.
    # Inventory says which is which.
    def self.create_item(char, category, name, quantity, item_info)
      if Inventory.stackable?(category)
        held = Inventory.all(char, category).find { |item| item.name == name }

        return held.update(:quantity => held.quantity.to_i + quantity.to_i) if held

        return build_item(char, category, name, item_info).update(:quantity => quantity)
      end

      build_item(char, category, name, item_info)
    end

    # Copies the catalogue's per-item facts onto the item: its bulk, its price, its runes.
    #
    # Only the keys the model actually has. A catalogue row also carries things that belong to the
    # kind of item rather than to this one - what it modifies, what it says about itself - and those
    # are read from the catalogue when wanted, so writing them onto every copy would both waste the
    # space and freeze a catalogue we edit constantly.
    def self.build_item(char, category, name, item_info)
      model = Inventory.model(category)
      item = model.create(Pf2e::Actors.of(char).item_owner_field => char, :name => name)
      known = model.attributes.map(&:to_s)

      (item_info || {}).each_pair do |key, value|
        item.update("#{key}": value) if known.include?(key.to_s)
      end

      item
    end

    def self.get_item_name(item)
      nickname = item.respond_to?(:nickname) ? item.nickname : nil

      nickname ? "#{nickname} (#{item.name})" : item.name
    end

    def self.get_rune_value(object, type, subtype)
      return 0 if !object
      value = object.runes.dig(type, subtype)

      value ? value : 0
    end

    # Every invested item, across the categories PF2e lets a character invest. Reading only the
    # magic items meant an invested weapon's or armour's item bonus counted for nothing.
    def self.get_invested_items(char)
      Inventory.categories.select { |c| Inventory.investable?(c) }
               .map { |c| Inventory.canonical(c) }.uniq
               .flat_map { |c| Inventory.held(char, c) }
               .select { |item| item.invested }
    end

    # Every item the character has actually got working, each paired with the category it came from.
    #
    # `use_needs` already says what has to be true before an item does anything: armour and weapons
    # have to be worn, a magic item has to be invested. A category with no `use_needs` - gear, a
    # consumable, a shield - has nothing worn about it, so nothing there modifies a figure passively;
    # a potion in a backpack is not a bonus, and a shield's AC comes from raising it.
    def self.effective_items(char)
      Inventory.categories.map { |c| Inventory.canonical(c) }.uniq.flat_map do |category|
        needs = Inventory.use_needs(category)

        next [] unless needs

        Inventory.held(char, category).select { |item| item.send(needs) }
                 .map { |item| [ category, item ] }
      end
    end

    # Everything the character has on them, worn or not.
    #
    # Most of what an item does needs it worn, and `effective_items` is the list for that. Some rules say
    # outright that they do not - a compass points north in your pack, a religious symbol is held rather
    # than worn - and those rules are marked, so the item has to be reachable to read the mark.
    def self.carried_items(char)
      Inventory.categories.map { |c| Inventory.canonical(c) }.uniq.flat_map do |category|
        Inventory.held(char, category).map { |item| [ category, item ] }
      end
    end

    # The catalogue row an item was made from, which is where its effects live - the same way a feat's
    # effects live in the feat catalogue rather than on the character.
    # The property runes etched on an item, as slugs. `etch/property` keeps them as a list on the item,
    # which is where Foundry keeps them too.
    def self.property_runes(item)
      Array(item.runes&.dig('property', 'list')).map { |one| Pf2e::Domains.slug(one) }
    end

    # The catalogue of property runes, keyed by the slug a rule names. Foundry keeps what a rune does in
    # their code rather than their packs, so `scripts/import_foundry_runes.py` reads that table and
    # writes it here as `rules:` like every other catalogue.
    def self.runes
      (Global.read_config('pf2e_runes') || {})
    end

    # A rune answers to its name as a player types it and to the slug their data calls it, which are not
    # the same word: `giantKilling` slugs to one word and "Giant Killing" to two.
    def self.rune_row(name)
      wanted = Pf2e::Domains.slug(name)

      runes.find do |held, info|
        [ held, info['slug'] ].compact.any? { |one| Pf2e::Domains.slug(one) == wanted }
      end
    end

    def self.rune_entry(name)
      rune_row(name)&.last
    end

    def self.rune_named(name)
      rune_row(name)&.first
    end

    # How many property runes an item can hold: as many as its potency rune is worth, which is the
    # rule as written.
    def self.rune_slots(item)
      get_rune_value(item, 'fundamental', 'potency').to_i
    end

    def self.catalogue_entry(category, item)
      catalogue = Inventory.config(category)

      catalogue && Global.read_config(catalogue, item.name)
    end

    def self.destroy_item(item, client, enactor)
      item.delete
      dest_msg = t('pf2egear.item_used_up', :name => item.name)
      Login.notify(enactor, :pf2_gear, dest_msg, item.id)
      client.emit_ooc dest_msg
    end



  end
end
