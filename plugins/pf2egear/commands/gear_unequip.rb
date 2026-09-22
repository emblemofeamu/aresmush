module AresMUSH
  module Pf2egear
    class PF2GearUnequipCmd
      include CommandHandler

      attr_accessor :category, :item_num

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.category = downcase_arg(args.arg1)
        self.item_num = integer_arg(args.arg2)

        @numcheck = trim_arg(args.arg2)
      end

      def required_args
        [ self.category, self.item_num ]
      end

      # What can be taken off again: the same list equipping accepts.
      def check_valid_category
        return nil if PF2GearEquipCmd::EQUIPPABLE.include?(self.category)

        t('pf2egear.bad_category')
      end

      def check_is_number
        return nil if @numcheck.to_i.to_s == @numcheck
        return t('pf2egear.must_specify_by_number')
      end

      def handle
        found = Pf2egear::Inventory.item(enactor, self.category, self.item_num)

        return if Pf2e::CharState.emit_error!(client, found)

        item = found.state

        item.update(equipped: false)

        iname = item.nickname ? item.nickname : item.name

        client.emit_success t('pf2egear.item_unequip_ok', :name => iname)
      end

    end
  end
end
