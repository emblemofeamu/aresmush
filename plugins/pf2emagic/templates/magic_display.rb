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
            spell_list = spells_today[charclass] || {}

            spell_list = Pf2emagic.sort_level_spell_list(spell_list) unless spell_list.empty?

            list << format_prepared_spells(@char, charclass, spell_list, trad_info)
          elsif caster_type == 'spontaneous'
            repertoire = @magic.repertoire
            spell_list = repertoire[charclass] || {}

            spell_list = Pf2emagic.sort_level_spell_list(spell_list) unless spell_list.empty?

            list << format_spont_spells(@char, charclass, spell_list, spells_today, trad_info)
          else next
          end
        end

        list

      end

      def has_focus_spells
        focus_spells = @magic.focus_spells
        focus_cantrips = @magic.focus_cantrips

        !((focus_spells.keys + focus_cantrips.keys).empty?)
      end

      def focus_spells
        tradition = @magic.tradition

        fstype_to_cc = Global.read_config('pf2e_magic', 'focus_type_by_class').invert

        focus_spells = @magic.focus_spells
        focus_cantrips = @magic.focus_cantrips

        fs = (focus_spells.keys + focus_cantrips.keys).uniq.sort

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
        !(@magic.signature_spells.empty?)
      end

      def signature_spells

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

        list.join("%r")
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

        trad_string = "#{title_color}#{charclass}%xn: #{trad} (#{prof})%b%b%bBonus: #{atk}%r%r"

        # Spell List Block
        list = []

        spell_list.each_pair do |level, splist|
          list << "%b%b%xh#{level}%xn: #{splist.sort.join(", ")}"
        end

        "#{trad_string}#{list.join("%r")}"
      end

      def format_spont_spells(char, charclass, spell_list, spells_today, trad_info)
        # Stat Block
        trad = Pf2e.pretty_string(trad_info[0])
        prof = Pf2e.pretty_string(trad_info[1].slice(0).upcase)
        atk = PF2Magic.get_spell_attack_bonus(char, charclass)

        trad_string = "#{title_color}#{charclass}%xn: #{trad} (#{prof})%b%b%bBonus: #{atk}%r%r"

        # Spells Remaining Block
        remaining = []
        remaining_msg = "#{item_color}Remaining Today:%xn"

        # Spells_today can be an empty hash prior to first rest / approval.
        today_list = spells_today[charclass] || {}

        today_list.each_pair do |level, amt|
          remaining << "%b%b%xh#{level}:%xn #{amt}"
        end

        # Spell List Block
        splist_displ = []

        spell_list.each_pair do |level, splist|
          splist_displ << "#{item_color}#{level.capitalize}:%xn #{splist.sort.join(", ")}"
        end

        "#{trad_string}#{remaining_msg} #{remaining.join("%b%b")}%r%r%b%b#{splist_displ.join("%r%b%b")}"
      end

      def format_focus_spells(char, charclass, fstype, trad_info, spell_list=nil, cantrip_list=nil)
        # Stat Block
        trad = Pf2e.pretty_string(trad_info[0])
        prof = Pf2e.pretty_string(trad_info[1].slice(0).upcase)
        atk = PF2Magic.get_spell_attack_bonus(char, charclass)

        trad_string = "#{title_color}#{charclass}%xn: #{trad} (#{prof})%b%b%bBonus: #{atk}%r"

        # Spell List Block

        cantrips = cantrip_list ? "%b%b#{item_color}Cantrips (#{fstype.capitalize}):%xn #{cantrip_list.sort.join(", ")}%r" : ""

        spells = spell_list ? "%b%b#{item_color}Focus Spells (#{fstype.capitalize}):%xn #{spell_list.sort.join(", ")}" : ""

        "#{trad_string}#{cantrips}#{spells}"
      end

      def format_innate_spells(char, name, values, prof)
        pbonus = Pf2e.get_prof_bonus(char, prof)
        p_short = prof.slice[0].upcase

        level = values['level']
        name = Pf2e.pretty_string(name)
        trad = Pf2e.pretty_string(values['tradition'])

        amod = Pf2eAbilities.abilmod(Pf2eAbilities.get_score char, values['cast_stat'])

        atk_bonus = amod + pbonus

        "%b%b#{item_color}#{name}%xn: %xhLevel%xn: #{level} %xhTradition%xn: #{trad} (#{p_short}) %xhBonus%xn: #{atk_bonus}"
      end


    end
  end
end
