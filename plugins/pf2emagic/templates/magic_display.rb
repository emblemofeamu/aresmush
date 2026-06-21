module AresMUSH
  module Pf2emagic

    class PF2MagicDisplayTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :client, :magic

      def initialize(char, magic, client)
        @char = char
        @client = client
        @magic = magic

        super File.dirname(__FILE__) + "/magic_display.erb"
      end

      def name
        @char.name
      end

      def textline(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def spell_details_by_charclass
        tradition = @magic.tradition

        charclass_list = tradition.keys.sort - [ 'innate ']
        spells_today = @magic.spells_today
        list = []

        charclass_list.each do |charclass|
          trad_info = tradition[charclass]

          caster_type = Pf2emagic.get_caster_type(charclass)

          if caster_type == 'prepared'
            # Can be blank prior to first rest.
            prepared_spells = @magic.spells_prepared || {}
            spell_list = spells_today[charclass]
            spell_list = prepared_spells[charclass] if spell_list.nil? || spell_list.empty?
            spell_list ||= {}

            spell_list = Pf2emagic.sort_level_spell_list(spell_list) unless spell_list.empty?

            list << format_prepared_spells(@char, charclass, spell_list, trad_info)
          elsif caster_type == 'spontaneous'
            list << format_spont_spells(@char, charclass, spells_today, trad_info)
          else next
          end
        end

        list

      end

      def has_focus_spells
        focus_spells = @magic.focus_spells
        focus_cantrips = @magic.focus_cantrips

        (focus_spells.values + focus_cantrips.values).any? { |list| !Array(list).empty? }
      end

      def focus_spells
        tradition = @magic.tradition

        fstype_to_cc = Global.read_config('pf2e_magic', 'focus_type_by_class').invert

        focus_spells = @magic.focus_spells
        focus_cantrips = @magic.focus_cantrips

        fs = (focus_spells.keys + focus_cantrips.keys).uniq.sort
        fs = fs.select do |focus_type|
          !Array(focus_spells[focus_type]).empty? || !Array(focus_cantrips[focus_type]).empty?
        end

        list = []
        fs.each do |fs|
          charclass = fstype_to_cc[fs]
          trad_info = tradition[charclass]
          spell_list = focus_spells[fs]
          cantrip_list = focus_cantrips[fs]
          list << format_focus_spells(@char, charclass, fs, trad_info, spell_list, cantrip_list)
        end

        list
      end

      def has_signature_spells
        signatures = @magic.signature_spells || {}

        signatures.any? do |charclass, levels|
          Pf2emagic.get_caster_type(charclass) == 'spontaneous' &&
            levels.is_a?(Hash) &&
            levels.values.any? { |spells| !Array(spells).empty? }
        end
      end

      def signature_spells
        signatures = @magic.signature_spells || {}
        tradition = @magic.tradition || {}
        list = []

        signatures.keys.sort.each do |charclass|
          next unless Pf2emagic.get_caster_type(charclass) == 'spontaneous'

          sig_levels = signatures[charclass]
          next unless sig_levels.is_a?(Hash)

          sorted = Pf2emagic.sort_level_spell_list(sig_levels)
          next if sorted.empty?

          trad_info = tradition[charclass]
          next unless trad_info

          trad = Pf2e.pretty_string(trad_info[0])
          prof = Pf2e.pretty_string(trad_info[1].slice(0).upcase)
          atk = PF2Magic.get_spell_attack_bonus(@char, charclass)

          sublist = []
          sorted.each_pair do |level, spells|
            next if Array(spells).empty?

            display_level = spell_level_label(level)
            sublist << "%b%b#{item_color}#{display_level}:%xn #{Array(spells).sort.join(", ")}"
          end

          next if sublist.empty?

          header = "#{title_color}#{charclass}%xn: #{trad} (#{prof})%b%b%bBonus: #{atk}%r"
          list << "#{header}#{sublist.join("%r")}"
        end

        list
      end

      def has_innate_spells
        !(@magic.innate_spells.empty?)
      end

      def innate_spells
        spell_list = @magic.innate_spells
        prof = @magic.tradition['innate'][1]

        list = []

        spell_list.each_pair do |name, values|
          list << format_innate_spells(@char, name, values, prof)
        end

        list
      end

      def innate_remaining_spells_today
        spells_today = @magic.spells_today || {}
        innate_today = spells_today['innate'] || {}

        return "%r#{item_color}Remaining Innate Spells Today:%xn None" if innate_today.empty?

        grouped = Pf2emagic.sort_level_spell_list(innate_today)
        list = []

        grouped.each_pair do |level, spells|
          next if Array(spells).empty?

          display_level = spell_level_label(level)
          list << "%b%b#{item_color}#{display_level}:%xn #{Array(spells).sort.join(", ")}"
        end

        return "%r#{item_color}Remaining Innate Spells Today:%xn None" if list.empty?

        "%r#{item_color}Remaining Innate Spells Today:%xn%r#{list.join("%r")}" 
      end

      def revelation_locked
        @magic.revelation_locked
      end

      def revelation_lock_msg
        t('pf2emagic.revelation_locked') + "%r"
      end

      def format_prepared_spells(char, charclass, spell_list, trad_info)
        # Stat Block
        trad = Pf2e.pretty_string(trad_info[0])
        prof = Pf2e.pretty_string(trad_info[1].slice(0).upcase)
        atk = PF2Magic.get_spell_attack_bonus(char, charclass)
        focus_pool = format_focus_pool(charclass)
        stat_block_break = focus_pool.empty? ? "%r%r" : "%r"

        trad_string = "#{title_color}#{charclass}%xn: #{trad} (#{prof})%b%b%bBonus: #{atk}#{stat_block_break}"

        # Spell List Block
        list = []
        prepared_msg = "#{item_color}Prepared Spells Remaining:%xn"

        spell_list.each_pair do |level, splist|
          next if Array(splist).empty?

          display_level = spell_level_label(level)
          list << "%b%b#{item_color}#{display_level}:%xn #{splist.sort.join(", ")}"
        end

        return "#{trad_string}#{focus_pool}#{prepared_msg} None." if list.empty?

        "#{trad_string}#{focus_pool}#{prepared_msg}%r#{list.join("%r")}"
      end

      def format_spont_spells(char, charclass, spells_today, trad_info)
        # Stat Block
        trad = Pf2e.pretty_string(trad_info[0])
        prof = Pf2e.pretty_string(trad_info[1].slice(0).upcase)
        atk = PF2Magic.get_spell_attack_bonus(char, charclass)
        focus_pool = format_focus_pool(charclass)
        stat_block_break = focus_pool.empty? ? "%r%r" : "%r"

        trad_string = "#{title_color}#{charclass}%xn: #{trad} (#{prof})%b%b%bBonus: #{atk}#{stat_block_break}"

        # Spells Remaining Block
        remaining = []
        remaining_msg = "#{item_color}Remaining Spell Slots Today:%xn"

        # Spells_today can be an empty hash prior to first rest / approval.
        today_list = spells_today[charclass] || {}

        today_list.each_pair do |level, amt|
          display_level = spell_level_label(level)
          remaining << "%b%b%xh#{display_level}:%xn #{amt}"
        end

        remaining_data = if remaining.empty?
                           " None."
                         else
                           "%r#{remaining.join("%r")}"
                         end

        "#{trad_string}#{focus_pool}#{remaining_msg}#{remaining_data}"
      end

      def format_focus_pool(charclass)
        focus_type = Global.read_config('pf2e_magic', 'focus_type_by_class', charclass)
        return '' unless focus_type

        focus_spells = @magic.focus_spells || {}
        focus_cantrips = @magic.focus_cantrips || {}
        has_focus_magic = !Array(focus_spells[focus_type]).empty? || !Array(focus_cantrips[focus_type]).empty?

        return '' unless has_focus_magic

        focus_pool = @magic.focus_pool || {}
        max = focus_pool['max'].to_i
        current = focus_pool['current'].to_i

        return '' if max.zero? && current.zero?

        "#{item_color}Focus Points:%xn #{max}%r%r#{item_color}Remaining Focus Points:%xn #{current}%r"
      end

      def format_focus_spells(char, charclass, fstype, trad_info, spell_list=nil, cantrip_list=nil)
        # Stat Block
        trad = Pf2e.pretty_string(trad_info[0])
        prof = Pf2e.pretty_string(trad_info[1].slice(0).upcase)
        atk = PF2Magic.get_spell_attack_bonus(char, charclass)

        trad_string = "#{title_color}#{charclass}%xn: #{trad} (#{prof})%b%b%bBonus: #{atk}%r"

        # Spell List Block

        cantrips = !Array(cantrip_list).empty? ? "%b%b#{item_color}Cantrips (#{fstype.capitalize}):%xn #{cantrip_list.sort.join(", ")}%r" : ""

        spells = !Array(spell_list).empty? ? "%b%b#{item_color}Focus Spells (#{fstype.capitalize}):%xn #{spell_list.sort.join(", ")}" : ""

        "#{trad_string}#{cantrips}#{spells}"
      end

      def format_innate_spells(char, name, values, prof)
        pbonus = Pf2e.get_prof_bonus(char, prof)
        # Grab the first letter of the proficiency label safely.
        p_short = prof.to_s.slice(0).to_s.upcase

        level = values['level']
        name = Pf2e.pretty_string(name)
        trad = Pf2e.pretty_string(values['tradition'])

        amod = Pf2eAbilities.abilmod(Pf2eAbilities.get_score char, values['cast_stat'])

        atk_bonus = amod + pbonus

        "%b%b#{item_color}#{name}%xn: %xhLevel%xn: #{level} %xhTradition%xn: #{trad} (#{p_short}) %xhBonus%xn: #{atk_bonus}"
      end

      def spell_level_label(level)
        level_str = level.to_s
        return 'Cantrip' if level_str.downcase == 'cantrip'

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

      def help_text
        tradition = @magic.tradition || {}
        charclasses = tradition.keys - ['innate', 'innate ']

        caster_types = charclasses.map { |cc| Pf2emagic.get_caster_type(cc) }
                                 .select { |type| ['prepared', 'spontaneous'].include?(type) }
                                 .uniq

        return '' if caster_types.empty?
        return t('pf2emagic.spellbook_help') if caster_types == ['prepared']
        return t('pf2emagic.repertoire_help') if caster_types == ['spontaneous']

        "#{t('pf2emagic.spellbook_help')} %b%b#{t('pf2emagic.repertoire_help')}"
      end

    end
  end
end
