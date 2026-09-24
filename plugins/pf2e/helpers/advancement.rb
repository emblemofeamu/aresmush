module AresMUSH
  module Pf2e

    def self.can_advance(char)
      # Are they already advancing?
      return t('pf2e.already_advancing') if char.advancing

      # Do they have enough XP?
      xp = char.pf2_xp
      return t('pf2e.not_enough_xp') unless (xp >= 1000)

      # Are they in an active encounter?
      active_encounter = PF2Encounter.in_active_encounter? char
      return t('pf2e.already_in_encounter') if active_encounter

      # Can they level?
      level = char.pf2_level
      return t('pf2e.already_max_level') if (level == Global.read_config('pf2e', 'max_level'))

      return nil
    end

    def self.level_key?(key)
      key_str = key.to_s.downcase

      key_str == 'cantrip' || key_str == Pf2emagic::ANY_RANK || key_str.match?(/\A-?\d+\z/)
    end

    def self.wrap_magic_assign(to_assign, key, base_class_key)
      existing = to_assign[key]
      return if existing.nil?
      return if existing.is_a?(Hash) && existing.keys.any? { |k| k.to_s.casecmp?(base_class_key) }

      if existing.is_a?(Hash)
        if existing.keys.all? { |k| level_key?(k) }
          to_assign[key] = { base_class_key => existing }
        end
      else
        to_assign[key] = { base_class_key => existing }
      end
    end

    def self.wrap_adv_magic_stats(advancement, base_class_key)
      existing = advancement['magic_stats']
      return if existing.nil?
      return if existing.is_a?(Hash) && existing.keys.any? { |k| k.to_s.casecmp?(base_class_key) }

      if existing.is_a?(Hash)
        stat_keys = %w(
          spell_abil
          tradition
          spells_per_day
          repertoire
          spellbook
          signature
          signature_spells
          signature_spell
          focus_pool
          focus_spell
          focus_cantrip
          innate_spell
          addrepertoire
          addspellbook
          divine_font
        )

        if existing.keys.any? { |k| stat_keys.include?(k.to_s) }
          advancement['magic_stats'] = { base_class_key => existing }
        end
      end
    end

    def self.stage_feat_magic_stats(char, feat_name, feat_details, to_assign, advancement)
      return [] if !feat_details.is_a?(Hash)

      magic_stats = feat_details['magic_stats']

      return [] if !magic_stats.is_a?(Hash) || magic_stats.empty?
      return [] if !AresMUSH.const_defined?("Pf2emagic")

      magic_stats = resolve_caster_type_stats(char, magic_stats)

      return [] if magic_stats.empty?

      base_class_key = char.pf2_base_info['charclass']
      assessed = PF2Magic.assess_magic_stats(char, magic_stats)

      advancement['magic_stats'] ||= {}
      wrap_adv_magic_stats(advancement, base_class_key)

      stats = assessed['magic_stats'] || {}
      feat_stats, class_stats = split_feat_magic(stats, FEAT_KEYED_MAGIC_STATS)

      advancement['magic_stats'][feat_name] = feat_stats unless feat_stats.empty?

      unless class_stats.empty?
        advancement['magic_stats'][base_class_key] =
          merge_magic_stats(advancement['magic_stats'][base_class_key], class_stats)
      end

      magic_options = assessed['magic_options'] || {}

      magic_options.each_pair do |option, slots|
        wrap_magic_assign(to_assign, option, base_class_key)
        to_assign[option] ||= {}

        if FEAT_KEYED_MAGIC_OPTIONS.include?(option.to_s)
          to_assign[option][feat_name] = slots
        else
          to_assign[option][base_class_key] =
            merge_spell_slots(to_assign[option][base_class_key], slots)
        end
      end

      magic_options.keys.sort
    end

    FEAT_KEYED_MAGIC_STATS = %w(innate_spell)
    FEAT_KEYED_MAGIC_OPTIONS = %w(innate)

    def self.split_feat_magic(stats, feat_keys)
      feat_stats = stats.select { |key, _value| feat_keys.include?(key.to_s) }
      class_stats = stats.reject { |key, _value| feat_keys.include?(key.to_s) }

      [ feat_stats, class_stats ]
    end

    def self.merge_magic_stats(existing, added)
      return added unless existing.is_a?(Hash)
      return existing unless added.is_a?(Hash)

      added.each_with_object(existing.dup) do |(key, value), merged|
        current = merged[key]

        merged[key] = if current.is_a?(Hash) && value.is_a?(Hash)
          current.merge(value)
        elsif current.is_a?(Array) && value.is_a?(Array)
          current + value
        else
          value
        end
      end
    end

    def self.merge_spell_slots(existing, added)
      return added if existing.nil?
      return existing if added.nil?

      if existing.is_a?(Hash) && added.is_a?(Hash)
        added.each_with_object(existing.dup) do |(level, slots), merged|
          merged[level] = Array(merged[level]) + Array(slots)
        end
      elsif existing.is_a?(Array) && added.is_a?(Array)
        existing + added
      else
        added
      end
    end

    def self.magic_option_messages(options)
      innate, rest = Array(options).map(&:to_s).uniq.partition { |option| option.casecmp?('innate') }

      msg = []
      msg << t('pf2e.adv_item_magic', :options => rest.sort.join(" and ")) unless rest.empty?
      msg << t('pf2e.adv_item_innate_spells') unless innate.empty?

      msg
    end

    def self.archetype_key?(key)
      archetypes = Global.read_config('pf2e_archetype')&.keys || []
      archetypes.any? { |arch| arch.to_s.casecmp?(key.to_s) }
    end


    def self.open_skill_token?(value)
      token = value.to_s.strip.downcase
      token == 'open' || token == 'open lore' || token == 'open untrained' || token == 'open lore untrained'
    end

    def self.untrained_only_token?(value)
      token = value.to_s.strip.downcase
      token == 'open untrained' || token == 'open lore untrained'
    end

    def self.pending_skill_names(to_assign, advancement)
      entries = []
      entries += Array(to_assign['raise skill'])
      entries += Array(advancement['raise skill'])

      entries = entries.compact.map { |entry| entry.to_s.strip }.reject(&:empty?)
      entries.reject! { |entry| open_skill_token?(entry) }
      entries.map(&:downcase)
    end

    def self.merge_raise_skill_entries(existing, additions)
      list = if existing.is_a?(Array)
        existing.dup
      elsif existing.nil?
        []
      else
        [existing]
      end

      list += Array(additions)
      list = list.compact.map { |entry| entry.to_s.strip }.reject(&:empty?)

      seen = {}
      result = []
      list.each do |entry|
        if open_skill_token?(entry)
          result << entry
          next
        end

        key = entry.to_s.downcase
        next if seen[key]

        seen[key] = true
        result << entry
      end

      result
    end

    # Which of the four skill markers a restriction asks for. A slot can be limited to a Lore,
    # to something the character is untrained in, or both - and Advancement::Raises reads the
    # same vocabulary to decide what may spend it.
    SKILL_SLOT_TOKENS = {
      [ false, false ] => 'open',
      [ false, true ] => 'open untrained',
      [ true, false ] => 'open lore',
      [ true, true ] => 'open lore untrained'
    }.freeze

    def self.add_open_skill_slot(to_assign, advancement, lore=false, untrained_only=false)
      token = SKILL_SLOT_TOKENS[[ !!lore, !!untrained_only ]]
      delta = [ Slots.open('raise skill', :token => token) ]

      # A scalar left over from an older shape is folded into the list by Slots.open.
      to_assign.replace(Slots.apply(to_assign, delta))
      advancement.replace(Slots.apply(advancement, delta))
    end

    # Trains each of `skills`, or hands back an open slot where it cannot.
    #
    # Three outcomes, counted separately because they are three different things to say:
    # `assigned` trained outright, `free_count` for a grant that was a player's choice all along
    # (the literal `open`/`choice` tokens the shipped feats use, such as Natural Skill's two), and
    # `open_count`/`open_lore_count` for a named skill the character already has or is about to
    # get, which PF2e turns into a free pick rather than wasting.
    def self.add_training_skills(char, skills, to_assign, advancement)
      cleaned = Array(skills).map { |s| s.to_s.strip }.reject(&:empty?)
      return { assigned: [], free_count: 0, open_count: 0, open_lore_count: 0 } if cleaned.empty?

      pending = pending_skill_names(to_assign, advancement)
      assigned = []
      free_count = 0
      open_count = 0
      open_lore_count = 0

      cleaned.each do |skill|
        # Not a skill name at all: the feat grants a skill of the player's choice. Counted before
        # the checks below, which would otherwise read it as a skill literally called "open" and
        # call the second one a duplicate of the first.
        if OPEN_SKILL_VALUES.include?(skill.to_s.downcase)
          free_count += 1
          next
        end

        normalized = skill.to_s.downcase
        already_trained = Pf2eSkills.get_skill_prof(char, skill).to_s.downcase != 'untrained'
        already_pending = pending.include?(normalized)

        if already_trained || already_pending
          if lore_skill?(skill)
            open_lore_count += 1
          else
            open_count += 1
          end
          next
        end

        assigned << skill
        pending << normalized
      end

      if assigned.any?
        to_assign['raise skill'] = merge_raise_skill_entries(to_assign['raise skill'], assigned)
        advancement['raise skill'] = merge_raise_skill_entries(advancement['raise skill'], assigned)
      end

      # A free pick was never restricted to anything, so it opens an unrestricted slot.
      free_count.times { add_open_skill_slot(to_assign, advancement, false, false) }
      open_count.times { add_open_skill_slot(to_assign, advancement, false, true) }
      open_lore_count.times { add_open_skill_slot(to_assign, advancement, true, true) }

      { assigned: assigned, free_count: free_count, open_count: open_count, open_lore_count: open_lore_count }
    end

    # What advancing to the next level offers, as the messages telling the player what to pick.
    #
    # The level block's own keys are Advancement::Opens, a row each. What is left here is the three
    # things that come from the character rather than from the table: the choices a feat or feature
    # carries, and the level clauses an earlier pick deferred to this level.
    def self.assess_advancement(char, info)
      advfail = Pf2e.can_advance(char)
      return advfail if advfail

      to_assign, advancement, pairs = Advancement::Opens.all(char, info)

      # A nil key means the row rendered its own sentence, which some of them must: the magic
      # options are assembled from the caster's own stat block rather than named by a locale key.
      return_msg = pairs.map { |(key, args)| key.nil? ? args.to_s : t(key, **(args || {})) }

      # Feat choices this level opens.
      granted_choice_names(info).each do |name|
        open_feat_choice(to_assign, name)

        block = find_choice_block(char, name)
        summary = block ? choice_summary(block) : 'eligible option'

        return_msg << t('pf2e.adv_item_feat_choice', :choice => name, :summary => with_article(summary))
      end

      # Fold in anything an earlier feat choice deferred to this level, such as Canny Acumen.
      new_level = char.pf2_level + 1

      deferred_choice_grants(char, new_level).each do |choice_name, label, grants|
        next unless grants.is_a?(Hash)

        advancement['grants'] ||= {}
        advancement['grants']["#{choice_name} (#{label})"] = grants

        return_msg << t('pf2e.adv_deferred_choice', :choice => "#{choice_name} (#{label})", :level => new_level)
      end

      # Level clauses on feats they already hold, such as Weapon Proficiency going to expert at 11.
      deferred_feat_grants(char, new_level).each do |feat, lvl, grants|
        next unless grants.is_a?(Hash)

        advancement['grants'] ||= {}
        advancement['grants']["#{feat} (level #{lvl})"] = grants

        return_msg << t('pf2e.adv_deferred_feat', :feat => feat, :level => lvl)
      end

      char.update(pf2_to_assign: to_assign)
      char.update(pf2_advancement: advancement)
      char.update(advancing: true)

      return_msg
    end

    def self.do_advancement(char, client)
      # Make sure they don't have anything left to choose.
      messages = advancement_messages(char)
      return messages.join("%r") if messages

      to_process = char.pf2_advancement

      # What each draft key writes to the sheet is Advancement::Apply, a row per key. The writes are
      # collected and saved once at the end rather than one attribute at a time.
      Advancement::Apply.all(char, to_process,
                             :charclass => char.pf2_base_info['charclass'],
                             :client => client).each do |(key, args, kind)|
        rendered = t(key, **(args || {}))

        case kind
        when :failure then client.emit_failure rendered
        when :ooc then client.emit_ooc rendered
        else client.emit rendered
        end
      end

      # The level this advancement completes.
      new_level = char.pf2_level + 1

      # Record what was chosen against the level it was chosen at.
      to_assign = char.pf2_to_assign

      entry = { 'advancement' => to_process }
      entry['archetype'] = to_assign['archetype'] if to_assign['archetype']
      entry['archetype_specialty'] = to_assign['archetype_specialty'] if to_assign['archetype_specialty']
      entry['archetype_specialty_choice'] = to_assign['archetype specialty choice'] if to_assign['archetype specialty choice']

      if to_assign['feat_choices'].is_a?(Hash) && !to_assign['feat_choices'].empty?
        entry['feat_choices'] = to_assign['feat_choices']
      end

      tracker = char.pf2_level_tracker || {}
      tracker[new_level.to_s] = (tracker[new_level.to_s] || {}).merge(entry)
      char.pf2_level_tracker = tracker

      # Update level.
      char.pf2_level = new_level

      # Out of advancement mode, but the draft stays for one more step: the commit below diffs
      # against it, and a feat handed over while applying this level's grants lands there.
      char.advancing = false

      char.save

      # The single commit point for a level-up: everything this advancement produced becomes
      # one level_up transaction attributed to the level just gained, XP spend included.
      Pf2e::Ledger.commit_level_up!(char, new_level)

      # History now, so the draft goes.
      char.update(:pf2_to_assign => {})
      char.update(:pf2_advancement => {})

      return nil
    end

    # What the review screen says is still outstanding, and the gate advance/done checks.
    #
    # Which picks are open is Advancement::Outstanding's table; this renders what it returns. One
    # message needs the character to describe itself - the summary of what a feat's choice may be
    # drawn from - so that lookup happens here rather than in the pure table.
    def self.advancement_messages(char)
      # Only the draft and the config, not a folded sheet: this runs on every review screen and at
      # every advance/done, and Outstanding reads nothing else.
      state = CharState.build({ 'to_assign' => char.pf2_to_assign, 'advancement' => char.pf2_advancement })

      msg = Advancement::Outstanding.messages(state).map do |(key, args)|
        args = args.merge('summary' => choice_pending_summary(char, args['choice'])) if args.key?('choice')

        t(key, **args.reject { |k, _v| k == 'choice' }.transform_keys(&:to_sym))
      end

      return nil if msg.empty?

      msg
    end

    # What a feat's open choice is drawn from, in words: "a skill", "a lore". Falls back to a
    # neutral phrase for a choice whose block cannot be found, so the player is still told they
    # owe a pick.
    def self.choice_pending_summary(char, name)
      block = find_choice_block(char, name)

      with_article(block ? choice_summary(block) : 'eligible option')
    end

    def self.merge_combat_stats(existing_stats, added_stats)
      existing = existing_stats || {}
      added = added_stats || {}

      merged = {}

      (existing.keys | added.keys).each do |key|
        existing_value = existing[key]
        added_value = added[key]

        merged[key] =
          if existing_value.is_a?(Hash) && added_value.is_a?(Hash)
            merge_combat_stats(existing_value, added_value)
          elsif prof_rank(existing_value) || prof_rank(added_value)
            higher_prof(existing_value, added_value)
          elsif added_value.nil?
            existing_value
          else
            added_value
          end
      end

      merged
    end

    def self.prof_rank(value)
      return nil if value.nil?

      {
        'untrained' => 0,
        'trained' => 1,
        'expert' => 2,
        'master' => 3,
        'legendary' => 4
      }[value.to_s.downcase]
    end

    def self.higher_prof(left, right)
      left_rank = prof_rank(left)
      right_rank = prof_rank(right)

      return right if left_rank.nil?
      return left if right_rank.nil?

      left_rank >= right_rank ? left.to_s.downcase : right.to_s.downcase
    end

    # Kept for callers outside the advance/option path. The rule itself lives in
    # Advancement::Options, so the gate and the apply side cannot drift apart again.
    def self.valid_class_option?(char, feature, option)
      saves = (char.combat && char.combat.saves) || {}

      Advancement::Options.allowed?({ 'saves' => saves }, feature, option)
    end

  end
end
