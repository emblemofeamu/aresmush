module AresMUSH
  module Pf2egear
    class PF2BagStoreCmd
      include CommandHandler

      attr_accessor :bag_id, :category, :item_id

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)
        self.bag_id = integer_arg(args.arg3)
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

      def handle

        bag = enactor.bags.to_a[self.bag_id]

        if !bag
          client.emit_failure t('pf2egear.bag_not_found')
          return
        end

        found = Pf2egear::Inventory.item(enactor, self.category, self.item_id)

        return if Pf2e::CharState.emit_error!(client, found)

        item = found.state

        # Move the item.

        item.update(bag: bag)

        client.emit_success t('pf2egear.bag_store_ok', :name => item.name, :bag => bag.name)
      end

    end
  end
end
