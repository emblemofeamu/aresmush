module AresMUSH
  module Pf2e

    class PF2CGReviewUnlockDisplay < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :client

      def initialize(char, client)
        @char = char
        @client = client

        base_info = @char.pf2_base_info
        @ancestry = base_info['ancestry']
        @heritage = base_info['heritage']
        @background = base_info['background']
        @charclass = base_info['charclass']
        @subclass = base_info['specialize']
        @subclass_option = base_info['specialize_info']

        @ancestry_info = @ancestry.blank? ? {} : Global.read_config('pf2e_ancestry', @ancestry)
        @heritage_info = @heritage.blank? ? {} : Global.read_config('pf2e_heritage', @heritage)
        @background_info = @background.blank? ? {} : Global.read_config('pf2e_background', @background)
        @charclass_info = @charclass.blank? ? {} : Global.read_config('pf2e_class', @charclass)
        @subclass_info = @subclass.blank? ? {} : Global.read_config('pf2e_specialty', @charclass, @subclass)
        @faith_info = @char.pf2_faith

        @baseinfolock = @char.pf2_baseinfo_locked
        @class_features_info = @charclass_info['chargen']
        @subclass_features_info = @subclass_info['chargen']

        # A specialty's own options (a wizard's school, a draconic sorcerer's dragon) can grant
        # skills and languages too.
        subclass_choose = @subclass_info['choose']
        subclass_options = subclass_choose.is_a?(Hash) ? subclass_choose['options'] : nil
        @subclass_option_info = (subclass_options.is_a?(Hash) && !@subclass_option.blank?) ?
                                subclass_options[@subclass_option] : nil
        @subclassopt_features_info = @subclass_option_info.is_a?(Hash) ? @subclass_option_info['chargen'] : nil

        @to_assign = @char.pf2_to_assign
        @boosts = @char.pf2_boosts_working

        super File.dirname(__FILE__) + "/cg_review_unlocked.erb"
      end

      def baseinfolock
        @baseinfolock
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def name
        @char.name
      end

      def unset
      # Shown when there's an option the character still has to choose.
        "%xh%xrUNSET%xn"
      end

      def not_applicable
        "-"
      end

      def show(value)
        value.blank? ? unset : value
      end

      def base_info_set
      # Everything the character must choose has been chosen, so they can commit info.
        Pf2e.base_info_set?(@char.pf2_base_info, @faith_info)
      end

      def has_ancestry
        !@ancestry.blank?
      end

      def has_background
        !@background.blank?
      end

      def has_charclass
        !@charclass.blank?
      end

      def show_sofar
      # Ancestry sets size, speed and part of the HP; class sets the rest of it.
        has_ancestry || has_charclass
      end

      def hp_incomplete
      # HP is only complete once both ancestry and class are set.
        if has_ancestry && !has_charclass
          t('pf2e.cg_hp_incomplete_class')
        elsif has_charclass && !has_ancestry
          t('pf2e.cg_hp_incomplete_ancestry')
        end
      end

      def show_traits
      # Traits come from ancestry, heritage, and class.
        has_ancestry || has_charclass
      end

      def show_boosts
      # Boosts come from ancestry, background, and class.
        has_ancestry || has_background || has_charclass
      end

      def show_skills
      # Trained skills come from the character's class, class specialty, background, heritage, and
      # (if a cleric or champion) deity.
        has_charclass || has_background || !config_list(@heritage_info, 'skills').empty?
      end

      def show_other
      # Senses and special abilities come from the character's ancestry, heritage, and background; starting languages come from ancestry.
        has_ancestry || has_background
      end

      def magic_plugin?
        # There might be a better way to do this. There probably is. I'll figure it out later or this'll be a really funny comment when later rolls around.
        AresMUSH.const_defined?("Pf2emagic")
      end

      def show_magic
        magic_plugin? && !magic_stats.empty?
      end

      def magic_stat_blocks
        [
          config_hash(@class_features_info, 'magic_stats'),
          config_hash(@subclass_features_info, 'magic_stats'),
          config_hash(@subclassopt_features_info, 'magic_stats'),
          class_specific_magic_stats,
          config_hash(@heritage_info, 'magic_stats')
        ]
      end

      def class_specific_magic_stats
        case @charclass
        when 'Cleric'
          return {} if @faith_info['deity'].blank?

          config_hash(Global.read_config('pf2e_deities', @faith_info['deity']), 'magic_stats')
        when 'Wizard'
          return {} if @subclass_option.blank?

          config_hash(Global.read_config('pf2e_subclass', 'wizard_school_spells', @subclass_option), 'magic_stats')
        when 'Sorcerer'
          return {} if @subclass != 'Draconic' || @subclass_option.blank?

          dragon = Global.read_config('pf2e_subclass', 'Dragon Exemplar', @subclass_option)

          config_hash(dragon.is_a?(Hash) ? dragon['chargen'] : nil, 'magic_stats')
        else
          {}
        end
      end

      def magic_stats
        @magic_stats ||= magic_stat_blocks.inject({}) { |merged, block| merged.merge(block) }
      end

      def config_hash(source, key)
        return {} if !source.is_a?(Hash)

        source[key].is_a?(Hash) ? source[key] : {}
      end

      def tradition_name
        names = magic_stats['tradition'].is_a?(Hash) ? magic_stats['tradition'].keys : []

        names.empty? ? nil : Pf2e.pretty_string(names.first)
      end

      def tradition
        return tradition_name if tradition_name

        return t('pf2emagic.cg_tradition_from_specialty') if @subclass.blank? && Pf2e.needs_specialty?(@charclass)
        return t('pf2emagic.cg_tradition_from_specialty_choice') if Pf2e.needs_specialty_choice?(@charclass, @subclass)

        nil
      end

      def divine_font_options
        Array(magic_stats['divine_font'])
      end

      def divine_font
        fonts = divine_font_options

        return nil if fonts.empty?
        return Pf2e.pretty_string(fonts.first) if fonts.size == 1

        t('pf2emagic.cg_font_unchosen', :options => fonts.map { |f| Pf2e.pretty_string(f) }.join(" or "))
      end

      def spells_to_choose
        blocks = [ spell_choice_block('repertoire', 'Repertoire'),
                   spell_choice_block('spellbook', 'Spellbook') ].compact

        blocks.empty? ? nil : blocks.join("%r")
      end

      def spell_choice_block(key, list)
        counts = magic_stats[key]

        return nil if !counts.is_a?(Hash) || counts.empty?

        lines = counts.map { |level, num| "%b%b#{item_color}#{spell_level_label(level)}%xn: #{num}" }

        ([ "#{item_color}#{spell_list_label(list)}%xn:" ] + lines).join("%r")
      end

      def spell_list_label(list)
        return t('pf2emagic.cg_spells_to_choose_start_plain', :list => list) if !tradition_name

        t('pf2emagic.cg_spells_to_choose_start', :list => list, :tradition => tradition_name)
      end

      def spell_level_label(level)
        return "Cantrip(s)" if level.to_s.downcase == 'cantrip'

        "#{Pf2emagic.ordinal_level(level)}-rank"
      end

      def innate_spells
        entries = magic_stat_blocks.map { |block| block['innate_spell'] }.select { |entry| entry.is_a?(Hash) }

        return nil if entries.empty?

        innate_blocks(entries.flat_map do |entry|
          Array(entry['name']).map { |name| [ name, entry['tradition'], entry['level'] ] }
        end)
      end

      def innate_blocks(entries)
        grouped = {}

        entries.each do |name, tradition, level|
          trad_label = Pf2e.pretty_string(Array(tradition).first.to_s)
          rank = innate_level_label(level)

          grouped[trad_label] ||= {}
          grouped[trad_label][rank] ||= []
          grouped[trad_label][rank] << name
        end

        blocks = grouped.map do |trad_label, ranks|
          lines = ranks.map { |rank, names| "%b%b#{item_color}#{rank}%xn: #{innate_rank_entries(names)}" }

          ([ "#{item_color}#{innate_heading(trad_label)}%xn:" ] + lines).join("%r")
        end

        blocks.join("%r")
      end

      def innate_heading(trad_label)
        return t('pf2emagic.cg_innate_to_choose_plain') if trad_label.blank?

        t('pf2emagic.cg_innate_to_choose', :tradition => trad_label)
      end

      def innate_rank_entries(names)
        open_count = names.count { |name| name.to_s.casecmp?('open') }
        chosen = names.reject { |name| name.to_s.casecmp?('open') }

        entries = chosen
        entries += [ "#{open_count} open" ] if open_count > 0

        entries.join(", ")
      end

      def innate_level_label(level)
        return "Cantrip" if level.to_s.downcase == 'cantrip' || level.to_i.zero?

        "#{Pf2emagic.ordinal_level(level)}-rank"
      end

      def prepares_from_tradition?
      # Clerics and druids prepare from their tradition's whole spell list. Unlike a witch or a
      # wizard, they have no list to fill.
        return false if !magic_stats['spells_per_day'].is_a?(Hash)

        !magic_stats['repertoire'].is_a?(Hash) && !magic_stats['spellbook'].is_a?(Hash)
      end

      def prepared_list_note
        return t('pf2emagic.cg_prepared_list_note_plain') if !tradition_name

        t('pf2emagic.cg_prepared_list_note', :tradition => tradition_name)
      end

      def open_innate_spells?
        magic_stat_blocks.any? do |block|
          innate = block['innate_spell']

          innate.is_a?(Hash) && Array(innate['name']).any? { |name| name.to_s.casecmp?('open') }
        end
      end

      def chargen_spell_choices?
        return true if magic_stats['repertoire'].is_a?(Hash) || magic_stats['spellbook'].is_a?(Hash)

        open_innate_spells?
      end

      def no_spells_to_select?
        return false if !tradition_name

        !prepares_from_tradition? && !chargen_spell_choices?
      end

      def magic_notes
        notes = []

        notes << t('pf2emagic.cg_magic_note_start') if chargen_spell_choices?
        notes << t('pf2emagic.cg_no_spells_note') if no_spells_to_select?

        notes << prepared_list_note if prepares_from_tradition?

        notes << t('pf2emagic.cg_font_note_start') if divine_font_options.size > 1

        # A champion or ranger has a tradition and nothing else yet, so they get no notes at all.
        notes.empty? ? nil : notes.join("%r")
      end

      def ancestry
        show(@ancestry)
      end

      def heritage
        show(@heritage)
      end

      def background
        show(@background)
      end

      def charclass
        show(@charclass)
      end

      def subclass
        return not_applicable if !Pf2e.needs_specialty?(@charclass)
        show(@subclass)
      end

      def subclass_option
        return not_applicable if !Pf2e.needs_specialty_choice?(@charclass, @subclass)
        show(@subclass_option)
      end

      def deity
        return show(@faith_info['deity']) if use_deity
        @faith_info['deity'].blank? ? not_applicable : @faith_info['deity']
      end

      def use_deity
        Pf2e.needs_deity?(@charclass)
      end

      def is_devotee
        use_deity ? " %xh%xy(REQ)%xn" : ""
      end

      def deity_optional
      # Reminder for a character who has picked a class that doesn't require a deity, so that they can pick a deity if they want to for the funsies.
        has_charclass && !use_deity && @faith_info['deity'].blank?
      end

      def alignment
        show(@faith_info['alignment'])
      end

      def sanctification
        if Pf2e.uses_sanctification?(@charclass)
          show(@faith_info['sanctification'])
        end
      end

      def has_code

        d_edicts = []
        d_anathema = []

        if use_deity
          if !(@faith_info['deity'].blank?)

            d_edicts = Global.read_config('pf2e_deities',
                        @faith_info['deity'],
                        'edicts')
            d_anathema = Global.read_config('pf2e_deities',
                        @faith_info['deity'],
                        'anathema')
          end
        end

        s_edicts = @subclass_info['edicts'] ? @subclass_info['edicts'] : []
        s_anathema = @subclass_info['anathema'] ? @subclass_info['anathema'] : []

        edicts = s_edicts + d_edicts
        anathema = s_anathema + d_anathema

        code = edicts + anathema

        if code.empty?
          nil
        else
          t('pf2e.char_has_code', :edicts=>edicts.join("%r"), :anathema=>anathema.join("%r"))
        end
      end

      def ahp
        ancestry_hp = @heritage_info['ancestry_HP'] ?
                      @heritage_info['ancestry_HP'] :
                      @ancestry_info["HP"]

        ahp = ancestry_hp ? ancestry_hp : 0
      end

      def chp
        class_hp = @charclass_info["HP"] ? @charclass_info["HP"] : 0
      end

      def size
        return not_applicable if !has_ancestry
        @ancestry_info["Size"] ? @ancestry_info["Size"] : "M"
      end

      def speed
        return not_applicable if !has_ancestry
        speed = @ancestry_info["Speed"] ? @ancestry_info["Speed"] : "?"
        "#{speed} feet"
      end

      def traits
        a_traits = @ancestry_info["traits"] ? @ancestry_info["traits"] : []
        h_traits = @heritage_info["traits"] ? @heritage_info["traits"] : []

        traits = (a_traits + h_traits).uniq.difference([ "" ]).sort.map { |t| t.titlecase }
      end

      def free_boosts
        free = "4 open"
      end

      def collapse_open_boosts(msg)
      # Roll any "open" entries up into a single "N open" count, e.g. ["open", "open"] => "2 open".
        open_count = msg.count { |item| item == "open" }
        named = msg.reject { |item| item == "open" }
        named << "#{open_count} open" if open_count > 0
        named.join(", ")
      end

      def ancestry_boosts
        list = @ancestry_info["abl_boosts"] ? @ancestry_info["abl_boosts"] : "?"

        return list if !list.is_a?(Array)

        msg = list.map { |item| item.is_a?(Array) ? item.join(" and ") : item }
        collapse_open_boosts(msg)
      end

      def bg_boosts
        list = @background_info["abl_boosts"] ? @background_info["abl_boosts"] : []

        return "None." if list.empty?

        msg = list.map { |item| item.is_a?(Array) ? item.join(" or ") : item }
        collapse_open_boosts(msg)
      end

      def key_ability

        key_ability = @subclass_info['key_abil'] ?
          @subclass_info['key_abil'] :
          @charclass_info['key_abil']

        return "Not set." if !key_ability

        if key_ability.is_a?(Array)
          key_ability.flatten.join(" or ")
        else
          key_ability
        end

      end

      def con_mod
        con_mod = "CON Mod"
      end

      def int_mod
        int_mod = "Int MOD"
      end

      def specials
        ainfo = @ancestry_info["special"] ? @ancestry_info["special"] : []
        hinfo = @heritage_info["special"] ? @heritage_info["special"] : []
        binfo = @background_info["special"] ? @background_info["special"] : []
        specials = ainfo + hinfo + binfo.flatten

        if specials.include?("Low-Light Vision") && @heritage_info["change_vision"]
          specials = specials - [ "Low-Light Vision" ] + [ "Darkvision" ]
        end
        specials.empty? ? "No special abilities or senses." : specials.sort.join(", ")
      end

      def starting_language_groups
      # Ancestry is the usual source, but a heritage, background, class, or specialty can grant one too.
        [
          [ 'Ancestry Languages',   config_list(@ancestry_info, 'languages') ],
          [ 'Heritage Languages',   config_list(@heritage_info, 'languages') ],
          [ 'Background Languages', config_list(@background_info, 'languages') ],
          [ 'Class Languages',      config_list(@class_features_info, 'languages') ],
          [ 'Specialty Languages',  config_list(@subclass_features_info, 'languages') +
                                    config_list(@subclassopt_features_info, 'languages') ]
        ]
      end

      def languages
        display = grouped_source_display(starting_language_groups)

        # A character with no granted language still speaks the common tongue.
        return "Kamin" if !display

        notes = []
        notes << t('pf2e.cg_duplicate_languages_note_later') if duplicate_grants?(starting_language_groups)
        notes << t('pf2e.cg_bonus_languages_note_later', :count => bonus_languages) if bonus_languages.positive?

        display + notes.map { |note| "%r%b%b#{note}" }.join
      end

      def language_sources
        [ @ancestry_info, @heritage_info, @background_info,
          @class_features_info, @subclass_features_info, @subclassopt_features_info ]
      end

      def bonus_languages
      # Humans know a language outright, on top of the ones their Intelligence earns them.
        language_sources.sum { |source| source.is_a?(Hash) ? source['bonus_languages'].to_i : 0 }
      end

      def grouped_source_display(groups)
      # Rows hang under their heading, indented, one source per line. Nil when nothing was granted.
        rows = groups.map { |label, list| [ label, list.uniq ] }
                     .reject { |_label, items| items.empty? }

        return nil if rows.empty?

        rows.map { |label, items| "%r%b%b#{item_color}#{label}%xn: #{items.join(", ")}" }.join
      end

      def deity_skills
      # Clerics and champions train their deity's skill.
        return [] if (!use_deity || @faith_info['deity'].blank?)

        Array(Global.read_config('pf2e_deities', deity, 'divine_skill'))
      end

      def draconic_skills
        return [] if @charclass != 'Sorcerer' || @subclass != 'Draconic' || @subclass_option.blank?

        exemplar = Global.read_config('pf2e_subclass', 'Dragon Exemplar', @subclass_option) || {}

        config_list(exemplar['chargen'], 'skills')
      end

      def config_list(source, key)
        return [] if !source.is_a?(Hash)

        Array(source[key]).difference([ "open" ])
      end

      def starting_skill_groups
        [
          [ 'Background Skills', config_list(@background_info, 'skills') ],
          [ 'Heritage Skills',   config_list(@heritage_info, 'skills') ],
          [ 'Class Skills',      config_list(@class_features_info, 'skills') ],
          [ 'Specialty Skills',  config_list(@subclass_features_info, 'skills') +
                                 config_list(@subclassopt_features_info, 'skills') +
                                 draconic_skills ],
          [ 'Deity Skill',       deity_skills ]
        ]
      end

      def starting_skills
        display = grouped_source_display(starting_skill_groups)

        return t('pf2e.cg_none_granted') if !display
        return display if !duplicate_grants?(starting_skill_groups)

        "#{display}%r%b%b#{t('pf2e.cg_duplicate_skills_note')}"
      end

      def duplicate_grants?(groups)
        granted = groups.flat_map { |_label, list| list }

        granted.uniq.size != granted.size
      end

      # A background or class skill list longer than this is spammy, so it points at the wiki instead.
      MANY_SKILL_OPTIONS = 5

      def skill_choice_display(options)
      # The options for a skill choice, which is made later, once base info is committed.
        options = Array(options).compact

        return nil if options.empty?
        return t('pf2e.cg_skill_choice_many') if options.size > MANY_SKILL_OPTIONS

        options.sort.join(" or ")
      end

      def bg_skill_choice
        skill_choice_display(@background_info.is_a?(Hash) ? @background_info['skill choice'] : nil)
      end

      def class_skill_choice
        skill_choice_display(@class_features_info.is_a?(Hash) ? @class_features_info['skill choice'] : nil)
      end

      def all_grants
        sources = [ @background_info, @heritage_info, @class_features_info,
                    @subclass_features_info, @subclassopt_features_info ]

        granted = sources.select { |source| source.is_a?(Hash) }
                         .flat_map { |source| Array(source['skills']) }

        granted + draconic_skills + deity_skills
      end

      def open_skills
      # A class's open slots plus any skill granted more than once, which trades the duplicate in.
        all_grants.size - all_grants.difference([ "open" ]).uniq.size
      end

      def free_skills
        count = has_charclass ? open_skills.to_s : "your class's number of open skills"

        "#{count} + your INT modifier"
      end

      def errors
      # Memoized because the template asks for this three times and each pass re-reads config.
        return @errors if defined?(@errors)

        @errors = Pf2e.chargen_messages(@ancestry, @heritage, @background, @charclass, @subclass, @char.pf2_faith, @subclass_option, @to_assign)
      end

      def has_messages
        !!errors
      end

      def show_message_section
        has_messages || base_info_set
      end

      def commit_prompt
        t('pf2e.cg_stage_commit_prompt', :checkpoint => 'info')
      end

    end
  end
end
