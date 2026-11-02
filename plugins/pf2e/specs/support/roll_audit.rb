module AresMUSH
  module Pf2e

    # Checks the arithmetic of every roll, defence and hit an encounter makes, worked out a second time
    # from the rules rather than from the engine's own figures:
    #
    #   a roll        its total is its die and its modifiers; its modifiers stack by type, the best bonus
    #                 and the worst penalty of each and every untyped one; its degree is its total against
    #                 the DC, a step either way for a natural 20 or 1
    #   conditions    each condition the roller or defender holds shows as the modifier the rules give it:
    #                 frightened and sickened on every check and DC, clumsy on AC and Reflex and anything
    #                 Dexterity rolls, off-guard on AC, and the rest
    #   the sheet     a character's Strike is their level and proficiency, the attribute it uses and their
    #                 potency rune; a creature's AC, saves and attacks are its stat block's
    #   damage        what a roll deals is within what its formula can roll; what lands is that, less a
    #                 resistance and more a weakness, nothing through an immunity; and the target's hit
    #                 points move by exactly what landed
    #
    # The scenario's spec wraps the engine's own calls (`Resolve.roll`, `Resolve.defence`, `DamageRoll`,
    # `Harm.damage`) and hands each here. What does not add up is a finding.
    class RollAudit

      Finding = Struct.new(:kind, :what, :detail, keyword_init: true) do
        def to_s
          "#{kind}: #{what} - #{detail}"
        end
      end

      attr_reader :findings, :counts

      def initialize
        @findings = []
        @counts = Hash.new(0)
        @rolls = {}
        @defences = {}
      end

      # The last roll someone made, and the last defence of theirs rolled against, for a probe to read.
      def last_roll(name)
        @rolls[name]
      end

      def last_defence(name)
        @defences[name]
      end

      # The rows of the last damage rolled, whoever rolled it.
      attr_reader :last_damage

      # A check the audit could not make is itself a finding, so a broken audit cannot pass quietly.
      def safely(what)
        yield
      rescue StandardError => e
        find('audit', what, "#{e.class}: #{e.message} (#{e.backtrace&.first})")
      end

      def find(kind, what, detail)
        @findings << Finding.new(:kind => kind, :what => what, :detail => detail)
      end

      # ------------------------------------------------------------------------------
      # Rolls

      def rolled(check, dc, result)
        @counts['rolls'] += 1
        what = describe(check)
        @rolls[check.char.name] = { 'check' => check, 'result' => result, 'dc' => dc }
        breakdown = result['breakdown'] || {}
        face = result['die'] || (result['substitution'] || {})['value']

        find('total', what, "#{face} + #{breakdown['total']} is not #{result['total']}") if
          face && result['total'] != face.to_i + breakdown['total'].to_i

        stacked(what, breakdown)
        degree(check, what, result, face, dc) if dc
        conditions(check.char, what, roll_kinds(check), breakdown)
        sheet(check, what, breakdown)
      end

      def describe(check)
        name = check.name.is_a?(Hash) ? check.name['name'] : check.name
        "#{check.char.name} #{check.kind}#{name ? " (#{name})" : ''}"
      end

      # The modifiers stacked again by the rules: per type, the best bonus and the worst penalty;
      # untyped all; attributes, the best alone.
      def stacked(what, breakdown)
        rows = Array(breakdown['modifiers'])

        return if rows.empty? && breakdown['total'].to_i == breakdown['base'].to_i

        counted = rows.group_by { |row| row['type'].to_s.downcase }.sum do |type, group|
          values = group.map { |row| row['value'].to_i }

          case type
          when 'untyped', '' then values.sum
          when 'ability' then values.max
          else (values.select(&:positive?).max || 0) + (values.select(&:negative?).min || 0)
          end
        end

        expected = breakdown['base'].to_i + counted

        return if expected == breakdown['total'].to_i

        find('stacking', what, "rules give #{expected}, engine #{breakdown['total']}: #{brief(rows)}")
      end

      def brief(rows)
        rows.map { |row| "#{row['source']} #{row['type']} #{row['value']}#{row['enabled'] ? '' : ' (off)'}" }.join(', ')
      end

      # The degree by the rules, before anything that adjusts it. Where the check carries an adjustment
      # (Assurance, a keen rune) a difference is the adjustment's, and is counted rather than found.
      def degree(check, what, result, face, dc)
        total = result['total'].to_i
        steps = if total >= dc + 10 then 3 elsif total >= dc then 2 elsif total <= dc - 10 then 0 else 1 end
        steps += 1 if face.to_i == 20 && result['die']
        steps -= 1 if face.to_i == 1 && result['die']
        steps = (steps.clamp(0, 3) + result['shift'].to_i).clamp(0, 3)

        return if steps == result['degree']

        if check.respond_to?(:adjustments) && Array(check.adjustments(check.rolled(total, dc, result['die']))).any?
          @counts['adjusted degrees'] += 1
          return
        end

        find('degree', what, "#{total} (die #{face}) vs DC #{dc} is #{Resolve::WORDS[steps]}, engine said #{Resolve::WORDS[result['degree'].to_i]}")
      end

      # ------------------------------------------------------------------------------
      # Defences

      def defended(holder, against, result)
        return unless result

        @counts['defences'] += 1
        @defences[holder.name] = result
        kind, name = Resolve.defence_figure(against)
        what = "#{holder.name} #{kind}#{name ? " (#{name})" : ''} DC #{result['dc']}"
        breakdown = result['breakdown'] || {}

        stacked(what, breakdown)
        conditions(holder, what, defence_kinds(kind, name), breakdown)
        stat_block(holder, what, kind, name, breakdown)
      end

      # ------------------------------------------------------------------------------
      # Conditions

      # What each condition takes from, by the kinds of check and DC it reaches, as the rules give it.
      CONDITION_REACH = {
        'Frightened' => [ :all ],
        'Sickened' => [ :all ],
        'Clumsy' => %i{ac reflex dex},
        'Enfeebled' => %i{str},
        'Stupefied' => %i{will mental spell perception},
        'Drained' => %i{fortitude}
      }.freeze

      def roll_kinds(check)
        kinds = [ :all ]
        name = check.name

        case check.kind
        when 'attack'
          # A creature's Strike is its stat block's number, whichever attribute is behind it.
          kinds << (attack_attribute(check.char, name) == 'Dexterity' ? :dex : :str) unless Actors.of(check.char).creature?
        when 'spell_attack', 'spell_dc' then kinds << :spell
        when 'perception', 'initiative' then kinds << :perception
        when 'save' then kinds << name.to_s.downcase.to_sym
        end

        kinds
      end

      def defence_kinds(kind, name)
        case kind
        when 'ac' then %i{all ac}
        when 'save' then [ :all, name.to_s.downcase.to_sym ]
        when 'perception' then %i{all perception}
        else [ :all ]
        end
      end

      def conditions(holder, what, kinds, breakdown)
        held = holder.respond_to?(:pf2_conditions) ? (holder.pf2_conditions || {}) : {}
        rows = Array(breakdown['modifiers'])

        held.each_pair do |name, info|
          reach = CONDITION_REACH[name]
          value = info.is_a?(Hash) ? info['value'].to_i : info.to_i

          next unless reach && value.positive?
          next unless reach.include?(:all) || (reach & kinds).any?

          @counts['conditions checked'] += 1
          found = rows.find { |row| row['type'].to_s == 'status' && row['value'].to_i == -value && row['source'].to_s.downcase.include?(name.downcase) }

          find('condition', what, "#{name} #{value} gives no -#{value} status: #{brief(rows)}") unless found
        end

        off_guard(holder, what, kinds, held, rows)
        prone_attack(what, kinds, held, rows)
      end

      # Prone is also a -2 circumstance penalty to one's own attack rolls.
      def prone_attack(what, kinds, held, rows)
        return unless held.key?('Prone') && (kinds & %i{str dex spell}).any? && !kinds.include?(:ac)

        @counts['conditions checked'] += 1
        return if rows.any? { |row| row['type'].to_s == 'circumstance' && row['value'].to_i == -2 }

        find('condition', what, "prone gives no -2 circumstance to its attack: #{brief(rows)}")
      end

      # Off-guard, and prone which makes one off-guard, are a -2 circumstance penalty to AC.
      def off_guard(holder, what, kinds, held, rows)
        return unless kinds.include?(:ac) && (held.key?('Off-Guard') || held.key?('Prone'))

        @counts['conditions checked'] += 1
        return if rows.any? { |row| row['type'].to_s == 'circumstance' && row['value'].to_i == -2 && row['enabled'] }

        find('condition', what, "off-guard gives no -2 circumstance to AC: #{brief(rows)}")
      end

      # ------------------------------------------------------------------------------
      # The sheet and the stat block

      PROFICIENCY = { 'untrained' => 0, 'trained' => 2, 'expert' => 4, 'master' => 6, 'legendary' => 8 }.freeze

      # A character's Strike: level and proficiency, the attribute, and the potency rune's item bonus.
      def sheet(check, what, breakdown)
        return unless check.kind == 'attack' && check.name.is_a?(Hash) && !Actors.of(check.char).creature?

        attack = check.name
        rank = attack['prof'].to_s.downcase
        level = check.char.pf2_level.to_i
        proficiency = rank == 'untrained' || rank.empty? ? 0 : level + PROFICIENCY.fetch(rank, 0)
        attribute = Pf2e.ability_mod(check.char, attack_attribute(check.char, attack))
        item = attack['rune'].to_i

        @counts['strikes checked'] += 1
        rows = Array(breakdown['modifiers']).select { |row| row['enabled'] }
        engine = breakdown['base'].to_i + rows.select { |row| %w{proficiency ability item potency}.include?(row['type'].to_s) }.sum { |row| row['value'].to_i }
        expected = proficiency + attribute + item

        return if engine == expected

        find('sheet', what, "#{rank} at #{level} (#{proficiency}) + #{attack_attribute(check.char, attack)} #{attribute} + item #{item} is #{expected}, engine #{engine}: #{brief(Array(breakdown['modifiers']))}")
      end

      # Dexterity for a ranged Strike, the better of the two for a finesse one, Strength otherwise.
      def attack_attribute(char, attack)
        return 'Strength' unless attack.is_a?(Hash)
        return 'Dexterity' if attack['ranged']

        finesse = Pf2e.has_trait?(attack['traits'], 'finesse')
        finesse && Pf2e.ability_mod(char, 'Dexterity') > Pf2e.ability_mod(char, 'Strength') ? 'Dexterity' : 'Strength'
      end

      # A creature's defence before what it is under is its stat block's number.
      def stat_block(holder, what, kind, name, breakdown)
        return unless Actors.of(holder).creature?

        block = holder.stat_block || {}
        listed = case kind
                 when 'ac' then block['ac']
                 when 'save' then (block['saves'] || {})[name.to_s.downcase]
                 when 'perception' then block['perception']
                 end

        return unless listed

        @counts['stat blocks checked'] += 1
        base = breakdown['base'].to_i

        find('stat block', what, "stat block says #{listed}, engine's base is #{base}") unless base == listed.to_i
      end

      # ------------------------------------------------------------------------------
      # Damage

      # What a roll dealt is within what its formula can roll.
      def dealt_rows(rows, critical)
        @last_damage = Array(rows)

        Array(rows).each do |row|
          next if row['formula'].to_s.empty?

          low, high = range_of(row['formula'])
          next unless low

          @counts['damage rolls'] += 1
          next if row['amount'].to_i.between?([ low, 0 ].max, high)

          find('damage', "#{row['amount']} #{row['type']}#{critical ? ' (critical)' : ''}", "outside #{row['formula']}, which rolls #{low}-#{high}")
        end
      end

      def range_of(formula)
        terms = formula.to_s.delete(' ').split(/(?=[+-])/)

        return nil unless terms.all? { |term| term.match?(/\A[+-]?(\d*d\d+|\d+)\z/) }

        terms.each_with_object([ 0, 0 ]) do |term, out|
          sign = term.start_with?('-') ? -1 : 1
          body = term.delete('+-')

          if body.include?('d')
            count, faces = body.split('d')
            count = count.empty? ? 1 : count.to_i
            out[0] += sign * count
            out[1] += sign * count * faces.to_i
          else
            out[0] += sign * body.to_i
            out[1] += sign * body.to_i
          end
        end
      end

      # What landed is the roll after immunity, weakness and resistance, and the hit points moved by it.
      def landed(holder, amount, type, before, after, result)
        @counts['hits checked'] += 1
        what = "#{holder.name} took #{amount} #{type}"
        applied = Array(result['applied'])

        expected = if applied.any? { |one| one['category'] == 'immunity' }
                     0
                   else
                     [ amount.to_i + applied.sum { |one| one['adjustment'].to_i }, 0 ].max
                   end

        find('resistance', what, "#{applied.map { |one| "#{one['category']} #{one['adjustment']}" }.join(', ')} leaves #{expected}, engine #{result['amount']}") unless expected == result['amount'].to_i

        moved = before - after
        return if moved == [ result['amount'].to_i, before ].min || before <= 0

        find('hit points', what, "#{result['amount']} landed but hit points went #{before} -> #{after}")
      end

      # A whole hit on a character, whatever kinds of damage it dealt: one that leaves them at nothing
      # leaves them Dying 1, or 2 from a critical hit, more by their Wounded - or one or two higher than
      # they were - and dead only at the value Doomed leaves for it. `before` and `after` are
      # `{ 'hp' =>, 'temp' =>, 'dying' =>, 'wounded' =>, 'doomed' =>, 'dead' => }`. `dealt` is what the hit
      # landed after resistances: one that landed nothing, or only set damage to burn later, did them no
      # damage and leaves their dying where it was.
      def hit_dropped(name, before, after, critical, dealt = nil)
        return if dealt&.zero?
        return if before['dead'] || after['hp'].positive? || (before['hp'].zero? && before['dying'].zero?)
        # Temporary hit points on someone already down may have taken all of it.
        return if before['hp'].zero? && before['temp'].to_i.positive?

        @counts['hits checked for dying'] += 1
        expected = (before['dying'].positive? ? before['dying'] : before['wounded']) + (critical ? 2 : 1)
        fatal = 4 - before['doomed']
        what = "#{name}, at #{before['hp']} hit points, Dying #{before['dying']}, Wounded #{before['wounded']}"

        if expected >= fatal
          find('dying', what, "should be dead or spared at Dying #{expected}, and is Dying #{after['dying']}") if !after['dead'] && after['dying'].positive?
        elsif after['dead']
          find('dying', what, "died of one#{critical ? ' critical' : ''} hit, which leaves Dying #{expected}")
        elsif after['dying'] != expected
          find('dying', what, "one#{critical ? ' critical' : ''} hit should leave Dying #{expected}, and left #{after['dying']}")
        end
      end
    end
  end
end
