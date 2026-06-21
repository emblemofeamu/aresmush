module AresMUSH
  module Pf2emagic

    class PF2SpellbookTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :spellbook, :client

      def initialize(char, charclass, spellbook, client, title_key='pf2emagic.spellbook_title')
        @char = char
        @charclass = charclass
        @spellbook = spellbook
        @client = client
        @title_key = title_key

        super File.dirname(__FILE__) + "/spellbook.erb"
      end

      def title
        t(@title_key, :name => @char.name)
      end

      def spellbook_list
        list = []

        @spellbook.each_pair do |key, value|
          list << format_spell_list_block(key, value)

        end

        list
      end

      def format_spell_list_block(key, value)
        charclass = value.is_a?(Array) ? @charclass : key
        selected_level = value.is_a?(Array) ? key : nil

        section = []
        section << section_title(charclass)

        stats = class_stats_line(charclass)
        section << stats unless stats.empty?

        if show_total_slots?(charclass)
          section << total_slots_block(charclass)
        end

        section << section_title("#{charclass} Spells Known")
        section << known_spells_block(key, value)

        if show_signature_spells?(charclass)
          signature_block = signature_spells_block(charclass, selected_level)
          unless signature_block.empty?
            section << section_title("#{charclass} Signature Spells")
            section << signature_block
          end
        end

        section.join("%r")
      end

      def section_title(title)
        @client.screen_reader ? "#{title}:" : line_with_text(title)
      end

      def class_stats_line(charclass)
        tradition = @char.magic.tradition || {}
        trad_info = tradition[charclass]
        return '' unless trad_info

        trad = Pf2e.pretty_string(trad_info[0])
        prof = Pf2e.pretty_string(trad_info[1].slice(0).upcase)
        atk = PF2Magic.get_spell_attack_bonus(@char, charclass)

        "#{item_color}Tradition:%xn #{trad} (#{prof})%b%b%b#{item_color}Bonus:%xn #{atk}"
      end

      def show_total_slots?(charclass)
        caster_type = Pf2emagic.get_caster_type(charclass)

        return false unless ['prepared', 'spontaneous'].include?(caster_type)
        return true if @title_key == 'pf2emagic.spellbook_title' && caster_type == 'prepared'
        return true if @title_key == 'pf2emagic.repertoire_title' && caster_type == 'spontaneous'

        false
      end

      def total_slots_block(charclass)
        slots = @char.magic.spells_per_day[charclass] || {}
        sorted_slots = Pf2emagic.sort_level_spell_list(slots)

        return "#{item_color}Total Spell Slots:%xn None." if sorted_slots.empty?

        lines = sorted_slots.map do |level, amount|
          "%b%b#{item_color}#{spellbook_level_label(level)}:%xn #{amount}"
        end

        "#{item_color}Total Spell Slots:%xn%r#{lines.join("%r")}"
      end

      def known_spells_block(key, value)
        if value.is_a? Array
          level_label = spellbook_level_label(key)
          spells = value.sort.join(", ")

          return "#{item_color}#{level_label}:%xn%r%b%b#{spells}"
        end

        sorted = Pf2emagic.sort_level_spell_list(value)
        lines = []

        sorted.each_pair do |level, spell_list|
          spells = Array(spell_list).sort.join(", ")
          lines << "#{item_color}#{spellbook_level_label(level)}:%xn"
          lines << "%b%b#{spells}"
        end

        lines.join("%r")
      end

      def show_signature_spells?(charclass)
        @title_key == 'pf2emagic.repertoire_title' && Pf2emagic.get_caster_type(charclass) == 'spontaneous'
      end

      def signature_spells_block(charclass, selected_level=nil)
        signatures = @char.magic.signature_spells || {}
        class_signatures = signatures[charclass] || {}

        return '' unless class_signatures.is_a?(Hash)

        sorted = Pf2emagic.sort_level_spell_list(class_signatures)
        lines = []

        sorted.each_pair do |level, spells|
          next if selected_level && level.to_s != selected_level.to_s
          next if Array(spells).empty?

          lines << "#{item_color}#{spellbook_level_label(level)}:%xn"
          lines << "%b%b#{Array(spells).sort.join(", ")}"
        end

        lines.join("%r")
      end

      def spellbook_level_label(level)
        level_str = level.to_s
        return 'Cantrips' if level_str.downcase == 'cantrip'

        level_num = level_str.to_i
        "#{ordinal(level_num)}-level"
      end

      def ordinal(number)
        abs_num = number.to_i.abs

        return "#{number}th" if (11..13).include?(abs_num % 100)

        suffix = case abs_num % 10
                 when 1 then 'st'
                 when 2 then 'nd'
                 when 3 then 'rd'
                 else 'th'
                 end

        "#{number}#{suffix}"
      end

    end
  end
end
