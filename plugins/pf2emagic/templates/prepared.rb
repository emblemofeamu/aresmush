module AresMUSH
  module Pf2emagic
    class PF2DisplayPreparedSpellsTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :spell_list

      def initialize(char, spell_list)
        @char = char
        @spell_list = spell_list

        super File.dirname(__FILE__) + "/prepared.erb"

      end

      def title
        t('pf2emagic.prepared_spells_title', :name => @char.name)
      end

      def spells_per_day
        @char.magic.spells_per_day
      end

      def spells

        list = []

        @spell_list.each_pair do |charclass, spells|
          sorted_spells = Pf2emagic.sort_level_spell_list(spells)
          daily_spells_for_charclass = spells_per_day[charclass]
          sublist = []

          sorted_spells.each_pair do |level, list|
            max_for_level = daily_spells_for_charclass[level]

            sublist << "%b%b#{item_color}#{level}%xn (max #{max_for_level}): #{list.sort.join(", ")}"
          end

          list << format_class_spell_list(charclass, sublist)
        end

        list
      end

      def format_class_spell_list(charclass, spells)
        # Spells come to this function as an array of formatted level lists, so all we need to do is
        # arrange by class.

        "#{title_color}#{charclass} Spells%xn%r%r#{spells.join("%r")}%r"
      end

    end
  end
end
