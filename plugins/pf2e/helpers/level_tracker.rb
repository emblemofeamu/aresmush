module AresMUSH
  module Pf2e

    # XP charged per advancement. Kept here because rollback has to refund it.
    ADVANCEMENT_XP_COST = 1000

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

    # ------------------------------------------------------------------------------------
    # Rollback
    # ------------------------------------------------------------------------------------

    def self.can_rollback_to?(char, level)
      target = level.to_i

      # Rolling back under an open advancement would fold the ledger over choices the player
      # is still making, so the draft has to be finished or abandoned first.
      return t('pf2e.rollback_while_advancing') if char.advancing

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

      # Every level from the target upwards is coming back, so the refund is all of their
      # costs, not one level's worth. The ledger has already returned the xp itself by
      # reverting the xp_spend grants; this is the line the player reads in xp/history.
      refunded = (char.pf2_level - (level.to_i - 1)) * Pf2e::ADVANCEMENT_XP_COST

      marker = Ledger.rollback_to_level!(char, level, enactor)

      char.update(:pf2_rollback_marker => marker)

      Pf2e.record_xp_history(char, enactor ? enactor.name : 'System', refunded, t('pf2e.rollback_xp_reason', :level => level.to_i))

      Global.logger.info "PF2e ledger rollback: char=#{char.name} to_level=#{level} marker=#{marker} by=#{enactor&.name}"

      nil
    end

    # Undoes the last rollback. The grants were only marked, never deleted, so this is a
    # matter of clearing the marker off them and refolding.
    def self.redo_rollback(char, enactor = nil)
      marker = char.pf2_rollback_marker

      return t('pf2e.rollback_nothing_to_redo') if marker.blank?

      was = char.pf2_level

      return t('pf2e.rollback_nothing_to_redo') if Ledger.redo_rollback!(char, marker).zero?

      char.update(:pf2_rollback_marker => nil)

      # The fold has taken the xp back out again; record the other half of the refund line
      # so xp/history reads as a pair rather than an unexplained gain.
      spent = (char.pf2_level - was) * Pf2e::ADVANCEMENT_XP_COST

      Pf2e.record_xp_history(char, enactor ? enactor.name : 'System', -spent, t('pf2e.rollback_redo_xp_reason', :level => char.pf2_level))

      Global.logger.info "PF2e ledger rollback redone: char=#{char.name} marker=#{marker} by=#{enactor&.name}"

      nil
    end

  end
end
