module AresMUSH
  module Pf2e

    # What a character has, counting an open draft.
    #
    # A rule that asks a question about a character mid-build has to see the picks made so far, and
    # those live in the advancement draft rather than on the sheet. This is the one place that knows
    # it, so a rule asks `DraftSheet.of(char).feat_names` and never asks whether a draft is open.
    #
    # The merge is unconditional. `pf2_advancement` is cleared at `advance/done` and at
    # `advance/reset`, so outside an open advancement there is nothing to merge and the answer is the
    # sheet's own. A caller that guards the merge is writing a branch that cannot change the result,
    # and a caller that forgets to guard it gets the right answer anyway.
    class DraftSheet

      def self.of(char)
        new(char)
      end

      def initialize(char)
        @char = char
      end

      def drafting?
        !!@char.advancing
      end

      # The level a prerequisite is measured against: the one being gained, while a level is open.
      def level
        drafting? ? @char.pf2_level.to_i + 1 : @char.pf2_level.to_i
      end

      # Feat names, upcased, because every caller compares them that way.
      def feat_names
        (held_feats + staged_feats).uniq
      end

      def skill_prof(name)
        held = Pf2eSkills.get_skill_prof(@char, name)
        raises = staged_raises_for(name)

        return held if raises.zero?

        progression = Global.read_config('pf2e', 'prof_progression') || []
        return held if progression.empty?

        index = progression.index(held) || 0

        progression[[ index + raises, progression.size - 1 ].min]
      end

      # rank => [ spells ], for a spontaneous caster's repertoire.
      def repertoire(class_key = nil)
        merge_spell_lists(@char.magic&.repertoire, 'repertoire', class_key)
      end

      # rank => [ spells ], for a prepared caster's spellbook. A pick staged at `any` rank is filed
      # by the spell's own rank, which is where a reader expects to find it.
      def spellbook(class_key = nil)
        merge_spell_lists(@char.magic&.spellbook, 'spellbook', class_key, :file_any => true)
      end

      # The highest spell rank this caster has slots at, counting slots this level grants.
      def max_spell_rank(charclass)
        committed = @char.magic && @char.magic.spells_per_day[charclass]
        ranks = Array(committed.is_a?(Hash) ? committed.keys : nil)

        staged_magic_stats.each do |stats|
          per_day = stats['spells_per_day']
          next unless per_day.is_a?(Hash)

          per_day = per_day[charclass] if per_day.keys.any? { |k| k.to_s.casecmp?(charclass.to_s) }
          ranks += Array(per_day.is_a?(Hash) ? per_day.keys : nil)
        end

        numbered = ranks.reject { |rank| rank.to_s.casecmp?('cantrip') }.map(&:to_i)

        numbered.empty? ? nil : numbered.max
      end

      # source => [ tradition, proficiency ], counting a tradition this level grants.
      def traditions
        merged = deep_copy(@char.magic&.tradition || {})

        staged_magic_stats_by_source.each_pair do |source, stats|
          next unless stats['tradition'].is_a?(Hash) && !stats['tradition'].empty?

          trad, prof = stats['tradition'].first
          merged[source] = [ trad, prof ]
        end

        merged
      end

      private

      def draft
        @char.pf2_advancement || {}
      end

      def held_feats
        (@char.pf2_feats || {}).values.flatten.map { |f| f.to_s.upcase }
      end

      def staged_feats
        (draft['feats'] || {}).values.flatten
                              .map { |f| f.to_s.upcase }
                              .reject { |f| f.empty? || f == 'OPEN' }
      end

      # Both kinds of skill increase a level can hand out, counted for one skill.
      def staged_raises_for(name)
        staged = Array(draft['raise skill']) + Array(draft['raise skill choice'])

        staged.reject { |s| s.to_s.strip.empty? || Pf2e.open_skill_token?(s) }
              .count { |s| s.to_s.casecmp?(name.to_s) }
      end

      # A staged spell list is keyed by rank, or by class and then by rank. Which one it is has to be
      # sniffed, because both shapes are written.
      def staged_spell_list(key, class_key)
        staged = draft[key]
        return {} if staged.nil?
        return staged if staged.is_a?(Array)
        return {} unless staged.is_a?(Hash)
        return staged if staged.keys.all? { |k| Pf2e.level_key?(k) }

        staged[class_key] || {}
      end

      def merge_spell_lists(committed, key, class_key, file_any: false)
        lists = deep_copy(committed || {})
        target = class_key || @char.pf2_base_info['charclass']
        staged = staged_spell_list(key, target)

        return lists if staged.nil? || staged == {} || staged == []

        for_class = lists[target] || {}

        each_staged_pick(staged) do |rank, spell|
          # No rank at all, or a pick staged at `any` rank, is filed by the spell's own rank, which
          # is where a reader looks for it.
          if rank.nil? || (file_any && Pf2emagic.any_rank?(rank))
            file_by_own_rank(for_class, spell)
          else
            for_class[rank] = (Array(for_class[rank]) + [ spell ]).uniq
          end
        end

        lists[target] = for_class
        lists
      end

      # Yields rank, spell for every filled pick, whichever shape the draft used. A flat list is
      # written for a spellbook that keeps no ranks, and yields a nil rank.
      def each_staged_pick(staged)
        if staged.is_a?(Array)
          staged.each { |spell| yield(nil, spell) unless unfilled?(spell) }
          return
        end

        staged.each_pair do |rank, spells|
          Array(spells).each { |spell| yield(rank, spell) unless unfilled?(spell) }
        end
      end

      def unfilled?(spell)
        spell.to_s.strip.empty? || spell.to_s.casecmp?('open')
      end

      def file_by_own_rank(for_class, spell)
        found = Pf2emagic.get_spell_details(spell)
        details = found && found[1]
        return unless details

        rank = details['base_level'].to_s

        for_class[rank] = (Array(for_class[rank]) + [ spell ]).uniq
      end

      def staged_magic_stats
        stats = draft['magic_stats']

        return [] unless stats.is_a?(Hash)
        return [ stats ] if stats.key?('spells_per_day')

        stats.values.select { |entry| entry.is_a?(Hash) }
      end

      def staged_magic_stats_by_source
        stats = draft['magic_stats']
        return {} unless stats.is_a?(Hash)

        stats.select { |_source, entry| entry.is_a?(Hash) }
      end

      def deep_copy(value)
        Marshal.load(Marshal.dump(value))
      end
    end
  end
end
