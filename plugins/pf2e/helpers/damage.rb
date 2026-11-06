module AresMUSH
  module Pf2e

    # What an attack does when it hits, assembled the way Foundry assembles it.
    #
    # The shape of a damage roll in PF2e is a number of dice of a size, plus a flat amount, per kind of
    # damage, with some kinds kept apart from the rest: persistent damage is rolled again each round,
    # splash damage applies whether or not the attack hit, and precision damage is lost against
    # anything immune to it. Those are `category` on a rule, and they are why this returns a structure
    # rather than one string.
    #
    # Three things the reader it replaced got wrong, all in the same direction:
    #
    #   * A striking rune adds dice, and it was adding both a die *and* a flat bonus of the same size.
    #   * Strength adds to damage for a melee attack, a propulsive one, or a thrown one that is neither
    #     splash nor a bomb (`actor/helpers.ts:420`). It was added to every attack, so a crossbow got
    #     the archer's Strength.
    #   * A Thief rogue adds Dexterity instead of Strength, but only with a finesse weapon. The racket
    #     was read without that condition.
    #
    # `helpers.ts:378` builds the domains, so a rune that says `{item|id}-damage` reaches the weapon it
    # is on and a feat that says `sword-weapon-group-damage` reaches every sword.
    module Damage

      STRIKING = 'power'.freeze

      # PF2e's own words for the kinds of damage that are rolled apart from the main body of a roll.
      APART = %w{persistent splash precision}.freeze

      # `system/damage/values.ts:40`. A die size steps along this list and stops at either end.
      DIE_SIZES = %w{d4 d6 d8 d10 d12}.freeze

      # A weapon's die size can be raised once however many effects say to raise it
      # (`weapon.ts:478`), which is what stops two upgrades stacking into a d12 fist.
      MAX_INCREASES = 1

      # Whether a contribution doubles on a critical hit (`values.ts:112`). A row that says nothing
      # doubles; one that says `false` applies to both a hit and a crit but never doubles; one that says
      # `true` applies only to a crit, and does not double either.
      #
      #   nil   -> in a hit, and doubled in a crit
      #   false -> in a hit, and in a crit undoubled
      #   true  -> in a crit only, undoubled
      BUCKETS = { nil => 'doubling', false => 'fixed', true => 'crit_only' }.freeze

      # The notes a rule holds for this damage, as `Rules.notes` answers them, kept to the ones for the
      # Strike's `degree` the way `Check#notes` keeps them: a note naming no outcome is for every roll, and
      # one naming outcomes is for those only, so Crushing's critical-hit note stays off an ordinary hit.
      # A creature's Strike has no attribute of its own to add.
      def self.notes(char, attack, options = [], degree = nil)
        ability = char.respond_to?(:pf2_base_info) ? damage_attribute(char, attack) : nil
        domains = Domains.for('damage', attack, ability)
        held = Effects.options(char, domains) + Pf2eCombat.attack_options(attack, char) + Array(options)
        named = degree && Degree::NAMES[degree]

        Rules.notes(Effects.sources(char), domains, held).select do |note|
          note['outcome'].empty? || note['outcome'].include?(named)
        end
      end

      # What a weapon does, with everything that modifies it.
      #
      #   { 'instances' => [ { 'damage_type' =>, 'dice' => [ [ n, die ] ], 'modifier' =>,
      #                        'category' => } ],
      #     'formula' => '2d12+1d6 fire+7', 'critical' => '(2d12+7)x2 + 1d6 fire',
      #     'conditional' => [ … ] }
      def self.of(char, attack, options = [])
        domains = Domains.for('damage', attack, damage_attribute(char, attack))
        sources = Effects.sources(char)
        context = Effects.context(char)
        # The attack's own facts are part of what a rule about this damage is tested against: a
        # shockwave rune's splash is for a melee weapon dealing bludgeoning damage, and the weapon is
        # what knows both.
        held = Effects.options(char, domains) + Pf2eCombat.attack_options(attack, char) + Array(options)

        dice = Effects.damage_dice(sources, domains, context, held)
        flat = Effects.modifiers(sources, domains, context, held)

        # A battle form's attack keeps only what the form allows of the character's own.
        if attack['form']
          dice = dice.select { |row| BattleForms.damage_kept?(row, attack['traits'], attack['source']) }
          flat = flat.select { |row| BattleForms.damage_kept?(row, attack['traits'], attack['source']) }
        end

        met_dice, unmet_dice = dice.partition { |row| row['met'] }
        met_flat, unmet_flat = flat.partition { |row| row['met'] }

        # The flat modifiers are adjusted and stacked as any modifiers are: a fury instinct raises Rage's
        # +2 to +3, and of two status bonuses only the better counts.
        met_flat = Modifiers.stack(Modifiers.adjust(met_flat, Rules.modifier_adjustments(sources, domains, held, context)))
                            .select { |row| row['enabled'] }

        # A bomb's persistent and splash damage are the bomb's own, so they always apply.
        bomb_dice, bomb_flat = Consumables.bomb_rows(attack)
        met_dice += bomb_dice
        # What the weapon's traits add to this Strike is the Strike's to say (`WeaponTraits`).
        met_flat += bomb_flat + Array(attack['bonus_damage'])

        # An override adjusts the weapon's own dice rather than adding any of its own, so it is taken
        # out before the rest are added up.
        overriding, adding = met_dice.partition { |row| row['override'] }

        instances = alter(assemble(char, attack, adding, met_flat, overriding),
                          Rules.damage_alterations(sources, domains, held, context))

        { 'instances' => instances,
          'formula' => render(instances, false),
          'critical' => render(critical_instances(instances, attack), true),
          'conditional' => unmet_dice + unmet_flat }
      end

      # ------------------------------------------------------------------------------
      # What a critical hit adds beyond doubling

      # A trait that carries a die, whichever way it is spelled: a creature's stat block writes
      # `deadly-d10`, this game's catalogue `Deadly (d10)`, and a deadly trait may name more than one
      # die (`deadly-2d10`). `[ count, faces ]`, or nothing.
      def self.trait_dice(attack, name)
        found = Array(attack['traits']).map { |one| Domains.slug(one) }
                                       .map { |one| one.match(/\A#{name}-(\d)?d(\d{1,2})\z/) }.compact.first

        found ? [ (found[1] || 1).to_i, found[2].to_i ] : nil
      end

      def self.trait_die(attack, name)
        trait_dice(attack, name)&.last
      end

      # `weapon.ts:268`. Deadly adds its dice on a critical hit, undoubled - as many times over as the
      # striking rune adds dice, once it adds more than one. Fatal rolls the weapon's own dice at its
      # size, which are doubled with the rest, and adds one more of that size, which is not.
      def self.critical_extras(attack)
        extras = []

        if (deadly = trait_dice(attack, 'deadly'))
          striking = attack['striking'].to_i
          extras << [ striking > 1 ? striking * deadly.first : deadly.first, "d#{deadly.last}" ]
        end

        fatal = trait_die(attack, 'fatal')
        extras << [ 1, "d#{fatal}" ] if fatal

        extras
      end

      # The weapon's instance as a critical hit leaves it: its own dice at the fatal size, and the
      # critical-only dice added.
      def self.critical_instances(instances, attack)
        return instances if instances.empty?

        base = instances.first.transform_values { |value| value.is_a?(Array) ? value.dup : value }
        fatal = trait_die(attack, 'fatal')
        weapon = base['dice'].index { |_count, die| die.to_s == base['die'].to_s }

        base['dice'][weapon] = [ base['dice'][weapon].first, "d#{fatal}" ] if fatal && weapon
        base['crit_only_dice'] = Array(base['crit_only_dice']) + critical_extras(attack)

        [ base ] + instances.drop(1)
      end

      def self.formula(char, attack, options = [])
        of(char, attack, options)['formula']
      end

      def self.critical(char, attack, options = [])
        of(char, attack, options)['critical']
      end

      # ------------------------------------------------------------------------------

      # Changes a roll has after it is built rather than additions to it: the kind of damage it deals,
      # how many dice, or how large they are. A `dice-faces` upgrade with nothing to upgrade to means one
      # step larger, which is the same step a DamageDice override takes.
      ALTERATIONS = {
        'damage-type' => ->(instance, one) { instance['damage_type'] = one['value'] if one['value'] },
        'dice-number' => ->(instance, one) { instance['count'] = counted(instance, one) },
        'dice-faces' => ->(instance, one) { instance['die'] = faces(instance, one) }
      }.freeze

      def self.alter(instances, alterations)
        return instances if alterations.empty?

        instances.each do |instance|
          alterations.each do |one|
            change = ALTERATIONS[one['property']]

            next unless change

            change.call(instance, one)
          end

          instance['dice'] = instance['die'] ? [ [ instance['count'].to_i, instance['die'] ] ] : []
        end
      end

      def self.counted(instance, one)
        current = instance['count'].to_i

        case one['mode']
        when 'multiply' then (current * one['value'].to_i)
        when 'add' then current + one['value'].to_i
        when 'upgrade' then [ current, one['value'].to_i ].max
        else one['value'] ? one['value'].to_i : current
        end
      end

      def self.faces(instance, one)
        return step(instance['die'], 1) if one['value'].nil?
        return one['value'] if one['mode'] == 'override'

        one['mode'] == 'upgrade' ? step(instance['die'], 1) : instance['die']
      end

      # The weapon's own dice, then everything else grouped by the kind of damage it deals. A row that
      # names no kind deals the weapon's kind, which is what makes a plain +2 a bonus to the whole hit
      # rather than to something of its own.
      def self.assemble(char, attack, dice, flat, overriding = [])
        base = override(base_instance(char, attack), overriding)
        instances = { [ base['damage_type'], nil ] => base }

        (dice + flat).each do |row|
          key = [ row['damage_type'] || base['damage_type'], apart(row['category']) ]

          # A flat bonus to persistent damage - Burn It!'s +1 to persistent fire - is a bonus to that
          # damage where the roll deals some, and makes none of its own. Dice do, and a bomb's own
          # persistent damage says it does. Flat splash and precision damage are damage of their own:
          # a shockwave rune's splash, a swashbuckler's precise strike.
          next if key.last == 'persistent' && !row['die'] && !row['creates'] && !instances.key?(key)

          into = instances[key] ||= empty_instance(key)

          add(into, row)
        end

        instances.values.reject { |instance| empty?(instance) }
      end

      def self.empty_instance(key)
        BUCKETS.values.each_with_object({ 'damage_type' => key.first, 'category' => key.last,
                                          'sources' => [] }) do |bucket, out|
          out[dice_key(bucket)] = []
          out[modifier_key(bucket)] = 0
        end
      end

      def self.add(instance, row)
        bucket = BUCKETS.fetch(row['critical'], 'doubling')

        instance['sources'] << row['source']

        if row['die'] && row['dice'].to_i.positive?
          instance[dice_key(bucket)] << [ row['dice'].to_i, row['die'] ]
        else
          instance[modifier_key(bucket)] += row['value'].to_i
        end
      end

      def self.dice_key(bucket)
        bucket == 'doubling' ? 'dice' : "#{bucket}_dice"
      end

      def self.modifier_key(bucket)
        bucket == 'doubling' ? 'modifier' : "#{bucket}_modifier"
      end

      # A category we keep apart, or nothing. An unrecognised one is treated as part of the main roll,
      # because a number in the wrong pile still adds up and a number dropped does not.
      def self.apart(category)
        APART.include?(category.to_s) ? category.to_s : nil
      end

      # `system/damage/helpers.ts:118`. A step up or down in die size happens first, because an override
      # of the die size is meant to win over one - a fatal powerful fist is their example. Each
      # direction is capped separately and then netted, so two effects that raise a weapon's die and one
      # that lowers it come to one step up.
      def self.override(base, overriding)
        adjustments = overriding.map { |row| row['override'] }.compact

        ups = [ adjustments.count { |one| one['upgrade'] }, MAX_INCREASES ].min
        downs = [ adjustments.count { |one| one['downgrade'] }, MAX_INCREASES ].min

        base['die'] = step(base['die'], ups - downs)

        adjustments.each do |one|
          base['damage_type'] = one['damageType'] if one['damageType']
          base['die'] = one['dieSize'] if one['dieSize']
          base['count'] = one['diceNumber'].to_i if one['diceNumber']
          base['sources'] << 'override'
        end

        base['dice'] = base['die'] ? [ [ base['count'], base['die'] ] ] : []

        base
      end

      # A die size some number of steps along, stopping at either end of the list.
      def self.step(die, delta)
        at = DIE_SIZES.index(die.to_s)

        return die unless at && !delta.zero?

        DIE_SIZES[(at + delta).clamp(0, DIE_SIZES.size - 1)]
      end

      # The weapon's own dice and the attribute modifier that goes with them.
      #
      # A striking rune raises the number of dice - `weapon.ts:263` reads it as the difference between
      # the weapon's dice and its printed dice - and adds nothing flat.
      def self.base_instance(char, attack)
        die = attack['die']
        # A catalogue weapon rolls one die before striking; a granted attack says how many it rolls,
        # because some of them roll two.
        count = (attack['dice'] || 1).to_i + attack['striking'].to_i
        attribute = damage_attribute(char, attack)

        # A battle form's attack has its own damage modifier where the attribute would be.
        modifier = if attack['form'] then attack['form']['damage_modifier'].to_i
                   elsif attribute then Pf2e.ability_mod(char, attribute)
                   else 0
                   end

        # An attack with no die deals a flat amount of its own, as an acid flask's 1 acid does.
        modifier += attack['flat'].to_i

        empty_instance([ attack['damage_type'] || 'B', nil ])
          .merge('die' => die,
                 'count' => count,
                 'dice' => die ? [ [ count, die ] ] : [],
                 'modifier' => modifier,
                 'sources' => [ attack['name'], attribute ].compact)
      end

      # Which attribute adds to this attack's damage, or nothing.
      #
      # `actor/helpers.ts:420`: Strength for a melee attack, a propulsive one, or a thrown one that is
      # neither splash nor a bomb. A Thief rogue reads Dexterity instead, and only with a finesse
      # weapon - the racket says "when you attack with a finesse or thrown weapon".
      def self.damage_attribute(char, attack)
        return nil unless strength_based?(attack)

        thief?(char) && Pf2e.has_trait?(attack['traits'], 'finesse') ? 'Dexterity' : 'Strength'
      end

      def self.strength_based?(attack)
        traits = attack['traits']

        return true unless attack['ranged']
        return true if Pf2e.has_trait?(traits, 'propulsive')

        Pf2e.has_trait?(traits, 'thrown') && !Pf2e.has_trait?(traits, 'splash') && !attack['bomb']
      end

      def self.thief?(char)
        (char.pf2_base_info || {})['specialize'].to_s.casecmp?('Thief')
      end

      def self.empty?(instance)
        BUCKETS.values.all? do |bucket|
          instance[dice_key(bucket)].empty? && instance[modifier_key(bucket)].zero?
        end
      end

      # `2d12+1d6 fire+7`, with anything kept apart named: `1d6 persistent bleed`. On a critical hit the
      # doubling part is doubled and the rest is added to it, which is the default rule - doubling the
      # total rather than the dice.
      def self.render(instances, critical)
        instances.map { |instance| render_instance(instance, critical) }
                 .reject(&:empty?).join(' + ')
      end

      def self.render_instance(instance, critical)
        doubled = body(instance, 'doubling')
        doubled = doubled.empty? || !critical ? doubled : "(#{doubled})x2"

        parts = [ doubled, body(instance, 'fixed') ]
        parts << body(instance, 'crit_only') if critical

        joined = parts.reject(&:empty?).join('+').gsub('+-', '-')

        return '' if joined.empty?

        [ joined, instance['category'], instance['damage_type'] ].compact.join(' ')
      end

      def self.body(instance, bucket)
        dice = merge(instance[dice_key(bucket)]).map { |count, die| "#{count}#{die}" }
        flat = instance[modifier_key(bucket)]

        (dice + (flat.zero? ? [] : [ flat.to_s ])).join('+')
      end

      # Two rows of the same die size are one roll of that many dice.
      def self.merge(dice)
        dice.group_by(&:last).map { |die, rows| [ rows.sum(&:first), die ] }
      end

    end
  end
end
