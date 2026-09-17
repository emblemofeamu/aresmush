module AresMUSH
  module Pf2e
    module Advancement

      # Where a spell pick lands in the pool.
      #
      # Three shapes, and which applies is data rather than logic. A spellbook may be one flat list
      # or one list per rank. A repertoire and a signature list are always per rank. And a character
      # casting from more than one source has all of them keyed by source first.
      #
      # This is the half that only needs the pool, so it is pure: the shell asks it where the pick
      # goes, then asks Pf2emagic::SpellPick whether the spell may go there.
      module SpellSlots

        # A resolution: whose list, the entries in it, and the rank they live under. `list_key` is
        # nil for a flat list, where the rank is not part of the path.
        def self.resolve(state, type:, rank:, magic_class:, charclass:)
          pool = (state['to_assign'] || {})[type.to_s]

          return no_option(type, charclass) unless pool

          keyed = pool.is_a?(Hash) && pool.keys.any? { |key| !Pf2e.level_key?(key) }
          class_key = keyed ? source_for(pool, magic_class, charclass) : nil

          return Err.new(:not_an_option, 'pf2e.adv_not_an_option') if keyed && class_key.nil?

          entries = keyed ? pool[class_key] : pool
          list = entries.is_a?(Hash) ? entries[rank] : entries

          # A level may give slots that are tied to no rank: the pool is keyed `any`, and a pick at
          # any rank spends one. So a rank with no list of its own is not a refusal while one of
          # those is open.
          if list.nil?
            pool_key = any_rank_key(entries)

            return Err.new(:no_slots_at_rank, 'pf2e.adv_no_spell_slots_level',
                           'type' => type, 'level' => rank) unless pool_key

            return Ok.new(:state => {
              'class_key' => class_key,
              'entries' => entries,
              'list' => entries[pool_key],
              'list_key' => pool_key,
              'from_pool' => true
            })
          end

          Ok.new(:state => {
            'class_key' => class_key,
            'entries' => entries,
            'list' => list,
            'list_key' => entries.is_a?(Hash) ? rank : nil,
            'from_pool' => false
          })
        end

        # Which source's list. The one the player named, or their own class, or the only one there
        # is - a character with two casting sources and no `class/` prefix has to say which.
        def self.source_for(pool, magic_class, charclass)
          return pool.keys.find { |key| key.to_s.casecmp?(magic_class.to_s) } if magic_class

          own = pool.keys.find { |key| key.to_s.casecmp?(charclass.to_s) }

          own || (pool.keys.size == 1 ? pool.keys.first : nil)
        end

        # Naming your own class where the pool is keyed by list type is a common enough mistake to
        # answer specifically.
        def self.no_option(type, charclass)
          return Err.new(:wrong_type, 'pf2e.adv_spell_wrong_type', 'class' => charclass) if type.to_s.casecmp?(charclass.to_s)

          Err.new(:not_an_option, 'pf2e.adv_not_an_option')
        end

        # The any-rank slot some classes get: it pays for a pick at a specific rank, and the spell
        # lands under the rank it actually is. Nil when the pool has no such slot open.
        def self.any_rank_key(entries)
          return nil unless entries.is_a?(Hash)

          key = entries.keys.find { |k| Pf2emagic.any_rank?(k) }

          key && Array(entries[key]).include?('open') ? key : nil
        end
      end
    end
  end
end
