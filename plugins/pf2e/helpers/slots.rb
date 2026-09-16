module AresMUSH
  module Pf2e

    # The pool of things a character still has to pick, and the handful of operations anything
    # ever does to it.
    #
    # `pf2_to_assign` is that pool. Every path that touched it spelled its operation out inline:
    # `Array(to_assign[key]) + ['open']` in one place to open a slot, an index-of-'open'
    # replacement in another to fill one, a bespoke four-way search for which restricted marker
    # a lore may spend in a third. That is why "what does taking this feat open up?" had no
    # answer you could read, let alone test - the answer was scattered across the call sites.
    #
    # A **slot delta** is one of those operations as data. A transformation returns the deltas
    # it implies and `apply` folds them into the pool, in order, so a slot opened by one delta
    # can be filled by a later one. Both halves are pure: same pool and deltas in, same pool
    # out, and the pool handed in is never modified.
    #
    # Filling and opening are deliberately the same kind of thing. A feat that grants two
    # languages and a feat that is itself a language pick differ only in which deltas they
    # carry, which is what lets a feat describe its own effect on the pool instead of the
    # command knowing about it.
    module Slots

      OPEN = 'open'.freeze

      # op => how it changes one slot. Each returns the new value for that slot, or an Err.
      #
      #   open     add pickable markers
      #   fill     spend a marker on a value
      #   release  hand a filled slot back, turning it into a marker again
      #   set      a scalar slot, decided outright - an archetype, a deity
      #   add      values that were never pickable, just recorded
      OPS = {
        'open' => lambda { |held, delta|
          Array(held) + Array.new([ delta[:count].to_i, 1 ].max, delta[:token] || OPEN)
        },

        'fill' => lambda { |held, delta|
          slots = Array(held).dup
          wanted = Array(delta[:tokens] || [ OPEN ])

          # The caller lists which markers this pick may spend, most specific first, so the
          # rule about what a lore or an untrained-only slot accepts stays with the pick.
          index = wanted.lazy
            .map { |token| slots.index { |s| s.to_s.casecmp?(token.to_s) } }
            .find { |i| !i.nil? }

          next Err.new(:no_free, 'pf2e.no_free', 'element' => Slots.label(delta[:path])) if index.nil?

          slots[index] = delta[:value]
          slots
        },

        'release' => lambda { |held, delta|
          slots = Array(held).dup
          index = slots.index { |s| s.to_s.casecmp?(delta[:value].to_s) }

          next Err.new(:not_in_list, 'pf2e.not_in_list', 'option' => delta[:value]) if index.nil?

          slots[index] = delta[:token] || OPEN
          slots
        },

        # A marker spent on something recorded elsewhere - a spellbook's any-rank pool pays for
        # a spell that lands under its actual rank, so the pool loses a marker and gains nothing.
        'consume' => lambda { |held, delta|
          slots = Array(held).dup
          wanted = Array(delta[:tokens] || [ OPEN ])

          index = wanted.lazy
            .map { |token| slots.index { |s| s.to_s.casecmp?(token.to_s) } }
            .find { |i| !i.nil? }

          next Err.new(:no_free, 'pf2e.no_free', 'element' => Slots.label(delta[:path])) if index.nil?

          slots.delete_at(index)
          slots
        },

        'set' => lambda { |_held, delta| delta[:value] },

        'add' => lambda { |held, delta| (Array(held) + Array(delta[:value])).uniq }
      }.freeze

      # ------------------------------------------------------------------------------
      # Building deltas
      # ------------------------------------------------------------------------------

      def self.open(path, count: 1, token: nil)
        { :op => 'open', :path => path, :count => count, :token => token }
      end

      def self.fill(path, value, tokens: nil)
        { :op => 'fill', :path => path, :value => value, :tokens => tokens }
      end

      def self.release(path, value, token: nil)
        { :op => 'release', :path => path, :value => value, :token => token }
      end

      def self.consume(path, tokens: nil)
        { :op => 'consume', :path => path, :tokens => tokens }
      end

      def self.set(path, value)
        { :op => 'set', :path => path, :value => value }
      end

      def self.add(path, value)
        { :op => 'add', :path => path, :value => value }
      end

      # ------------------------------------------------------------------------------
      # Applying them
      # ------------------------------------------------------------------------------

      # Folds the deltas into the pool, in order. Returns the new pool, or the Err of the first
      # delta that could not be applied - the pool is left alone in that case, so a half-applied
      # sequence never reaches a character.
      def self.apply(pool, deltas)
        Array(deltas).reduce(deep_copy(pool || {})) do |acc, delta|
          return acc if acc.is_a?(Err)

          op = OPS[delta[:op].to_s]

          return Err.new(:unknown_slot_op, 'pf2e.unknown_slot_op', 'op' => delta[:op].to_s) unless op

          path = Array(delta[:path])
          updated = op.call(read(acc, path), delta)

          updated.is_a?(Err) ? updated : write(acc, path, updated)
        end
      end

      # What a list of deltas opens up, as slot label => how many. The question the scattered
      # version could not answer.
      def self.openings(deltas)
        Array(deltas).each_with_object({}) do |delta, counts|
          next unless delta[:op].to_s == 'open'

          label = self.label(delta[:path])
          counts[label] = counts.fetch(label, 0) + [ delta[:count].to_i, 1 ].max
        end
      end

      def self.label(path)
        Array(path).join("/")
      end

      # ------------------------------------------------------------------------------
      # Reading and writing a nested slot
      # ------------------------------------------------------------------------------

      def self.read(pool, path)
        path.reduce(pool) { |node, key| node.is_a?(Hash) ? node[key] : nil }
      end

      def self.write(pool, path, value)
        *parents, leaf = path

        target = parents.reduce(pool) do |node, key|
          node[key] = {} unless node[key].is_a?(Hash)
          node[key]
        end

        target[leaf] = value
        pool
      end

      # One level deeper than dup, so applying a delta to a nested slot cannot reach back into
      # the caller's pool.
      def self.deep_copy(pool)
        pool.each_with_object({}) do |(key, value), copy|
          copy[key] = case value
                      when Hash then deep_copy(value)
                      when Array then value.dup
                      else value
                      end
        end
      end
    end
  end
end
