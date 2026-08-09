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
      # finished once nothing is outstanding. Must not call anything that calls stage.
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
      # Options are locked by this point, so a blank one is one the character doesn't have rather than
      # one they still need to pick.
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

        "#{assigned} plus #{still_free} free"
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

      def existing_skills
        char_skills = @char.skills

        list = []

        char_skills.each do |skill|
          list << skill.name if skill.prof_level == 'trained'
        end

        list.sort.join(", ")
      end

      def open_skills
        @to_assign['open skills'].count("open")
      end

      def open_languages
        Pf2eSkills.open_language_count(@char)
      end

      # Feat slots the character still has to fill, keyed by the to_assign entry that tracks them.
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

      # Which help topics and commit keyword belong to each stage. The feats stage has no commit
      # of its own; 'commit featskills' shows up there only when a feat has reopened skills.
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
      # A finished sheet has no stage left to explain; it says its piece in the Messages section.
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
      # With nothing outstanding, the commit prompt alone says everything an all-clear line would.
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
      # The catch-all line abilities_messages emits, replaced here by the per-category messages above.
        # Mirrors the loop in Pf2eAbilities.abilities_messages so the reconstructed line matches exactly.
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

        # Divine fonts and open innate spells are reported alongside the list messages below, not
        # instead of them, so nothing is hidden by an earlier warning.
        msgs = Pf2emagic.cg_magic_warnings(@magic, @to_assign) || []

        # The per-level counts live in the Magic section; these just say which list still needs filling.
        msgs << t('pf2emagic.cg_rep_spells') if !open_spells_by_level('repertoire').empty?
        msgs << t('pf2emagic.cg_spellbook_spells') if !open_spells_by_level('spellbook').empty?

        msgs
      end

      def open_spells_by_level(list)
      # Levels with nothing left to choose are dropped, so a fully assigned repertoire reports nothing.
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
      # Shown whether or not it was a choice: a deity with a single font assigns it silently, and the
      # character has no other way to find out which one they got.
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
      # Innate spells come from feats rather than a spell list, so they're listed here in full. An
      # unchosen one is the only prompt the character gets outside the Messages section.
        spells = (@magic && @magic.innate_spells) || {}

        return nil if spells.empty?

        lines = spells.map do |name, info|
          label = name.to_s.casecmp?('open') ? t('pf2emagic.cg_innate_unchosen') : name
          tradition = Array(info['tradition']).first.to_s

          "%b%b#{item_color}#{innate_level_label(info['level'])}%xn: #{label} (#{Pf2e.pretty_string(tradition)})"
        end

        ([ "#{item_color}Innate Spells%xn:" ] + lines).join("%r")
      end

      def innate_level_label(level)
        return "Cantrip" if level.to_s.downcase == 'cantrip' || level.to_i.zero?

        "#{Pf2emagic.ordinal_level(level)}-rank"
      end

      def spells_to_choose
      # Indented breakdown shown under the Magic section, e.g. "  Cantrip(s): 4".
        blocks = [
          spell_choice_block('repertoire', t('pf2emagic.cg_rep_to_choose')),
          spell_choice_block('spellbook', t('pf2emagic.cg_spellbook_to_choose'))
        ].compact

        if blocks.empty?
          # Say so explicitly rather than leaving the section bare, but only for characters who have a
          # list to fill in the first place. Innate- or focus-only casters have nothing to report here.
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

      def magic_notes
        notes = [ t('pf2emagic.cg_magic_note') ]

        notes << t('pf2emagic.cg_repertoire_note') if has_repertoire
        notes << t('pf2emagic.cg_spellbook_note') if has_spellbook

        notes.join("%r")
      end

    end
  end
end
