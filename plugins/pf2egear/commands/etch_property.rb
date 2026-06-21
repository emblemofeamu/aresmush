module AresMUSH
  module Pf2egear
    class PF2EtchPropertyCmd
      include CommandHandler

      attr_accessor :target, :category, :item_index, :rune_name

      def parse_args
          if (args = cmd.args.match(/([^\s=]+)=(\w+)\/(\d+)\/(.*)/))
            self.target = args[1]
            self.category = args[2]
            @item_index = args[3].to_i
            self.rune_name = args[4]
          else
            client.emit_failure t('pf2egear.rune_property_cmd_fail')
            return
          end
      end

      def check_permissions
        # Admin may only swap out runes
        if !enactor.is_admin?
          client.emit_failure t("pf2egear.rune_no_admin")
          return
        end
      end

      def check_character_exists
        if !(@char = Character.find_one_by_name(self.target))
          return t('pf2egear.target_not_found', :name => self.target)
          return nil
        end
      end
      
      def check_item_exists
        case category
        when "weapons", "weapon"
          @item = Pf2egear.items_in_inventory(@char.weapons).to_a[@item_index]
        when "armor"
          @item = Pf2egear.items_in_inventory(@char.armor).to_a[@item_index]
        end
        if @item.nil?
          return t('pf2egear.not_found')
          return nil
        end
      end

      def handle
        # All validation checks have passed
        # Property Runes are a toggle, essentially. The list will have it or not.
        runes = @item.runes || {}
        runes["property"] ||= { "list" => [] }
        list = runes["property"]["list"] || []
        
        # Remove it if it's there, add it if it's not
        if list.include? self.rune_name
          # Has it, so remove it
          list.delete(self.rune_name)
          operation = "unset"
        else
          # Doesn't have it, add it and sort the list
          list << self.rune_name
          list.sort!
          operation = "set"
        end
        runes["property"]["list"] = list
        @item.update(runes: runes)
        client.emit_success t('pf2egear.rune_property_set', :rune_name => self.rune_name.titlecase, :operation => operation, :char => self.target.titlecase, :item_name => @item.nickname.nil? ? @item.name : @item.nickname)
      end
    end
  end
end
