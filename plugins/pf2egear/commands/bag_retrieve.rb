module AresMUSH
  module Pf2egear
    class PF2BagRetrieveCmd
      include CommandHandler

      attr_accessor :bag_id, :category, :item_id, :quantity

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)
        where, how_many = args.arg3.to_s.split('/', 2)

        self.bag_id = integer_arg(where)
        self.quantity = integer_arg(how_many)
        self.category = downcase_arg(args.arg1)
        self.item_id = integer_arg(args.arg2)

        @numcheck = trim_arg(args.arg2)
      end

      def required_args
        [ self.bag_id, self.category, self.item_id ]
      end

      # What a bag can hold, which Inventory says.
      def check_valid_category
        return nil if Pf2egear::Inventory.bag_categories.include?(self.category)

        t('pf2egear.bad_category')
      end

      def check_is_number
        return nil if @numcheck.to_i.to_s == @numcheck
        return t('pf2egear.must_specify_by_number')
      end

      def check_valid_quantity
        return nil if !self.quantity
        return nil if self.quantity.positive?
        return t('pf2egear.bad_quantity')
      end

      def handle

        bag = enactor.bags.to_a[self.bag_id]

        if !bag
          client.emit_failure t('pf2egear.bag_not_found')
          return
        end

        found = Pf2egear::Inventory.in_bag(bag, self.category, self.item_id)

        return if Pf2e::CharState.emit_error!(client, found)

        item = found.state

        name = item.name
        before = Pf2egear::Bulk.standing(enactor)
        moved = Pf2egear::Stowing.retrieve(enactor, self.category, item, self.quantity)

        return if Pf2e::CharState.emit_error!(client, moved)

        client.emit_success t('pf2egear.bag_retrieve_ok', :quantity => moved.state, :name => name, :bag => bag.name)

        warning = Pf2egear::Bulk.warning(enactor, before)

        client.emit_ooc warning if warning
      end

    end
  end
end
