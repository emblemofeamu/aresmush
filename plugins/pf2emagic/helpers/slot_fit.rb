module AresMUSH
  module Pf2emagic

    # Can this set of spells be placed in the slots available at one rank?
    #
    # PF2e slots are pools, and a pool can be restricted. A Wizard's curriculum slot takes only a
    # spell from the school's list; a Cleric's divine font slot takes only heal or harm. The
    # question is therefore which spell goes in which slot, and comparing counts does not answer
    # that once a rank has two restricted pools. Greedy assignment does not either, because the
    # pool a spell is allowed to use may be the one another spell needs.
    #
    # Pure: pools and spell names in, a boolean out. It reads nothing outside its arguments.
    module SlotFit

      # A slot that takes anything.
      ANY = nil

      # Capacities are per-rank slot counts, so single digits. Expanding them into individual slots
      # keeps the matching simple; the cap bounds the work a corrupt stat block can ask for.
      MAX_SLOTS = 64

      # The pools a caster has at one rank: their open slots, plus one pool per restriction.
      #
      # `restrictions` is { name => { 'count' => n, 'eligible' => [ spells ] } } - what a
      # restriction's own rules produce, such as a curriculum's school list or a font's heal/harm.
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

        # Kuhn's algorithm: give every spell a slot, backing a spell out of one when that frees a
        # placement for another.
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
