module AresMUSH
  module Pf2egear
    class PF2GearRenameCmd
      include CommandHandler

      attr_accessor :category, :item_num, :nickname

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.category = downcase_arg(args.arg1)
        self.item_num = integer_arg(args.arg2)
        self.nickname = trim_arg(args.arg3)

        @numcheck = trim_arg(args.arg2)
      end

      def required_args
        [ self.category, self.item_num, self.nickname ]
      end

      def check_valid_category
        cats = %w(weapons weapon armor shields shield bags bag)

        return nil if cats.include?(self.category)
        return t('pf2egear.bad_category')
      end

      def check_is_number
        return nil if @numcheck.to_i.to_s == @numcheck
        return t('pf2egear.must_specify_by_number')
      end

      def handle
        found = Pf2egear::Inventory.item(enactor, self.category, self.item_num)

        return if Pf2e::CharState.emit_error!(client, found)

        item = found.state

        # Give the item its nickname.
        item.update(nickname: self.nickname)

        client.emit_success t('pf2egear.item_rename_ok', :name => item.name, :nickname => self.nickname)
      end

    end
  end
end
