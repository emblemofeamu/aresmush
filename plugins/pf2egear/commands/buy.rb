module AresMUSH
  module Pf2egear
    class PF2BuyCmd
      include CommandHandler

      attr_accessor :category, :item_name, :quantity

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        self.category = downcase_arg(args.arg1)
        self.item_name = downcase_arg(args.arg2)
        self.quantity = integer_arg(args.arg3)
      end

      def required_args
        [ self.category, self.item_name ]
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

      def handle
        charlevel = enactor.pf2_level

        # If no quantity is specified, assume they want just one.
        q = self.quantity ? self.quantity : 1

        list_key = "pf2e_" + self.category

        # Valid category of items?
        list = Global.read_config(list_key)

        if !list
          client.emit_failure t('pf2egear.bad_category')
          return
        end

        # The list of items in that category gets filtered by character level.
        available_items = list.select { |k,v| v['level'] <= charlevel }

        # Does that item exist in that category?
        item = available_items.select { |k,v| k.downcase.include? (self.item_name) }

        if item.size.zero?
          client.emit_failure t('pf2egear.not_found')
          return
        elsif item.size > 1
          item = available_items.select { |k,v| k.downcase == self.item_name }

          if item.size.zero?
            client.emit_failure t('pf2egear.not_found')
            return
          end

          item_name = item.keys.first
          item_info = item.values.first
        else
          item_name = item.keys.first
          item_info = item.values.first
        end

        #  If it's gear or a consumable, multiples are allowed, otherwise only one.

        case self.category
        when "weapons", "weapon", "armor", "shields", "shield", "bags", "magicitem"
          if q > 1
            client.emit_ooc t('pf2egear.quantity_one_only')
            q = 1
          end
        end

        # Do they have enough money?
        cost = item_info['price'] * q
        purse = enactor.pf2_money

        if cost > purse
          client.emit_failure t('pf2egear.not_enough_you', :item => 'money to buy that')
          return
        end

        # Create the item.

        Pf2egear.create_item(enactor, self.category, item_name, q, item_info)

        enactor.update(pf2_money: (purse - cost))

        Pf2egear.record_money_history(enactor, 'Item Vendor', -cost, "Purchase #{item_name}")

        client.emit_success t('pf2egear.item_bought_ok', :item => item_name, :cost => Pf2egear.display_money(cost), :quantity => q)

      end

    end
  end
end
