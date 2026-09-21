module AresMUSH
  module Pf2egear
    class PF2GearEquipCmd
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

      # Only what can be worn or wielded. A bag is carried, and gear is not equipped at all.
      EQUIPPABLE = %w{weapons weapon armor shields shield}.freeze

      def check_valid_category
        return nil if EQUIPPABLE.include?(self.category)

        t('pf2egear.bad_category')
      end

      def check_is_number
        return nil if @numcheck.to_i.to_s == @numcheck
        return t('pf2egear.must_specify_by_number')
      end

      def handle
        # Armour and a shield are worn one at a time, which Inventory says rather than this command.
        if Pf2egear::Inventory.single?(self.category) &&
           Pf2egear::Inventory.held(enactor, self.category).any? { |item| item.equipped }
          client.emit_failure t('pf2egear.already_equipped')
          return
        end

        found = Pf2egear::Inventory.item(enactor, self.category, self.item_num)

        return if Pf2e::CharState.emit_error!(client, found)

        item = found.state

        item.update(equipped: true)

        iname = item.nickname ? item.nickname : item.name

        client.emit_success t('pf2egear.item_equip_ok', :name => iname)
      end

    end
  end
end
