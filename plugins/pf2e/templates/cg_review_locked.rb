module AresMUSH
  module Pf2e

    class PF2CGReviewLockDisplay < ErbTemplateRenderer
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

        subclass_choose = @subclass_info['choose']
        subclass_options = subclass_choose.is_a?(Hash) ? subclass_choose['options'] : nil
        @subclass_option_info = (subclass_options.is_a?(Hash) && !@subclass_option.blank?) ?
                                subclass_options[@subclass_option] : nil
        @subclassopt_features_info = @subclass_option_info.is_a?(Hash) ? @subclass_option_info['chargen'] : nil

        @to_assign = @char.pf2_to_assign
        @boosts = @char.pf2_boosts_working

        @magic = magic_plugin? ? @char.magic : nil

        super File.dirname(__FILE__) + "/cg_review_locked.erb"
      end

      def baseinfolock
        @baseinfolock
      end

      def stage
        case @char.pf2_checkpoint
        when 'info'      then 'attributes'
        when 'abilities' then 'skills'
        when 'skills'    then feats_stage_done? ? 'final' : 'feats'
        else 'final'
        end
      end

      def feats_stage_done?
      # Feats are the last thing to assign and have no commit of their own, so the sheet is
      # finished once nothing is outstanding.
        @char.pf2_skills_locked && feat_messages.empty? && magic_messages.empty?
      end

      def skills_reopened?
      # A feat that grants a skill the character already trained hands back a free skill and
      # unlocks skills so it can be assigned. 'commit featskills' locks them again.
        stage == 'feats' && !@char.pf2_skills_locked
      end

      def show_boosts
        stage == 'attributes' || stage == 'final'
      end

      def show_attributes
        stage == 'skills' || stage == 'final'
      end

      def show_skills
        stage == 'skills' || stage == 'final' || skills_reopened?
      end

      def show_languages
        stage == 'skills' || stage == 'final'
      end

      def show_feats
        stage == 'feats' || stage == 'final'
      end

      def show_magic
        has_magic && (stage == 'feats' || stage == 'final')
      end

      def show_other
        stage == 'final'
      end

      def magic_plugin?
        AresMUSH.const_defined?("Pf2emagic")
      end

      def has_magic
        return false if !@magic

        return true if @to_assign['repertoire'] || @to_assign['spellbook'] || @to_assign['divine font']
        return true if !@magic.innate_spells.empty?
        return true if !@magic.focus_spells.empty? || !@magic.focus_cantrips.empty?
        return true if !@magic.spells_per_day.empty?
        return true if !(@magic.tradition.keys - [ 'innate' ]).empty?

        false
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def name
        @char.name
      end

      def show(value)
        value.blank? ? "-" : value
      end

      def ancestry
        @ancestry
      end

      def heritage
        @heritage
      end

      def background
        @background
      end

      def charclass
        @charclass
      end

      def subclass
        @subclass
      end

      def subclass_option
        @subclass_option
      end

      def deity
        @faith_info['deity']
      end

      def use_deity
        @charclass_info['use_deity']
      end

      def is_devotee
        use_deity ? " %xh%xy(REQ)%xn" : ""
      end

      def alignment
        @faith_info['alignment']
      end

      def sanctification
        if Pf2e.uses_sanctification?(@charclass)
          @faith_info['sanctification']
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
          t('pf2e.char_has_code',
            :edicts=>edicts.join("%r"),
            :anathema=>anathema.join("%r")
          )
        end
      end

      def ahp
        ancestry_hp = @heritage_info['ancestry_HP'] ?
                      @heritage_info['ancestry_HP'] :
                      @ancestry_info["HP"]

        ancestry_hp ? ancestry_hp : 0
      end

      def chp
        @charclass_info["HP"] ? @charclass_info["HP"] : 0
      end

      def size
        @ancestry_info["Size"] ? @ancestry_info["Size"] : "M"
      end

      def speed
        @ancestry_info["Speed"] ? @ancestry_info["Speed"] : "?"
      end

      def traits
        a_traits = @ancestry_info["traits"] ? @ancestry_info["traits"] : []
        h_traits = @heritage_info["traits"] ? @heritage_info["traits"] : []

        (a_traits + h_traits).uniq.difference([ "" ]).sort.map { |t| t.titlecase }
      end

      def free_boosts
        open_list = @boosts['free']
        still_free = open_list.count("open")
        assigned = open_list.difference([ "open" ]).empty? ?
                   "None assigned" :
                   open_list.difference([ "open" ]).sort.join(", ")

        "#{assigned}, #{still_free} open"
      end

      def collapse_open_boosts(msg)
      # Roll any still-unassigned "open" entries up into a single "N open" count, e.g. ["open", "open"] => "2 open".
        return msg if !msg.is_a?(Array)
        open_count = msg.count { |item| item == "open" }
        named = msg.reject { |item| item == "open" }
        named << "#{open_count} open" if open_count > 0
        named.join(", ")
      end

      def ancestry_boosts
        collapse_open_boosts(@boosts['ancestry'].sort)
      end

      def bg_boosts
        list = @boosts['background']
        if list.is_a?(Array)
          list = list.map { |v| v.is_a?(Array) ? v.join(" or ") : v }
        end
        collapse_open_boosts(list)
      end

      def key_ability
        list = @boosts['charclass']

        if list.is_a?(Array)
          list.sort.join(" or ")
        else
          list
        end
      end

      def con_mod
        Pf2eAbilities.abilmod(Pf2eAbilities.get_score(@char, "Constitution"))
      end

      def attribute_scores
        abilities = %w{Strength Dexterity Constitution Intelligence Wisdom Charisma}

        rows = abilities.map do |a|
          score = Pf2eAbilities.get_score(@char, a)
          mod = Pf2eAbilities.abilmod(score)
          sign = mod < 0 ? "" : "+"

          left("#{item_color}#{a.slice(0,3).upcase}%xn: #{score} (#{sign}#{mod})", 26)
        end

        rows.each_slice(3).map { |row| row.join }.join("%r")
      end

      def int_mod
        Pf2eAbilities.abilmod(Pf2eAbilities.get_score(@char, "Intelligence"))
      end

      def specials
        @char.pf2_special.join(", ")
      end

      def languages
        @char.pf2_lang.uniq.sort.join(", ")
      end

      def chosen_languages
        Array(@to_assign['open languages']).reject { |lang| lang == 'open' }.uniq
      end

      def starting_languages
        granted = @char.pf2_lang.uniq - chosen_languages

        groups = [
          [ 'Ancestry Languages',   config_list(@ancestry_info, 'languages') ],
          [ 'Heritage Languages',   config_list(@heritage_info, 'languages') ],
          [ 'Background Languages', config_list(@background_info, 'languages') ],
          [ 'Class Languages',      config_list(@class_features_info, 'languages') ],
          [ 'Specialty Languages',  config_list(@subclass_features_info, 'languages') +
                                    config_list(@subclassopt_features_info, 'languages') ]
        ]

        display = grouped_display(attribute_sources(groups, granted, 'Other Languages'), t('pf2e.cg_none_granted'))

        notes = []
        notes << t('pf2e.cg_duplicate_languages_note') if duplicate_grants?(groups)
        notes << t('pf2e.cg_bonus_languages_note', :count => bonus_languages) if bonus_languages.positive?

        display + notes.map { |note| "%r%b%b#{note}" }.join
      end

      def language_sources
        [ @ancestry_info, @heritage_info, @background_info,
          @class_features_info, @subclass_features_info, @subclassopt_features_info ]
      end

      def bonus_languages
      # For humans, who get a language bonus beyond high Int.
        language_sources.sum { |source| source.is_a?(Hash) ? source['bonus_languages'].to_i : 0 }
      end

      def chosen_languages_display
        chosen_languages.empty? ? t('pf2e.cg_none_so_far') : chosen_languages.sort.join(", ")
      end

      def existing_skills
        char_skills = @char.skills

        list = []

        char_skills.each do |skill|
          list << skill.name if skill.prof_level == 'trained'
        end

        list.sort.join(", ")
      end

      def trained_skills(cg_granted)
        @char.skills
             .select { |skill| skill.prof_level == 'trained' && !!skill.cg_skill == cg_granted }
             .map { |skill| skill.name }
             .sort
      end

      def starting_skills
        granted = trained_skills(true)

        groups = [
          [ 'Background Skills', config_list(@background_info, 'skills') ],
          [ 'Heritage Skills',   config_list(@heritage_info, 'skills') ],
          [ 'Class Skills',      config_list(@class_features_info, 'skills') ],
          [ 'Specialty Skills',  config_list(@subclass_features_info, 'skills') +
                                 config_list(@subclassopt_features_info, 'skills') +
                                 draconic_skills ],
          [ 'Deity Skill',       deity_granted_skills ]
        ]

        display = grouped_display(attribute_sources(groups, granted, 'Other Skills'), t('pf2e.cg_none_granted'))

        return display if !duplicate_grants?(groups)

        "#{display}%r%b%b#{t('pf2e.cg_duplicate_skills_note')}"
      end

      def duplicate_grants?(groups)
        granted = groups.flat_map { |_label, list| list }

        granted.uniq.size != granted.size
      end

      def deity_granted_skills
      # Clerics and champions train their deity's skill.
        return [] if !use_deity || deity.blank?

        Array(Global.read_config('pf2e_deities', deity, 'divine_skill'))
      end

      def draconic_skills
        return [] if @charclass != 'Sorcerer' || @subclass != 'Draconic' || @subclass_option.blank?

        exemplar = Global.read_config('pf2e_subclass', 'Dragon Exemplar', @subclass_option) || {}

        config_list(exemplar['chargen'], 'skills')
      end

      def chosen_skills
      # Everything trained since base info locked, split by the choice that trained it.
        chosen = trained_skills(false)

        groups = [
          [ 'Background Skill Choice', Array(selected_skill_choice('bg skill choice')) ],
          [ 'Class Skill Choice',      Array(selected_skill_choice('class skill choice')) ],
          [ 'Free Skills',             Array(@to_assign['open skills']).reject { |s| s == 'open' } ]
        ]

        grouped_display(attribute_sources(groups, chosen, 'Feat Skills'), t('pf2e.cg_none_so_far'))
      end

      def selected_skill_choice(key)
        choice = @to_assign[key]
        return nil if !choice.is_a?(Hash)

        selected = choice['selected']
        selected.blank? || selected == 'open' ? nil : selected
      end

      def config_list(source, key)
        return [] if !source.is_a?(Hash)

        Array(source[key]).difference([ "open" ])
      end

      def attribute_sources(groups, held, leftover_label)
        claimed = []

        rows = groups.map do |label, list|
          items = list.uniq.select { |item| held.include?(item) }
          claimed += items

          [ label, items ]
        end

        leftover = held - claimed
        rows << [ leftover_label, leftover ] if !leftover.empty?

        rows.reject { |_label, items| items.empty? }
      end

      def grouped_display(rows, empty_msg)
      # Rows hang under their heading, indented, one source per line.
        return empty_msg if rows.empty?

        rows.map { |label, items| "%r%b%b#{item_color}#{label}%xn: #{items.join(", ")}" }.join
      end

      def open_skills
        count = @to_assign['open skills'].count("open")

        count.zero? ? t('pf2e.cg_no_free_skills') : count
      end

      # A background or class skill list longer than this is spammy, so it points at the wiki instead.
      MANY_SKILL_OPTIONS = 5

      def bg_skill_choice
        skill_choice_options('bg skill choice')
      end

      def class_skill_choice
        skill_choice_options('class skill choice')
      end

      def skill_choice_options(key)
      # Only a choice still to be made shows up here; once chosen, the skill is in Current Skills.
        choice = @to_assign[key]
        return nil if !choice.is_a?(Hash) || choice['selected'] != 'open'

        options = Array(choice['options']).compact
        return nil if options.empty?
        return t('pf2e.cg_skill_choice_many') if options.size > MANY_SKILL_OPTIONS

        options.sort.join(" or ")
      end

      def open_languages
        count = Pf2eSkills.open_language_count(@char)

        count.zero? ? t('pf2e.cg_no_free_languages') : count
      end

      FEAT_SLOTS = {
        'ancestry feat'  => 'ancestry',
        'charclass feat' => 'class',
        'general feat'   => 'general',
        'skill feat'     => 'skill'
      }

      def feats
        assigned = @char.pf2_feats.values.flatten.sort
        (assigned + open_feat_slots).join(", ")
      end

      def open_feat_slots
        FEAT_SLOTS.map do |key, label|
          count = open_count(@to_assign[key])
          next if count.zero?

          "#{count} #{label} feat#{count == 1 ? "" : "s"} open"
        end.compact
      end

      def open_count(value)
      # Feat slots are stored either as a bare 'open' string or as a list of slots.
        return 0 if !value
        return value.count("open") if value.is_a?(Array)

        value.to_s == 'open' ? 1 : 0
      end

      STAGE_INFO = {
        'attributes' => { :help => [ 'cg_attributes' ],           :commit => 'abilities' },
        'skills'     => { :help => [ 'cg_skills', 'cg_languages' ], :commit => 'skills' },
        'feats'      => { :help => [ 'cg_feats' ],                :commit => nil },
        'final'      => { :help => [ 'cg' ],                      :commit => nil }
      }

      def commit_keyword
        return 'featskills' if skills_reopened?

        STAGE_INFO[stage][:commit]
      end

      def show_lock_msg
        stage != 'final'
      end

      def lock_msg
        msg = case stage
              when 'attributes' then t('pf2e.cg_stage_attributes')
              when 'skills'     then t('pf2e.cg_stage_skills')
              else                   has_magic ? t('pf2e.cg_stage_feats_magic') : t('pf2e.cg_stage_feats')
              end

        "#{msg}%r#{t('pf2e.cg_stage_help', :topics => help_topics)}"
      end

      def help_topics
        topics = STAGE_INFO[stage][:help].dup
        topics << 'cg_magic' if stage == 'feats' && has_magic

        quoted = topics.map { |topic| "'%xchelp #{topic}%xn'" }

        return quoted.first if quoted.size == 1
        return quoted.join(" and ") if quoted.size == 2

        "#{quoted[0..-2].join(", ")}, and #{quoted[-1]}"
      end

      def ready_to_commit
      # Nothing left to fix for this stage, so point them at the command that moves them on.
        stage_messages.empty? && commit_keyword
      end

      def commit_prompt
        return t('pf2e.cg_stage_relock_prompt') if commit_keyword == 'featskills'

        t('pf2e.cg_stage_commit_prompt', :checkpoint => commit_keyword)
      end

      def errors
        stage_messages.join("%r")
      end

      def has_messages
        !stage_messages.empty?
      end

      def show_message_section
        has_messages || ready_to_commit || sheet_complete
      end

      def sheet_complete
        stage == 'final' && !has_messages
      end

      def complete_msg
        [ t('pf2e.cg_stage_final'), t('pf2e.cg_sheet_view') ].join("%r")
      end

      def stage_messages
        case stage
        when 'attributes' then boost_messages
        when 'skills'     then skill_messages + language_messages
        # skill_messages is normally empty here, and isn't when a feat has reopened skills.
        when 'feats'      then skill_messages + feat_messages + magic_messages
        else                   boost_messages + skill_messages + language_messages + feat_messages + magic_messages
        end
      end

      BOOST_ORDER = %w{ancestry background charclass free}

      def boost_messages
        msgs = []

        BOOST_ORDER.each do |category|
          values = @boosts[category]
          next if !values.is_a?(Array)

          unassigned = values.include?("open")
          choice_open = values.any? { |v| v.is_a?(Array) }

          next if !unassigned && !choice_open

          if category == 'charclass'
            msgs << t('pf2e.unassigned_key_attribute', :options => key_ability)
          else
            msgs << t('pf2e.unassigned_boosts_for', :category => category)
          end
        end

        # Anything abilities_messages catches that isn't a per-category boost gap, such as scores over 18.
        abil_msgs = Pf2eAbilities.abilities_messages(@char) || []
        msgs + abil_msgs.reject { |m| m == unassigned_abilities_msg }
      end

      def unassigned_abilities_msg
        a = []
        @boosts.each_pair do |k,v|
          a << k if v.include?("open") || v.any? { |x| x.is_a?(Array) }
        end

        return nil if a.empty?
        t('pf2e.unassigned_abilities', :missing => a.uniq.sort.join(", "))
      end

      def skill_messages
        Pf2eSkills.skills_messages(@char) || []
      end

      def language_messages
        Pf2eSkills.language_messages(@char) || []
      end

      def feat_messages
        Pf2e.feat_messages(@char) || []
      end

      def magic_messages
        return [] if !has_magic

        msgs = Pf2emagic.cg_magic_warnings(@magic, @to_assign) || []

        # The per-level counts live in the Magic section; these just say which list still needs filling.
        msgs << t('pf2emagic.cg_rep_spells') if !open_spells_by_level('repertoire').empty?
        msgs << t('pf2emagic.cg_spellbook_spells') if !open_spells_by_level('spellbook').empty?

        msgs
      end

      def open_spells_by_level(list)
        spells = @to_assign[list]

        return {} if !spells.is_a?(Hash)

        counts = {}

        spells.each_pair do |level, slots|
          next if !slots.is_a?(Array)

          open = slots.count("open")
          next if open.zero?

          label = spell_level_label(level)
          counts[label] = counts.fetch(label, 0) + open
        end

        counts
      end

      def spell_level_label(level)
        return "Cantrip(s)" if level.to_s.downcase == 'cantrip'

        "#{Pf2emagic.ordinal_level(level)}-rank"
      end

      def divine_font
        pending = @to_assign['divine font']

        if pending.is_a?(Array)
          options = pending.map { |f| Pf2e.pretty_string(f) }.join(" or ")
          return "#{item_color}Divine Font%xn: #{t('pf2emagic.cg_font_unchosen', :options => options)}"
        end

        font = @magic && @magic.divine_font
        return nil if font.blank?

        "#{item_color}Divine Font%xn: #{Pf2e.pretty_string(font)}"
      end

      def innate_spells
        spells = (@magic && @magic.innate_spells) || {}

        return nil if spells.empty?

        innate_blocks(spells.map { |name, info| [ name, info['tradition'], info['level'] ] })
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

      def spells_to_choose
        blocks = [
          spell_choice_block('repertoire', spell_list_label('Repertoire', 'pf2emagic.cg_rep_to_choose')),
          spell_choice_block('spellbook', spell_list_label('Spellbook', 'pf2emagic.cg_spellbook_to_choose'))
        ].compact

        if blocks.empty?
          return t('pf2emagic.cg_all_spells_assigned') if has_repertoire || has_spellbook
          return nil
        end

        blocks.join("%r")
      end

      def spell_choice_block(list, label)
        counts = open_spells_by_level(list)

        return nil if counts.empty?

        lines = counts.map { |level_label, count| "%b%b#{item_color}#{level_label}%xn: #{count}" }

        ([ "#{item_color}#{label}%xn:" ] + lines).join("%r")
      end

      def has_repertoire
        return true if @to_assign['repertoire']

        @magic && !@magic.repertoire.empty?
      end

      def has_spellbook
        return true if @to_assign['spellbook']

        @magic && !@magic.spellbook.empty?
      end

      def casting_tradition
        return nil if !@magic

        traditions = @magic.tradition || {}
        trad_info = traditions[@charclass]

        if !trad_info
          # An archetype can add a second casting class, but in chargen there is only ever the one.
          casting_classes = traditions.keys.reject { |key| key.to_s.strip == 'innate' }
          trad_info = traditions[casting_classes.first] if casting_classes.size == 1
        end

        return nil if !trad_info.is_a?(Array) || trad_info.first.blank?

        Pf2e.pretty_string(trad_info.first)
      end

      def spell_list_label(list, plain_key)
        return t(plain_key) if !casting_tradition

        t('pf2emagic.cg_spells_to_choose', :list => list, :tradition => casting_tradition)
      end

      def prepares_from_tradition?
      # Clerics and druids prepare from their tradition's whole spell list. Unlike a witch or a
      # wizard, they have no list to fill.
        return false if !@magic || @magic.spells_per_day.empty?

        !has_repertoire && !has_spellbook
      end

      def prepared_list_note
        return t('pf2emagic.cg_prepared_list_note_plain') if !casting_tradition

        t('pf2emagic.cg_prepared_list_note', :tradition => casting_tradition)
      end

      def open_innate_spells?
      # An unnamed innate spell is still waiting to be picked.
        return false if !@magic

        @magic.innate_spells.keys.any? { |name| name.to_s.casecmp?('open') }
      end

      def no_spells_to_select?
      # A champion or ranger has a tradition and no spells whatsoever; feats are where their magic
      # eventually comes from.
        return false if !casting_tradition
        return false if prepares_from_tradition? || has_repertoire || has_spellbook

        !open_innate_spells?
      end

      def magic_notes
      # A finished sheet has nothing left to explain, and the Messages section covers anything that
      # is still outstanding.
        return nil if stage == 'final'

        notes = [ t('pf2emagic.cg_magic_note') ]

        notes << t('pf2emagic.cg_repertoire_note') if has_repertoire
        notes << t('pf2emagic.cg_spellbook_note') if has_spellbook

        if prepares_from_tradition?
          notes << prepared_list_note
          notes << t('pf2emagic.cg_prepare_after_approval_note')
        end

        notes << t('pf2emagic.cg_no_spells_note') if no_spells_to_select?

        notes.join("%r")
      end

    end
  end
end
