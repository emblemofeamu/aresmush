module AresMUSH
  module Pf2egear
    class PF2ItemViewCmd
      include CommandHandler

      attr_accessor :target, :category, :item_id

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        if args.arg3.nil?
          self.category = downcase_arg(args.arg1)
          self.item_id = integer_arg(args.arg2)
          @numcheck = trim_arg(args.arg2)
        else
          self.target = downcase_arg(args.arg1)
          self.category = downcase_arg(args.arg2)
          self.item_id = integer_arg(args.arg3)
          @numcheck = trim_arg(args.arg3)
        end
      end

      def required_args
        [ self.category, self.item_id ]
      end

      def check_valid_category
        cats = %w(weapons weapon armor shields shield magicitem)

        return nil if cats.include?(self.category)
        return t('pf2egear.no_detailed_item_info')
      end

      def check_is_number
        return nil if @numcheck.to_i.to_s == @numcheck
        return t('pf2egear.must_specify_by_number')
      end

      def handle

        # Identify the item to be viewed.

        index = self.item_id

        # Find the character whose inventory we're viewing if specified, otherwise use enactor.
        if !self.target.nil?
          char = Character.find_one_by_name(self.target)

          # Bail out if we can't find the character.
          if !char
            client.emit_failure t('pf2e.not_found')
            return
          end
        else
          char = enactor
        end

        found = Pf2egear::Inventory.item(char, category, index)

        return t(found.key) if found.err?

        item = found.state

        template = Pf2eDisplayItemTemplate.new(enactor, item, self.category, client)

        client.emit template.render

      end

    end
  end
end
