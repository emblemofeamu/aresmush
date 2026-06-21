$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Pf2egear

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config("pf2e_gear_options", "shortcuts")
    end

    def self.get_cmd_handler(client, cmd, enactor)
      case cmd.root
      when "pay"
        return PF2PayCmd
      when "money"
        return PF2MoneyCmd
      when "browse"
        return PF2BrowseGearCmd
      when "buy"
        return PF2BuyCmd
      when "sell"
        return PF2SellCmd
      when "gear"
        case cmd.switch
        when "rename"
          return PF2GearRenameCmd
        when "equip"
          return PF2GearEquipCmd
        when "unequip"
          return PF2GearUnequipCmd
        when "invest"
          return PF2InvestCmd
        when "uninvest"
          return PF2UninvestCmd
        else
          return PF2DisplayGearCmd
        end
      when "equip"
        return PF2GearEquipCmd
      when "unequip"
        return PF2GearUnequipCmd
      when "invest"
        return PF2InvestCmd
      when "uninvest"
        return PF2UninvestCmd
      when "bag"
        case cmd.switch
        when "store"
          return PF2BagStoreCmd
        when "retrieve"
          return PF2BagRetrieveCmd
        else
          return PF2BagViewCmd
        end
      when "item"
        case cmd.switch
        when "view"
          return PF2ItemViewCmd
        end
      when "use"
        return PF2UseItemCmd
      when "listmoney"
        return PF2ListMoneyCmd
      when "etch"
        case cmd.switch
          when"potency"
            return PF2EtchPotencyCmd
          when "striking"
            return PF2EtchPowerCmd
          when "resilient"
            return PF2EtchPowerCmd
          when "property"
            return PF2EtchPropertyCmd
          end
      end
    end

    def self.get_event_handler(event_name)
      nil
    end

    def self.get_web_request_handler(request)
      nil
    end

  end
end
