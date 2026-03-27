module AresMUSH
  module Pf2egear

    class Pf2eDisplayItemTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :item, :client, :category

      def initialize(char, item, category, client)
        @char = char
        @item = item
        @category = category
        @client = client

        super File.dirname(__FILE__) + "/display_item.erb"
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def title
        name = @item.nickname ? "#{@item.nickname} (#{@item.name})" : @item.name

        t('pf2egear.item_view_title', :name => name)
      end

      def bulk
        b = @item.bulk

        b == 0.1 ? "L" : b.to_i
      end

      def traits
        @item.traits.sort.join(", ")
      end

      def level
        @item.level
      end

      def sell_price
        Pf2egear.display_money(@item.price / 2)
      end

      def item_info

        fmt_list = []

        case @category 
        when "weapon", "weapons"
          fmt_list << "%b%b#{left("#{item_color}Category:%xn #{@item.category.capitalize}", 37)}"
          fmt_list << "%b#{left("#{item_color}Group:%xn #{@item.group}", 37)}%r"

          twoh_dmg = @item.wp_damage_2h ? " (#{@item.wp_damage_2h} 2H)" : ""

          fmt_list << "%b%b#{left("#{item_color}Damage:%xn #{@item.wp_damage} #{@item.wp_damage_type}#{twoh_dmg}", 18)}"

          # Other stuff
          fmt_list << "%b#{left("#{item_color}Range:%xn #{@item.range}", 18)}"
          fmt_list << "%b#{left("#{item_color}Reload:%xn #{@item.reload}", 18)}"
          fmt_list << "%b#{left("#{item_color}Range:%xn #{@item.hands}", 18)}%r"

          # Can this item be used? 
          usable = @item.use.empty? ? "This item cannot be used." : "#{item_color}Use Effects:%xn #{@item.use}"

          fmt_list << "%b%b#{usable}%r"
        when "armor"
          fmt_list << "%b%b#{left("#{item_color}Category:%xn #{@item.category.capitalize}", 37)}"
          fmt_list << "%b#{left("#{item_color}Group:%xn #{@item.group}", 37)}%r"

          fmt_list << "%b%b#{left("#{item_color}AC Bonus:%xn #{@item.ac_bonus}", 37)}"
          fmt_list << "%b#{left("#{item_color}Minimum Strength Score:%xn #{@item.min_str}", 37)}%r"
          fmt_list << "%b%b#{left("#{item_color}Check Penalty:%xn #{@item.check_penalty}", 26)}"
          fmt_list << "%b#{left("#{item_color}Speed Penalty:%xn #{@item.speed_penalty} feet", 26)}"
          fmt_list << "%b#{left("#{item_color}Max Dex Bonus:%xn #{@item.dex_cap}", 26)}%r"
        when "magicitem"

          # Can this item be used? 
          usable = @item.use.empty? ? "This item cannot be used." : "#{item_color}Use Effects:%xn #{@item.use}"

          fmt_list << "%b%b#{usable}%r"

        when "shield", "shields"

          # Calculate shield HP display.
          disp_hp = Pf2egear.display_shield_hp(@item)
          fmt_list << "%b%b#{left("#{item_color}HP:%xn #{disp_hp}", 26)}"

          # Other stuffs. 
          fmt_list << "%b#{left("#{item_color}AC Bonus:%xn #{@item.ac_bonus}", 26)}"
          fmt_list << "%b#{left("#{item_color}Hardness:%xn #{@item.hardness}", 26)}%r"

          # Does this shield have a weapon (e.g. boss or spikes) attached?

          att_weapon = @item.weapon ? @item.weapon : false

          if att_weapon
            weapon_name = att_weapon.nickname ? "#{att_weapon.nickname} (#{att_weapon.name})" : att_weapon.name

            fmt_list << "%b%b#{item_color}Attached Weapon:%xn #{weapon_name}%r"
          end

        end

        fmt_list 

      end

      def magical_properties

        if @category == "magicitem"

          list = []

          bonus_list = []

          bonuses = @item.bonus.each_pair do |k,v|

            bonus_list << "+#{v} to #{k}"

          end

          list << "%b%b#{item_color}Bonuses:%xn #{bonus_list.join(", ")}"

          
        elsif @category == ("shield" || "shields")
          
          return [ "%b%b#{t('pf2egear.shields_dont_have_magic')}" ]

        else

          list = []

          unformatted_talismans = @item.talisman.nil? ? [] : @item.talisman
          unformatted_fundamental_runes = @item.runes["fundamental"].nil? ? {} : @item.runes["fundamental"]
          unformatted_property_runes = @item.runes&.dig("property", "list") || []

          talismans = format_talismans(unformatted_talismans)
          fund_runes = format_fund_runes(unformatted_fundamental_runes)
          prop_runes = format_prop_runes(unformatted_property_runes)

          list << talismans
          list << "%b%b#{item_color}Runes:%xn"
          list << fund_runes
          list << prop_runes

        end

        list

      end

      def format_talismans(talismans)
        "%b%b#{item_color}Talismans:%xn #{talismans.sort.join(", ")}"
      end

      def format_fund_runes(runes)

        return "%b%b%b%b%xh%xwFundamental:%xn None." if runes.empty?

        striking_rune_names = ["None", "Standard", "Greater", "Major"]
        "%b%b%b%b%xh%xwFundamental:%xn Potency: +#{runes['potency']}, #{@category.downcase == "armor" ? "Resilient" : "Striking"} (#{striking_rune_names[runes['power'].nil? ? 0 : runes['power']]})"
      end

      def format_prop_runes(runes)

        return "%b%b%b%b%xh%xwProperty:%xn None." if runes.empty? 

        "%b%b%b%b%xh%xwProperty:%xn #{runes.sort.join(", ")}"
      end

    end

  end
end
