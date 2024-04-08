module AresMUSH
  module Pf2egear
    class PF2SellCmd
      include CommandHandler

      attr_accessor :category, :item_num, :quantity

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        self.category = downcase_arg(args.arg1)
        self.item_num = integer_arg(args.arg2)
        self.quantity = integer_arg(args.arg3)

        @numcheck = trim_arg(args.arg2)
      end

      def required_args
        [ self.category, self.item_num ]
      end

      def check_permissions
        return nil if enactor.is_approved?
        return nil if enactor.is_admin?
        return t('dispatcher.not_allowed')
      end

      def check_valid_quantity
        return nil if !self.quantity
        return nil if self.quantity.positive?
        return t('pf2egear.bad_quantity')
      end

      def check_is_number
        return nil if @numcheck.to_i.to_s == @numcheck
        return t('pf2egear.must_specify_by_number')
      end

      def handle

        # Q is how many you want to sell. If no quantity is specified, assume 1
        q = self.quantity ? self.quantity : 1

        list_key = "pf2e_" + self.category

        # Valid category of items?
        list = Global.read_config(list_key)

        if !list
          client.emit_failure t('pf2egear.bad_category')
          return
        end

        # Find the item in the list. How to do that depends on the category.
        index = self.item_num

        case category
        when "weapons", "weapon"
          item_id = Pf2egear.items_in_inventory(enactor.weapons).to_a[index]
        when "armor"
          item_id = Pf2egear.items_in_inventory(enactor.armor).to_a[index]
        when "shields", "shield"
          item_id = Pf2egear.items_in_inventory(enactor.shields).to_a[index]
        when "bags"
          item_id = enactor.bags.to_a[index]
        when "magicitem", "magicitems"
          item_id = Pf2egear.items_in_inventory(enactor.magic_items).to_a[index]
        when "consumables"
          item_id = Pf2egear.items_in_inventory(enactor.consumables).to_a[index]
          item_qty = item_id.quantity
        when "gear"
          item_id = Pf2egear.items_in_inventory(enactor.gear).to_a[index]
          item_qty = item_id.quantity
        end

        if !item_id
          client.emit_failure t('pf2egear.not_found')
          return
        end

        purse = enactor.pf2_money

        itemname = item_id.name
        price = (item_id.price) / 2

        # Unless it's gear or a consumable, you only have one of that item.
        item_qty = 1 if !item_qty

        if q > item_qty
          client.emit_failure t('pf2egear.not_enough_you', :item => "of those to sell #{q}")
          return
        end

        to_be_paid = price * item_qty

        # If they're selling all of them, blow the item out of the list, else subtract quantity

        if q == item_qty
          item_id.delete
        else
          item_id.update(quantity: item_qty - q)
        end

        enactor.update(pf2_money: purse + to_be_paid)

        Pf2egear.record_money_history(enactor, 'Item Vendor', to_be_paid, "Item Sale: #{itemname}")

        client.emit_success t('pf2egear.item_sold_ok', :item => itemname, :cost => Pf2egear.display_money(to_be_paid), :quantity => q)

      end

    end
  end
end
