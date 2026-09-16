module AresMUSH
  module Pf2e

    # XP charged per advancement. Kept here because rollback has to refund it.
    ADVANCEMENT_XP_COST = 1000

    SNAPSHOT_ATTRIBUTES = %w(
      pf2_base_info
      pf2_level
      pf2_archetypeinfo
      pf2_features
      pf2_traits
      pf2_feats
      pf2_faith
      pf2_special
      pf2_boosts_working
      pf2_boosts
      pf2_to_assign
      pf2_lang
      pf2_movement
      pf2_reagents
      pf2_alloc_reagents
      pf2_formula_book
      pf2_size
      pf2_roll_aliases
      pf2_actions
      pf2_known_for
      pf2_baseinfo_locked
      pf2_abilities_locked
      pf2_skills_locked
      pf2_checkpoint
    )

    def self.level_tracker_key(level)
      level.to_i.to_s
    end

    # ------------------------------------------------------------------------------------
    # Reading and writing level entries
    # ------------------------------------------------------------------------------------

    def self.level_entry(char, level)
      tracker = char.pf2_level_tracker || {}

      tracker[level_tracker_key(level)] || {}
    end

    # Merges data into a level's entry. Mutates and saves the character.
    def self.record_level(char, level, data)
      return unless data.is_a?(Hash)

      key = level_tracker_key(level)
      tracker = char.pf2_level_tracker || {}
      entry = tracker[key] || {}

      tracker[key] = entry.merge(data)

      char.update(pf2_level_tracker: tracker)
    end

    # Records a resolved feat choice against the level it was made at. Mutates and saves.
    def self.record_choice(char, choice_name, label, level = nil)
      key = level_tracker_key(level || char.pf2_level)

      tracker = char.pf2_level_tracker || {}
      entry = tracker[key] || {}
      choices = entry['feat_choices'] || {}

      existing = Array(choices[choice_name])
      existing << label.to_s
      choices[choice_name] = existing.uniq

      entry['feat_choices'] = choices
      tracker[key] = entry

      char.update(pf2_level_tracker: tracker)
    end

    # Every recorded choice as [ choice_name, label, level ], newest level first.
    def self.recorded_choices(char)
      tracker = char.pf2_level_tracker || {}

      tracker.keys.sort_by { |k| -k.to_i }.flat_map do |key|
        entry = tracker[key]
        next [] unless entry.is_a?(Hash)

        choices = entry['feat_choices']
        next [] unless choices.is_a?(Hash)

        choices.flat_map do |choice_name, labels|
          Array(labels).map { |label| [ choice_name, label, key.to_i ] }
        end
      end
    end

    # The most recent label recorded for a choice, or nil. Callers should use this rather
    # than walking the tracker themselves.
    def self.choice_for(char, choice_name)
      found = recorded_choices(char).find { |name, _label, _level| name.to_s.casecmp?(choice_name.to_s) }

      found && found[1]
    end

    # Every label ever picked for a choice, across all levels. Used to stop a repeatable feat
    # from choosing the same thing twice.
    #
    # Chargen writes to the tracker immediately, but advancement stages into to_assign until
    # advance/done, so both have to be consulted or a choice made earlier in the same
    # advancement would still show as available.
    def self.choice_labels_for(char, choice_name)
      labels = recorded_choices(char)
        .select { |name, _label, _level| name.to_s.casecmp?(choice_name.to_s) }
        .map { |_name, label, _level| label }

      in_flight = (char.pf2_to_assign || {})['feat_choices']

      if in_flight.is_a?(Hash)
        key = in_flight.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
        labels.concat(Array(in_flight[key])) if key
      end

      labels.uniq
    end

    def self.deferred_choice_grants(char, level, in_flight = {})
      pending = recorded_choices(char).map { |name, label, _lvl| [ name, label ] }

      if in_flight.is_a?(Hash)
        (in_flight['feat_choices'] || {}).each_pair do |name, labels|
          Array(labels).each { |label| pending << [ name, label ] }
        end
      end

      pending.uniq.filter_map do |choice_name, label|
        block = find_choice_block(char, choice_name)
        next unless block

        grants = choice_at_level(block, label, level)
        next unless grants

        [ choice_name, label, grants ]
      end
    end

    def self.find_level_snapshot(char, level)
      char.level_snapshots.find(level: level.to_i).first
    end

    # Deletes every snapshot the character has, or only those at or above from_level.
    def self.delete_level_snapshots(char, from_level = nil)
      # to_a first, so records are not deleted out from under the index being walked.
      char.level_snapshots.to_a.each do |snap|
        snap.delete if from_level.nil? || snap.level >= from_level.to_i
      end
    end

    # A section the character has no object for (no magic, say) is stored as an empty hash,
    # which restore reads as absent.
    def self.capture_level_snapshot(char, level)
      character_data = SNAPSHOT_ATTRIBUTES.each_with_object({}) do |attr, hash|
        hash[attr] = char.send(attr)
      end

      abilities = char.abilities.each_with_object({}) do |abil, hash|
        hash[abil.name] = { 'base_val' => abil.base_val, 'mod_val' => abil.mod_val }
      end

      # Untrained skills are omitted.
      skills = char.skills.each_with_object({}) do |skill, hash|
        next if skill.prof_level.to_s == 'untrained'

        hash[skill.name] = { 'prof_level' => skill.prof_level, 'cg_skill' => skill.cg_skill }
      end

      hp = {}
      combat = {}
      magic = {}

      if char.hp
        hp = {
          'ancestry_hp' => char.hp.ancestry_hp,
          'charclass_hp' => char.hp.charclass_hp
        }
      end

      if char.combat
        combat = {
          'saves' => char.combat.saves,
          'perception' => char.combat.perception,
          'class_dc' => char.combat.class_dc,
          'archetype_class_dcs' => char.combat.archetype_class_dcs,
          'key_abil' => char.combat.key_abil,
          'armor_prof' => char.combat.armor_prof,
          'weapon_prof' => char.combat.weapon_prof,
          'weapon_group_prof' => char.combat.weapon_group_prof,
          'unarmed_attacks' => char.combat.unarmed_attacks,
          'defense' => char.combat.defense
        }
      end

      if char.magic
        magic = {
          'focus_cantrips' => char.magic.focus_cantrips,
          'focus_spells' => char.magic.focus_spells,
          'focus_pool' => char.magic.focus_pool,
          'innate_spells' => char.magic.innate_spells,
          'signature_spells' => char.magic.signature_spells,
          'repertoire' => char.magic.repertoire,
          'spell_abil' => char.magic.spell_abil,
          'spellbook' => char.magic.spellbook,
          'adapted_spells' => char.magic.adapted_spells,
          'spells_per_day' => char.magic.spells_per_day,
          'restricted_slots' => char.magic.restricted_slots,
          'restricted_spellbook' => char.magic.restricted_spellbook,
          'prepared_lists' => char.magic.prepared_lists,
          'tradition' => char.magic.tradition,
          'divine_font' => char.magic.divine_font,
          'revelation_locked' => char.magic.revelation_locked
        }
      end

      existing = find_level_snapshot(char, level)
      existing.delete if existing

      Pf2eLevelSnapshot.create(
        character: char,
        level: level.to_i,
        character_data: character_data,
        abilities: abilities,
        skills: skills,
        hp: hp,
        combat: combat,
        magic: magic
      )
    end

    def self.has_level_snapshot?(char, level)
      !!find_level_snapshot(char, level)
    end

    # Overwrites the character's sheet with a stored snapshot.
    def self.restore_level_snapshot(char, level)
      snapshot = find_level_snapshot(char, level)

      return "No snapshot stored for level #{level}." unless snapshot

      (snapshot.character_data || {}).each_pair do |attr, value|
        next unless SNAPSHOT_ATTRIBUTES.include?(attr)

        char.send("#{attr}=", value)
      end

      char.save

      abilities = char.abilities.to_a

      (snapshot.abilities || {}).each_pair do |name, values|
        abil = abilities.find { |a| a.name.to_s.casecmp?(name.to_s) }
        next unless abil

        abil.update(base_val: values['base_val'], mod_val: values['mod_val'])
      end

      restore_skills(char, snapshot.skills || {})

      stored_hp = snapshot.hp || {}
      stored_combat = snapshot.combat || {}
      stored_magic = snapshot.magic || {}

      if !stored_hp.empty? && char.hp
        char.hp.update(ancestry_hp: stored_hp['ancestry_hp'], charclass_hp: stored_hp['charclass_hp'])
      end

      if !stored_combat.empty?
        combat = Pf2eCombat.get_create_combat_obj(char)
        combat.update(stored_combat.transform_keys(&:to_sym))
      end

      if !stored_magic.empty?
        magic = PF2Magic.get_create_magic_obj(char)
        magic.update(stored_magic.transform_keys(&:to_sym))
      elsif char.magic
        # They had no magic at the target level but do now, so clear it back out.
        PF2Magic.factory_default(char)
      end

      nil
    end

    def self.restore_skills(char, stored)
      char.skills.each do |skill|
        key = stored.keys.find { |name| name.to_s.casecmp?(skill.name.to_s) }
        entry = key && stored[key]

        if entry
          skill.update(prof_level: entry['prof_level'], cg_skill: entry['cg_skill'])
        else
          skill.update(prof_level: 'untrained', cg_skill: false)
        end
      end

      existing = char.skills.map { |s| s.name.to_s.upcase }

      stored.each_pair do |name, entry|
        next if existing.include?(name.to_s.upcase)

        Pf2eSkills.create_skill_for_char(name, char)
        Pf2eSkills.update_skill_for_char(name, char, entry['prof_level'], entry['cg_skill'])
      end
    end

    # ------------------------------------------------------------------------------------
    # Rollback
    # ------------------------------------------------------------------------------------

    def self.can_rollback_to?(char, level)
      target = level.to_i

      return t('pf2e.rollback_below_floor', :floor => 2) if target < 2
      return t('pf2e.rollback_not_that_high', :level => char.pf2_level) if target > char.pf2_level
      return t('pf2e.rollback_nothing', :level => target) if Ledger.rollback_targets(Ledger.rows(char), target).empty?

      nil
    end

    # The lowest level this character has a record for.
    def self.earliest_tracked_level(char)
      tracker = char.pf2_level_tracker || {}
      return char.pf2_level if tracker.empty?

      tracker.keys.map { |k| k.to_i }.min
    end

    # Puts the character back to just before the given level so they can redo it.
    #
    # The ledger does the work: the level-up transactions at or above the target are marked
    # reverted and the sheet is refolded. Nothing is deleted, so the rollback is itself
    # undoable, and a boon that merely takes effect at that level is left standing - it
    # goes dormant while the character is below it and returns when they level again.
    def self.rollback_to_level(char, level, enactor = nil)
      failure = can_rollback_to?(char, level)
      return failure if failure

      Ledger.seed_from_sheet!(char)
      marker = Ledger.rollback_to_level!(char, level, enactor)

      Pf2e.record_xp_history(char, enactor ? enactor.name : 'System', Pf2e::ADVANCEMENT_XP_COST, t('pf2e.rollback_xp_reason', :level => level.to_i))

      Global.logger.info "PF2e ledger rollback: char=#{char.name} to_level=#{level} marker=#{marker} by=#{enactor&.name}"

      nil
    end

    # The pre-ledger implementation, kept until the snapshot models are retired.
    def self.legacy_rollback_to_level(char, level, enactor = nil)
      target = level.to_i
      previous = target - 1

      failure = can_rollback_to?(char, target)
      return failure if failure

      levels_undone = char.pf2_level - previous
      refund = levels_undone * ADVANCEMENT_XP_COST

      error = restore_level_snapshot(char, previous)
      return error if error

      tracker = char.pf2_level_tracker || {}
      tracker.delete_if { |key, _entry| key.to_i >= target }

      delete_level_snapshots(char, target)

      char.pf2_level_tracker = tracker
      char.pf2_level = previous
      char.pf2_xp = char.pf2_xp + refund
      char.pf2_advancement = {}
      char.advancing = false

      char.save

      awarded_by = enactor ? enactor.name : 'System'
      Pf2e.record_xp_history(char, awarded_by, refund, t('pf2e.rollback_xp_reason', :level => target))

      nil
    end

  end
end
