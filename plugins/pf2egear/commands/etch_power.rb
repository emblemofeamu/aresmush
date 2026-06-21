module AresMUSH
  module Pf2egear
    class PF2EtchPowerCmd
      include CommandHandler

      attr_accessor :operation, :target, :category, :item_index, :rune_lvl

      def parse_args
          if (args = cmd.to_s.match(/etch\/(striking|resilient)\s([^\s=]+)=(\w+)\/(\d+)\/(\d+)$/))
            self.operation = args[1]
            self.target = args[2]
            self.category = args[3]
            @item_index = args[4].to_i
            self.rune_lvl = args[5].to_i
          else
            client.emit_failure t('pf2egear.rune_cmd_fail', :rune_type => "[striking/resiliency]")
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

      def check_item_category
        # Validate the category we are editing
        if !["weapon", "weapons", "armor"].include?(self.category.downcase)
          return t('pf2egear.bad_category')
          return nil
        end
        if !((["weapon", "weapons"].include?(self.category.downcase) && self.operation == "striking") || (["armor"].include?(self.category.downcase) && self.operation == "resilient"))
          return t('pf2egear.rune_bad_operation_for_type', :operation => self.operation.titlecase, :category => self.category)
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

      def check_rune_level
        if (self.rune_lvl < 0 || self.rune_lvl > 3)
          return t('pf2egear.rune_out_of_range', )
          return nil
        end
        if (self.rune_lvl > @item.runes["fundamental"]["potency"])
          return t('pf2egear.rune_power_gt_potency')
          return nil
        end
      end

      def handle
        # All validation checks have passed
        # Assign the value to the item.
        
        runes = @item.runes
        old_rune_lvl = runes["fundamental"]["power"].nil? ? "0" : runes["fundamental"]["power"]
        runes["fundamental"]["power"] = self.rune_lvl.to_i
        @item.update(runes: runes)
        client.emit_success t('pf2egear.rune_potency_set', :rune => self.operation.titlecase, :char => @char.name, :item_name => @item.nickname.nil? ? @item.name : @item.nickname, :old_rune_lvl => old_rune_lvl, :rune_lvl => self.rune_lvl)
      end
    end
  end
end
