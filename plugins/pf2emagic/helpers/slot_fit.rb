module AresMUSH
  module Pf2emagic

    # Can this set of spells be placed in the slots available at one rank?
    #
    # PF2e slots are pools, and a pool can be restricted: a Wizard's curriculum slot only takes a
    # spell from the school's list, a Cleric's divine font slot only heal or harm, a Sorcerer's
    # bloodline slot only the bloodline spell. Prepared casting is therefore an assignment - which
    # spell goes in which slot - and not a subtraction of counts.
    #
    # Treating it as a subtraction is what the old check did, and it could not express two
    # restricted pools at one rank: it enforced the first and logged that it was ignoring the
    # rest, so the second pool silently accepted anything. Greedy assignment does not fix that
    # either, because the pool a spell *can* use is not always the pool it *should* use.
    #
    # Pure: pools and spell names in, a boolean out. No character, no config, no database.
    module SlotFit

      # A slot that takes anything.
      ANY = nil

      # Capacities are per-rank slot counts, so single digits. Expanding them into individual
      # slots keeps the matching simple; the cap is only there so a corrupt stat block cannot
      # turn a sheet read into a hang.
      MAX_SLOTS = 64

      # The pools a caster has at one rank: their open slots, plus one pool per restriction.
      #
      # `restrictions` is { name => { 'count' => n, 'eligible' => [ spells ] } }, which is what
      # the restriction's own rules produce - a curriculum's school list, a font's heal/harm.
      def self.from_slots(open_count, restrictions)
        pools = []
        pools << { 'capacity' => open_count.to_i, 'eligible' => ANY } if open_count.to_i.positive?

        (restrictions || {}).each_value do |restriction|
          next unless restriction.is_a?(Hash)
          count = restriction['count'].to_i
          next unless count.positive?

          pools << { 'capacity' => count, 'eligible' => Array(restriction['eligible']) }
        end

        pools
      end

      def self.fits?(pools, spells)
        spells = Array(spells)
        return true if spells.empty?

        slots = expand(pools)
        return false if spells.size > slots.size

        # Kuhn's algorithm: try to give every spell a slot, backing a spell out of a slot when
        # that frees a placement for another. Matching rather than greed is the whole point - see
        # the "back out of a placement" spec.
        taken = {}

        spells.all? { |spell| place(spell.to_s.downcase, slots, taken, {}) }
      end

      # One entry per individual slot, each holding the set of spells it accepts (nil = any).
      def self.expand(pools)
        (pools || []).each_with_object([]) do |pool, slots|
          next unless pool.is_a?(Hash)

          eligible = pool['eligible']
          eligible = eligible.map { |s| s.to_s.downcase } if eligible

          [ pool['capacity'].to_i, MAX_SLOTS - slots.size ].min.times { slots << eligible }
        end
      end

      def self.place(spell, slots, taken, seen)
        slots.each_with_index do |eligible, index|
          next if seen[index]
          next unless eligible.nil? || eligible.include?(spell)

          seen[index] = true
          occupant = taken[index]

          if occupant.nil? || place(occupant, slots, taken, seen)
            taken[index] = spell
            return true
          end
        end

        false
      end
    end
  end
end
