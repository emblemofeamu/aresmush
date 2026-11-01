module AresMUSH
  module Pf2e

    # Who is in an encounter, and how a command names them.
    #
    # The initiative order is a list of rows, one per combatant, highest initiative first:
    #
    #   { 'id' => 3, 'init' => 18.2, 'name' => 'Goblin Warrior #3', 'npc' => '41' }
    #   { 'id' => 1, 'init' => 15.0, 'name' => 'Aria', 'char' => '12', 'state' => '7' }
    #
    # A row names its holder by database id, so nothing has to guess from a name which of them it is: a
    # creature's `Pf2eNpc`, or a character's state in this encounter (`Pf2eCombatantState`) with the
    # character beside it. Its id is given when it joins and never reused, so `#3`
    # names the same goblin all fight long whatever the order does - which is what a player types to
    # target it, since three goblins share a name. A row with neither holder is a name the GM put in the
    # order and nothing more.
    module Combatants

      Combatant = Struct.new(:holder, :label, :number, :init) do
        def creature?
          Actors.of(holder).creature?
        end

        def ref
          number ? "##{number}" : label
        end

        def name
          label
        end
      end

      ID = /\A#?(\d+)\z/

      # The order's rows. An order written as `[ initiative, name ]` pairs, or naming a character with no
      # state of their own in it, is read once into rows that hold one, and kept.
      def self.rows(encounter)
        held = Array(encounter.participants)

        return held if read?(held)

        # A copy of the encounter read before another one converted its order would convert it again.
        stored = PF2Encounter[encounter.id]

        if stored && read?(stored.participants)
          encounter.participants = stored.participants
          encounter.last_number = stored.last_number
          return stored.participants
        end

        last = encounter.last_number.to_i
        read = held.map do |one|
          unless one.is_a?(Hash)
            last += 1
            char = Character.named(one[1].to_s)
            one = { 'id' => last, 'init' => one[0].to_f, 'name' => one[1].to_s, 'char' => char&.id }.compact
          end

          next one unless one['char'] && !one['state']

          char = Character[one['char']]
          char ? one.merge('state' => CombatantStates.adopted(encounter, char).id) : one
        end

        encounter.update(:participants => read, :last_number => last)
        read
      end

      def self.read?(held)
        Array(held).all? { |one| one.is_a?(Hash) && (!one['char'] || one['state']) }
      end

      def self.holder_of(row)
        return Pf2eNpc[row['npc']] if row['npc']
        return Pf2eCombatantState[row['state']] if row['state']
        return Character[row['char']] if row['char']

        nil
      end

      def self.combatant(row)
        Combatant.new(holder_of(row), row['name'], row['id'].to_i, row['init'].to_f)
      end

      def self.all(encounter)
        rows(encounter).map { |row| combatant(row) }
      end

      # The one at this place in the order.
      def self.at(encounter, index)
        row = rows(encounter)[index]

        row ? combatant(row) : nil
      end

      # Whoever holds a place in the order under this name.
      def self.holder_named(encounter, label)
        return nil if label.to_s.empty?
        return Character.named(label) unless encounter

        row = rows(encounter).find { |one| one['name'] == label }

        row ? holder_of(row) : Character.named(label)
      end

      # ------------------------------------------------------------------------------
      # The order

      # Someone takes a place in the order: a character, a creature, or with no holder a name the GM put
      # there.
      def self.join(encounter, name, init, holder: nil)
        id = encounter.last_number.to_i + 1
        row = { 'id' => id, 'name' => name }

        if holder && Actors.of(holder).creature?
          row['npc'] = holder.id
        elsif holder
          row.merge!('char' => holder.id, 'state' => CombatantStates.for_join(encounter, holder).id)
        end

        row['init'] = placed(row, init)

        encounter.update(:last_number => id)
        write(encounter, rows(encounter) + [ row ])

        row
      end

      def self.leave(encounter, id)
        write(encounter, rows(encounter).reject { |row| row['id'].to_i == id.to_i })
      end

      def self.reroll(encounter, id, init)
        write(encounter, rows(encounter).map { |row| row['id'].to_i == id.to_i ? row.merge('init' => placed(row, init)) : row })
      end

      # Anyone but a character goes before a character on the same roll, which is the rule for a tie
      # between the GM's side and the players'.
      def self.placed(row, init)
        init.to_f + (row['char'] ? 0 : 0.2)
      end

      # The order, sorted, with the turn still on whoever held it.
      def self.write(encounter, rows)
        # Those on the same count stay in the order they were given.
        sorted = rows.each_with_index.sort_by { |row, at| [ -row['init'].to_f, at ] }.map(&:first)

        encounter.update(:next_init => pointer(encounter, rows(encounter), sorted), :participants => sorted)
      end

      # Someone moved to act directly before whoever's turn it is, from here on: who was reduced to no hit
      # points in that turn, or returns from a Delay. Answers whose turn that is where they were moved, and
      # nothing where it is their own or they already act directly before it.
      def self.before_current(encounter, label)
        order = rows(encounter)
        current = ActiveEffects.current_turn(encounter)
        at = order.index { |row| row['name'] == current }

        return nil unless at && current != label && order.any? { |row| row['name'] == label }
        return nil if order[at - 1]['name'] == label

        theirs = order[at]['init'].to_f
        init = at.zero? ? theirs + 1 : (order[at - 1]['init'].to_f + theirs) / 2
        moved = order.find { |row| row['name'] == label }.merge('init' => init)
        rest = order.reject { |row| row['name'] == label }

        # Placed, and not only counted: between two on the same count, the count alone does not say where.
        write(encounter, rest.take_while { |row| row['name'] != current } + [ moved ] + rest.drop_while { |row| row['name'] != current })

        current
      end

      # `next_init` is one past whoever's turn it is. It follows them wherever a sort puts them; if they
      # have left, it points at whoever was to come after them.
      def self.pointer(encounter, was, sorted)
        return 0 if sorted.empty? || was.empty? || encounter.round.to_i.zero?

        at = encounter.next_init.to_i
        place = lambda { |row| sorted.index { |one| one['id'] == row['id'] } }
        held = place.call(was[(at - 1) % was.size])

        return (held + 1) % sorted.size if held

        following = was.size.times.map { |step| was[(at + step) % was.size] }.find { |row| place.call(row) }

        following ? place.call(following) : 0
      end

      # The combatant a command names: `#3`, or a name only one of them has - whole, or the start of it.
      def self.find(encounter, term)
        wanted = term.to_s.strip
        listed = all(encounter)

        if (id = wanted.match(ID))
          found = listed.find { |one| one.number == id[1].to_i }

          return found ? Ok.new(:state => found) : Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => wanted)
        end

        exact = listed.select { |one| one.label.casecmp?(wanted) }
        close = exact.any? ? exact : listed.select { |one| one.label.downcase.start_with?(wanted.downcase) }

        return Ok.new(:state => close.first) if close.size == 1
        return Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => wanted) if close.empty?

        Err.new(:ambiguous_combatant, 'pf2e.ambiguous_combatant', 'target' => wanted,
                'options' => close.map { |one| "#{one.ref} #{one.label}" }.join(', '))
      end

      # Someone a command names, in an encounter or out of one: a combatant where there is an encounter,
      # and otherwise a character by name.
      def self.resolve(enactor, term, encounter = nil)
        if encounter
          found = find(encounter, term)

          return found if found.ok? || term.to_s.match?(ID)
        end

        char = ClassTargetFinder.find(term, Character, enactor)

        return Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => term) unless char.found?

        return Ok.new(:state => Combatant.new(char.target, char.target.name, nil)) unless encounter

        # In an encounter, only someone in it: a character's own sheet is no part of a fight.
        row = rows(encounter).find { |one| one['char'] == char.target.id }

        row ? Ok.new(:state => combatant(row)) : Err.new(:no_combatant, 'pf2e.no_combatant', 'target' => term)
      end

      # Several at once, saying which names found nobody: `[ found, missing ]`.
      def self.resolve_all(enactor, terms, encounter = nil)
        found, missing = Array(terms).map { |term| [ term, resolve(enactor, term, encounter) ] }
                                     .partition { |_term, result| result.ok? }

        [ found.map { |_term, result| result.state }, missing.map(&:first) ]
      end

      # The encounter a command addresses: the one running in the enactor's scene, or - for a GM away from
      # theirs - the one they run.
      def self.encounter_here(enactor)
        scene = enactor.room&.scene

        (scene ? PF2Encounter.scene_active_encounter(scene) : nil) || encounter_run_by(enactor)
      end

      # The encounter a GM runs from wherever they are: the one they chose with `+e/focus`, or the only one
      # they own.
      def self.encounter_run_by(char)
        focused = char.pf2_encounter_focus ? PF2Encounter[char.pf2_encounter_focus] : nil

        return focused if focused&.is_active && gm?(char, focused)

        running = PF2Encounter.running(:owner_id => char.id).to_a

        running.size == 1 ? running.first : nil
      end

      # ------------------------------------------------------------------------------
      # Adding a creature

      # A creature joins the encounter: its own hit points and conditions, an id, and a place in the
      # order - its Perception check unless the GM says where. It is a bestiary creature, a saved one by
      # the revision of it added, or one described on the spot. `name` is what the GM calls it; otherwise
      # it is the creature and its id.
      def self.add_npc(encounter, creature: nil, described: nil, revision: nil, name: nil, initiative: nil, adjustment: nil)
        npc = Pf2eNpc.create(:encounter => encounter, :creature => creature, :described => described || {},
                             :revision => revision, :adjustment => adjustment)
        number = encounter.last_number.to_i + 1
        base = name.to_s.strip.empty? ? "#{creature || (revision&.block || described)['name']} ##{number}" : name.to_s.strip
        label = rows(encounter).any? { |row| row['name'] == base } ? "#{base} ##{number}" : base

        npc.update(:name => label, :number => number)

        rolled = initiative || (Pf2e.roll_dice.first + Npcs.stat(npc, 'perception', nil, [ 'initiative' ])['total'].to_i)

        join(encounter, label, rolled, :holder => npc)

        Ok.new(:state => { 'npc' => npc, 'initiative' => rolled.to_i })
      end

      # ------------------------------------------------------------------------------
      # Who may do what

      # The GM runs the encounter: its organiser, or staff.
      def self.gm?(char, encounter)
        encounter && PF2Encounter.is_organizer?(char, encounter)
      end

      # A GM, or a player the GM trusted for this encounter, may set a target's cover and concealment.
      def self.trusted?(char, encounter)
        gm?(char, encounter) || Array(encounter&.trusted).include?(char.name)
      end
    end
  end
end
