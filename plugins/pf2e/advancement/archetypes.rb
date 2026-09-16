module AresMUSH
  module Pf2e
    module Advancement

      # The numbered archetype slots on pf2_archetypeinfo.
      #
      # A character may hold up to four archetypes, and each one has a matching specialty slot
      # and specialty-choice slot at the same index. Taking a dedication fills the lowest free
      # slot in a family; giving it back clears the highest filled one, which is the one this
      # advancement most recently used.
      module Archetypes

        SLOTS = 4

        def self.keys_for(family)
          (1..SLOTS).map { |i| "#{family}#{i}" }
        end

        # Which numbered slot an archetype sits in, 1-based, or nil when it holds none.
        def self.index_of(archetypes, archetype)
          found = keys_for('archetype').index { |key| archetypes[key].to_s == archetype.to_s }

          found && found + 1
        end

        # Records a value in the slot of another family that sits beside a given archetype -
        # its specialty, or its specialty choice. Returns a new hash; an archetype holding no
        # slot at all leaves it unchanged, which is how a specialty picked for an archetype the
        # sheet has not recorded is quietly skipped rather than written to slot 1.
        def self.set_alongside(archetypes, family, archetype, value)
          index = index_of(archetypes, archetype)

          index ? archetypes.merge("#{family}#{index}" => value) : archetypes
        end

        # Clears the highest-numbered slot in this family holding `value`. Returns a new hash;
        # if nothing holds it, the hash comes back unchanged.
        def self.clear(archetypes, family, value)
          return archetypes if value.blank?

          key = keys_for(family).reverse.find { |k| archetypes[k].to_s == value.to_s }

          key ? archetypes.merge(key => "") : archetypes
        end

        # Clears the specialty choice that sits alongside a given archetype.
        def self.clear_choice_for(archetypes, archetype)
          set_alongside(archetypes, 'archetype_specialty_choice', archetype, "")
        end

        # The archetype each Dedication feat in the draft belongs to.
        def self.dedications(state, feats)
          Array(feats).filter_map do |name|
            details = feat_details(state, name)

            next unless details
            next unless Array(details['feat_type']).any? { |t| t.to_s.casecmp?('Dedication') }

            Array(details['assoc_archetype']).first
          end.compact
        end

        # Undoes every archetype this advancement added, leaving anything held earlier alone.
        # A dedication taken this level fills a slot; abandoning the level gives it back,
        # along with the specialty and specialty choice that came with it.
        def self.undo_advancement(state)
          draft = state['advancement']['feats']
          picked = draft.is_a?(Hash) ? draft.values.flatten : []

          taken = dedications(state, picked)

          return state['archetypes'] || {} if taken.empty?

          # Choices first. The choice slot is keyed by which archetype sits at that index, so
          # it has to be found while that archetype is still in its slot - the old code
          # cleared the archetype first and then looked it up, which could never match for an
          # archetype taken this level.
          archetypes = Array((state['to_assign']['archetype specialty choice'] || {}).keys)
            .reduce(state['archetypes'] || {}) { |acc, archetype| clear_choice_for(acc, archetype) }

          archetypes = clear(archetypes, 'archetype_specialty', state['to_assign']['archetype_specialty'])

          taken.reduce(archetypes) { |acc, name| clear(acc, 'archetype', name) }
        end

        def self.feat_details(state, name)
          feats = state['config'].read('pf2e_feats') || {}
          key = feats.keys.find { |f| f.to_s.casecmp?(name.to_s) }

          key && feats[key]
        end
      end
    end
  end
end
