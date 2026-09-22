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
      list.filter { |item| !(item.bag) }
    end

    def self.bag_effective_bulk(bag, load)
      capacity_bonus = bag.bulk_bonus ? bag.bulk_bonus : 0
      bag_bulk = bag.bulk

      (load + bag_bulk - capacity_bonus).to_i.clamp(0,100)
    end

    def self.calculate_bag_load(bag)
      wp_load = bag.weapons.map { |w| w.bulk }.sum
      armor_load = bag.armor.map { |a| a.bulk }.sum
      shield_load = bag.shields.map { |s| s.bulk }.sum
      mi_load = bag.magicitem.map { |m| m.bulk }.sum
      c_load = bag.consumables.map { |c| c.bulk }.sum
      gear_load = bag.gear.map { |g| g.bulk }.sum

      wp_load + armor_load + shield_load + mi_load + c_load + gear_load
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

    def self.build_item(char, category, name, item_info)
      item = Inventory.model(category).create(:character => char, :name => name)

      (item_info || {}).each_pair { |key, value| item.update("#{key}": value) }

      item
    end

    def self.get_item_name(item)
      item.nickname ? "#{item.nickname} (#{item.name})" : item.name
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

    def self.bonus_from_item(char, roll)
      invested_items = get_invested_items(char)

      blist = [ 0 ]

      invested_items.each do |i|
        bonus = i.bonus[roll]

        blist << bonus if bonus
      end

      blist.sort.pop
    end

    def self.destroy_item(item, client, enactor)
      item.delete
      dest_msg = t('pf2egear.item_destroyed', :name => item.name)
      Login.notify(enactor, :pf2_gear, dest_msg)
      client.emit_ooc dest_msg
    end



  end
end
