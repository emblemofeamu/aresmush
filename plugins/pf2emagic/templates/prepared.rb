module AresMUSH
  module Pf2emagic
    class PF2DisplayPreparedSpellsTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :spell_list, :client

      def initialize(char, spell_list, client = nil)
        @char = char
        @spell_list = spell_list
        @client = client

        super File.dirname(__FILE__) + "/prepared.erb"

      end

      def title
        t('pf2emagic.prepared_spells_title', :name => @char.name)
      end

      def textline(title)
        @client && @client.screen_reader ? title : line_with_text(title)
      end

      def spells_per_day
        @char.magic.spells_per_day
      end

      def help_text
        t('pf2emagic.prepared_spells_help')
      end

      def spells
        @spell_list.map do |charclass, by_level|
          sorted = Pf2emagic.sort_level_spell_list(by_level)

          lines = sorted.map do |level, spell_names|
            heading = "%b%b#{item_color}#{Pf2emagic.rank_label(level)} (#{slot_summary(charclass, level)})%xn"
            names = "%b%b%b%b#{Array(spell_names).sort.join(", ")}"

            "#{heading}%r#{names}"
          end

          format_class_spell_list(charclass, lines)
        end
      end

      def slot_summary(charclass, level)
        parts = [ count_with_noun(base_slots(charclass, level), 'slot') ]

        Pf2emagic.restricted_slots_at(@char, charclass, level).each_pair do |restriction, count|
          parts << count_with_noun(count, "#{restriction} slot") if count.to_i.positive?
        end

        parts.join(" + ")
      end

      def base_slots(charclass, level)
        for_class = spells_per_day[charclass]
        return 0 unless for_class.is_a?(Hash)

        key = for_class.keys.find { |k| k.to_s.casecmp?(level.to_s) }
        key ? for_class[key].to_i : 0
      end

      def count_with_noun(count, noun)
        "#{count.to_i} #{noun}#{'s' unless count.to_i == 1}"
      end

      def format_class_spell_list(charclass, lines)
        "#{textline("#{charclass} Spells")}%r%r#{lines.join("%r%r")}%r"
      end

    end
  end
end
