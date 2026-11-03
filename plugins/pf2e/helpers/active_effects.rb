module AresMUSH
  module Pf2e

    # Effects a character or a creature in an encounter is under: applying one, reading it, and ending it.
    #
    # What an effect does is its catalogue entry's rules, read by the same machinery as a feat's, so an
    # effect is one more source in `Effects.sources` and every derived figure picks it up. What this adds
    # is time. An effect has a duration in Foundry's own terms, and it ends in one of three ways:
    #
    #   * by the clock of the encounter it was applied in - a round is a turn of the order, a minute is
    #     ten of them, and the count runs from the turn it began on, which is the caster's
    #   * with the encounter itself, for anything that could not outlast the fight
    #   * at a night's rest, for anything shorter than a day - and a day-long one counts its nights
    #
    # An effect applied outside an encounter has no clock to run on, so it lasts until the next rest or
    # until someone ends it.
    module ActiveEffects

      # How each unit of duration is measured, and what it survives. A minute is ten rounds; an hour
      # outlasts a fight but not a night's sleep; a day is counted in rests.
      UNITS = {
        'rounds' => { 'rounds' => 1, 'outlasts_encounter' => false, 'outlasts_rest' => false },
        'minutes' => { 'rounds' => 10, 'outlasts_encounter' => false, 'outlasts_rest' => false },
        'hours' => { 'rounds' => 600, 'outlasts_encounter' => true, 'outlasts_rest' => false },
        'days' => { 'rests' => 1, 'outlasts_encounter' => true, 'outlasts_rest' => true },
        'encounter' => { 'outlasts_encounter' => false, 'outlasts_rest' => false },
        'unlimited' => { 'outlasts_encounter' => true, 'outlasts_rest' => true }
      }.freeze

      # Foundry names an effect after what left it: `Spell Effect: Heroism`, `Effect: Rage`. A player
      # types `heroism`, so the prefix is not part of what they are matched on.
      PREFIXES = /\A(?:Spell Effect|Effect|Stance|Aura):\s*/

      # How deep a chain of effects granting effects is followed before it is taken to be a loop.
      DEPTH = 4

      def self.catalogue
        Global.read_config('pf2e_effects') || {}
      end

      def self.info(name)
        catalogue[name] || {}
      end

      # The catalogue entry a player means, by the name they typed.
      def self.find(term)
        wanted = Domains.slug(term)
        names = catalogue.keys

        exact = names.find { |name| Domains.slug(name) == wanted } ||
                names.find { |name| Domains.slug(name.sub(PREFIXES, '')) == wanted }

        return Ok.new(:state => exact) if exact

        close = names.select { |name| Domains.slug(name.sub(PREFIXES, '')).include?(wanted) }

        return Ok.new(:state => close.first) if close.size == 1
        return Err.new(:not_found, 'pf2e.effect_not_found', 'effect' => term) if close.empty?

        Err.new(:ambiguous, 'pf2e.effect_ambiguous', 'effect' => term,
                'options' => close.first(8).join(', '))
      end

      def self.on(char)
        char.pf2_effects.to_a
      end

      def self.named_on(char, name)
        on(char).select { |effect| effect.name == name }
      end

      def self.active?(char, name)
        named_on(char, name).any?
      end

      # ------------------------------------------------------------------------------
      # What an effect does

      # One source per effect, with the effect's own rank and badge where its rules read them
      # (`@item.level`, `@item.badge.value`), and the answers it was applied with where a choice set
      # asks for them. An effect another brought with it for as long as it lasts is a source too.
      def self.sources(char)
        on(char).flat_map { |effect| source_and_derived(char, effect.name, instance_item(effect),
                                                        effect.answers, 0, BattleForms.rows(char, effect)) }
      end

      def self.instance_item(effect)
        { 'id' => effect.id.to_s, '_id' => effect.id.to_s, 'level' => effect.level.to_i,
          'badge' => { 'value' => effect.badge.to_i } }
      end

      # `extra` is what the effect gives through the ordinary rules beyond its own - a battle form's
      # senses, size and resistances.
      def self.source_and_derived(char, name, item, answers, depth, extra = [])
        rules = Array(info(name)['rules']) + extra
        built = Effects.with_selections(char, Effects.source(name, rules, 'item' => item,
                                                             'chosen' => answers))

        return [ built ] if depth >= DEPTH

        derived = effect_grants(name).select { |grant| grant['derived'] && granted?(char, grant) }

        [ built ] + derived.flat_map { |grant|
          source_and_derived(char, grant['name'], item, [], depth + 1)
        }
      end

      def self.grants_of(name)
        Grants.of(info(name)['rules'])
      end

      def self.effect_grants(name)
        grants_of(name).select { |grant| grant['catalogue'] == 'effects' && catalogue.key?(grant['name']) }
      end

      def self.condition_grants(name)
        grants_of(name).select { |grant| grant['catalogue'] == 'conditions' }
      end

      # A grant's predicate is tested against what is true of the character without asking what they
      # are under - which is what those facts are built from - and against what the effect itself
      # declares. Animate Net immobilizes only on a critical success, and says so as an option of its own.
      def self.granted?(char, grant, own = [])
        grant['predicate'].nil? ||
          Predicate.test(grant['predicate'], Effects.character_facts(char) + Array(own))
      end

      # What an effect declares about itself: the answers it was applied with, as the options its choice
      # sets name, and the options its own `RollOption` rules hold by default.
      def self.own_options(char, effect)
        built = answered(char, effect)
        declared = Rules.of_kind(built, 'RollOption').map { |row| Rules.resolved(row, built, {}) }
                        .compact.map { |row| row['option'] }.compact

        Array(built['options']) + declared
      end

      def self.answered(char, effect)
        Effects.with_selections(char, Effects.source(effect.name, Array(info(effect.name)['rules']),
                                                     'item' => instance_item(effect),
                                                     'chosen' => effect.answers))
      end

      # The conditions the character's effects bring with them for as long as they last, as
      # `held_conditions` seeds its list from.
      def self.derived_conditions(char)
        on(char).flat_map do |effect|
          own = own_options(char, effect)

          condition_grants(effect.name).select { |grant| grant['derived'] && granted?(char, grant, own) }
                                       .map { |grant| [ grant, effect.name ] }
        end
      end

      # ------------------------------------------------------------------------------
      # Applying one

      # `options` are what the player said about it after its name: `rank 6` for the rank it was cast
      # at, `value 3` for a counter, and anything else as an answer to what it asks - `fire` for which
      # energy Resist Energy resists. `lasts` is a duration other than the catalogue's, where what applies
      # it decides how long it goes on.
      def self.apply(char, term, options: [], applied_by: nil, encounter: nil, granted_by: nil, lasts: nil)
        found = find(term)

        return found if found.err?

        name = found.state
        entry = info(name)
        said = parse(options)
        said['answers'] = owned_answers(char, name, said['answers'])
        duration = (entry['duration'] || {}).merge(lasts || {})
        unit = UNITS.key?(duration['unit']) ? duration['unit'] : 'unlimited'
        max_before = HitPointLoss.takes?(entry['rules']) ? HitPointLoss.max_hp(char) : nil

        effect = Pf2eEffect.create(
          Actors.of(char).effect_owner_field => char, :name => name, :applied_by => applied_by,
          :level => said['level'] || entry['level'] || 1,
          :badge => said['badge'] || (entry['badge'] || {})['value'],
          :unit => unit, :duration => duration['value'].to_i, :expiry => duration['expiry'],
          :encounter => encounter, :started_round => encounter&.round,
          :started_turn => encounter ? current_turn(encounter) : nil,
          :rests_left => unit == 'days' ? duration['value'].to_i : nil,
          :answers => said['answers'])

        effect.update(:granted_by => granted_by) if granted_by
        effect.update(:sustained => true, :sustained_round => sustained_through(effect, encounter)) if duration['sustained'] && encounter

        grant_stored(char, effect, encounter)

        # What the effect writes is derived, so it is rebuilt with the effect among the sources before
        # anything reads it - Rage's temporary hit points are a number its own write leaves behind.
        Paths.apply_all!(char)
        give_temp_hp(char, effect, 'on_create')
        HitPointLoss.effect_began(char, effect, max_before)

        Ok.new(:state => effect)
      end

      # An answer naming one of the character's own things - `longsword` for "the weapon you choose" - is
      # held as that thing's id, which is what the effect's rules name.
      def self.owned_answers(char, name, answers)
        sets = Rules.choice_sets(Effects.source(name, Array(info(name)['rules']))).select { |set| set['owned'] }

        answers.map do |typed|
          sets.map { |set| Choices.owned_answer(set, char, typed) }.compact.first || typed
        end
      end

      # The questions about one of the character's own things that these answers leave open: those no
      # answer settles with something the set would take, and whose own condition the answers meet.
      def self.items_wanted(char, name, answers)
        return [] unless Actors.of(char).carries_items?

        built = Effects.with_selections(char, Effects.source(name, Array(info(name)['rules']),
                                                             'chosen' => owned_answers(char, name, answers)))
        selections = (built['item'] || {}).dig('flags', 'system', 'rulesSelections') || {}
        known = Effects.character_facts(char) + Array(built['options'])

        Rules.choice_sets(built).select do |set|
          set['owned'] && set['flag'] && Predicate.test(set['when'], known) &&
            !Choices.offer(set, char).include?(selections[set['flag'].to_s])
        end
      end

      # The answers that go without saying, where the only thing a question could mean is equipped.
      def self.items_in_hand(char, name, answers)
        items_wanted(char, name, answers).map { |set| Choices.in_hand(set, char) }
                                         .select { |held| held.size == 1 }.map(&:first)
      end

      def self.parse(options)
        Array(options).each_with_object({ 'answers' => [] }) do |option, out|
          text = option.to_s.strip

          if (found = text.match(/\Arank\s+(\d+)\z/i))
            out['level'] = found[1].to_i
          elsif (found = text.match(/\Avalue\s+(\d+)\z/i))
            out['badge'] = found[1].to_i
          elsif !text.empty?
            out['answers'] << text
          end
        end
      end

      # What the effect brings with it that is stored in its own right: a condition, or another effect.
      def self.grant_stored(char, effect, encounter)
        own = own_options(char, effect)

        condition_grants(effect.name).reject { |grant| grant['derived'] }.each do |grant|
          next unless granted?(char, grant, own)

          name = Pf2e.canonical_condition(grant['name'])

          next if (char.pf2_conditions || {}).key?(name)
          next if Gm.spared?(char, name, effect.applied_by)

          Pf2e.set_condition(char, name, grant['value'] || Pf2e.default_condition_value(name),
                             'granted_by' => effect.name,
                             'when_granter_goes' => grant['when_granter_goes'],
                             'restricted' => grant['restricted'])
        end

        effect_grants(effect.name).reject { |grant| grant['derived'] }.each do |grant|
          next unless granted?(char, grant, own)
          next if !grant['duplicate'] && active?(char, grant['name'])

          apply(char, grant['name'], :applied_by => effect.applied_by, :encounter => encounter,
                                     :granted_by => effect.name)
        end
      end

      # ------------------------------------------------------------------------------
      # Temporary hit points

      # Foundry's rule: the better of what is held and what is given, and the effect that gave them is
      # recorded so ending it takes them away.
      def self.give_temp_hp(char, effect, event)
        hp = char.hp

        return unless hp

        # Its own rules and what it gives through them - a battle form's temporary hit points.
        rows = Rules.of_kind({ 'rules' => Array(info(effect.name)['rules']) + BattleForms.rows(char, effect) },
                             'TempHP')
        source = Effects.source(effect.name, [], 'item' => instance_item(effect))
        context = Effects.context(char).merge('item' => instance_item(effect))

        rows.each do |row|
          held = Rules.contribute(row, source, context)

          next unless held && held[event]
          next unless Predicate.test(row['predicate'], Effects.options(char))
          next unless held['value'] > hp.temp_hp.to_i

          hp.update(:temp_hp => held['value'], :temp_hp_source => effect.id.to_s)
        end
      end

      def self.take_temp_hp(char, effect)
        hp = char.hp

        return unless hp && hp.temp_hp_source.to_s == effect.id.to_s

        hp.update(:temp_hp => 0, :temp_hp_source => nil)
      end

      # ------------------------------------------------------------------------------
      # Ending one

      # Ends an effect, and whatever it brought with it that goes when it goes.
      def self.remove(char, effect)
        name = effect.name

        take_temp_hp(char, effect)
        Auras.dispelled(char, effect)
        effect.delete

        # Another instance of the same effect still holds what it granted.
        return Ok.new(:state => name).tap { Paths.apply_all!(char) } if active?(char, name)

        Pf2e.release_grants(char, name)

        on(char).select { |other| other.granted_by == name }.each { |other| remove(char, other) }

        Paths.apply_all!(char)

        Ok.new(:state => name)
      end

      # Ends the effect a player names.
      def self.remove_named(char, term)
        found = find(term)

        return found if found.err?

        held = named_on(char, found.state)

        return Err.new(:not_on, 'pf2e.effect_not_on', 'effect' => found.state, 'name' => char.name) if held.empty?

        held.each { |effect| remove(char, effect) }

        Ok.new(:state => found.state)
      end

      # Whoever a command names - a character, or a combatant by its id - saying which names found nobody.
      # Whoever a command that changes someone names: combatants in the encounter here, as they stand in
      # it. Nothing changes a character outside an encounter, so without one there is nobody to name.
      def self.targets(client, enactor, names)
        encounter = Combatants.encounter_here(enactor)

        unless encounter
          client.emit_failure t('pf2e.no_encounter_here')
          return []
        end

        found, missing = Array(names).map { |term| [ term, Combatants.find(encounter, term) ] }
                                     .partition { |_term, result| result.ok? && result.state.holder }

        unless missing.empty?
          client.emit_ooc t('pf2e.bad_value_in_list', :items => 'names', :list => missing.map(&:first).join(', '))
        end

        found.map { |_term, result| result.state.holder }
      end

      # ------------------------------------------------------------------------------
      # What a roll spends

      # Foundry asks every rule a character has after any check they make (`statistic.ts:631`), and two
      # kinds end the effect carrying them there:
      #
      #   FlatModifier `removeAfterRoll`  true: the next roll, whatever it was
      #                                   `if-enabled`: a roll the bonus counted in - Guidance, Aid
      #                                   a predicate: a roll whose circumstances satisfy it
      #   RollTwice                       a roll it made twice, unless it says otherwise
      #                                   (`roll-twice.ts`)
      #
      # `options` are the check's own, with what the roll established added.
      def self.after_roll(char, check, options)
        counted = Array(check.breakdown['modifiers']).select { |one| one['enabled'] }
                                                   .map { |one| one['origin'].to_s }

        on(char).select { |effect|
          Array(info(effect.name)['rules']).any? { |row| spent?(row, effect, counted, check, options) }
        }.each { |effect| remove(char, effect) }
      end

      def self.spent?(row, effect, counted, check, options)
        case row['key'].to_s
        when 'FlatModifier'
          spent = row['removeAfterRoll']

          return true if spent == true
          return counted.include?(effect.id.to_s) if spent == 'if-enabled'

          spent.is_a?(Array) && Predicate.test(spent, options)
        when 'SubstituteRoll'
          spent = row['removeAfterRoll']
          used = check.respond_to?(:substituted) && check.substituted.to_s == (row['slug'] || Domains.slug(effect.name))

          return true if spent == true
          return used if spent == 'if-enabled'

          spent.is_a?(Array) && Predicate.test(spent, options)
        when 'RollTwice'
          row['removeAfterRoll'] != false && !check.roll_twice.nil? &&
            Domains.matches?(Rules.selectors_of(row), check.domains) &&
            Predicate.test(row['predicate'], options)
        else
          false
        end
      end

      # ------------------------------------------------------------------------------
      # Time

      def self.in_encounter(encounter)
        Pf2eEffect.find(:encounter_id => encounter.id).to_a
      end

      # Whose turn it is in an encounter, by name, or nil before the first turn.
      def self.current_turn(encounter)
        order = Combatants.rows(encounter)

        return nil if order.empty? || encounter.round.to_i.zero?

        order[(encounter.next_init.to_i - 1) % order.size]['name']
      end

      def self.rounds_long(effect)
        per = UNITS[effect.unit]['rounds']

        per ? per * effect.duration.to_i : nil
      end

      # A turn has begun or ended. Anything whose time is up ends, and each one ended is answered as an
      # event for whoever tells the room (`Pf2e::Turns`).
      def self.expire(encounter, event, participant, round)
        in_encounter(encounter).select { |effect| effect.holder && due?(effect, event, participant, round) }
                               .map { |effect| ended(effect) }
      end

      # A sustained effect ends at the end of the caster's next turn unless they sustain it, which is the
      # rule; its duration is only the most it can last. It ends at the end of their first turn in a round
      # after `sustained_round`.
      def self.unsustained(encounter, participant, round)
        in_encounter(encounter).select { |effect|
          effect.holder && effect.sustained && caster_of(effect, encounter) == participant &&
            round.to_i > effect.sustained_round.to_i
        }.map { |effect| ended(effect) }
      end

      # Who an effect in an encounter is the doing of, by their name in the order: whoever applied it if
      # they are in the fight, and otherwise whoever is under it, which is what a GM's `effect/add` leaves.
      def self.caster_of(effect, encounter)
        return effect.applied_by if applied_by_combatant?(effect, encounter)

        Combatants.all(encounter).find { |one| one.holder == effect.holder }&.label || effect.holder&.name
      end

      def self.applied_by_combatant?(effect, encounter)
        Combatants.rows(encounter).any? { |row| row['name'] == effect.applied_by }
      end

      # An effect's name as a player says it.
      def self.bare_name(effect)
        effect.name.sub(PREFIXES, '')
      end

      # The names a player's words could mean: the one they spell out, or else any that contain them.
      def self.matching(names, term)
        wanted = Domains.slug(term)
        exact = names.find { |name| Domains.slug(name) == wanted }

        exact ? [ exact ] : names.select { |name| Domains.slug(name).include?(wanted) }
      end

      # Keeps a sustained effect going through the caster's next turn.
      def self.sustain(effect, encounter)
        effect.update(:sustained_round => sustained_through(effect, encounter))

        Ok.new(:state => effect)
      end

      # The `sustained_round` that makes the caster's next turn the last: this round, or the one before it
      # if that turn is still to come this round.
      def self.sustained_through(effect, encounter)
        round = encounter.round.to_i

        turn_to_come?(caster_of(effect, encounter), encounter) ? round - 1 : round
      end

      def self.turn_to_come?(name, encounter)
        order = Combatants.rows(encounter)
        at = order.index { |row| row['name'] == name }

        !at.nil? && encounter.round.to_i.positive? && at > (encounter.next_init.to_i - 1) % order.size
      end

      def self.ended(effect)
        char = effect.holder
        name = effect.name

        remove(char, effect)

        Turns.event('pf2e.effect_ended', 'effect' => name, 'name' => char.name)
      end

      # Foundry counts a duration from the turn it began on, and ends it as that turn starts again - or as
      # it ends, where the effect says `turn-end` - once enough rounds have gone by.
      def self.due?(effect, event, participant, round)
        total = rounds_long(effect)

        return false unless total && effect.started_round

        expiry = effect.expiry.to_s.empty? ? 'turn-start' : effect.expiry.to_s
        owner = effect.started_turn || effect.holder&.name

        expiry == event && owner == participant && round.to_i >= effect.started_round.to_i + total
      end

      # The encounter is over. Anything that could not outlast it ends with it.
      def self.encounter_ended(encounter)
        in_encounter(encounter).reject { |effect| UNITS[effect.unit]['outlasts_encounter'] || !effect.holder }
                               .map { |effect| ended(effect) }
      end

      # A night's rest. Anything shorter than a day ends, and a day-long effect counts the night.
      def self.rested(char)
        on(char).map do |effect|
          unit = UNITS[effect.unit]

          next nil if unit['outlasts_rest'] && !unit['rests']

          left = effect.rests_left.to_i - 1

          if unit['rests'] && left.positive?
            effect.update(:rests_left => left)
            next nil
          end

          remove(char, effect)
          effect.name
        end.compact
      end

      # How long an effect has left, in words a player reads.
      def self.remaining(effect)
        unit = UNITS[effect.unit]

        return t('pf2e.effect_lasts_unlimited') if effect.unit == 'unlimited'
        return t('pf2e.effect_lasts_encounter') if effect.unit == 'encounter'
        return t('pf2e.effect_lasts_rests', :count => effect.rests_left.to_i) if unit['rests']
        return t('pf2e.effect_lasts_until_rest') unless effect.encounter && effect.started_round

        left = effect.started_round.to_i + rounds_long(effect) - effect.encounter.round.to_i

        # Its last round: it ends as this turn ends, or as the next one starts.
        if left <= 0
          return t(effect.expiry.to_s == 'turn-start' ? 'pf2e.effect_lasts_turn_start' : 'pf2e.effect_lasts_turn_end')
        end

        t('pf2e.effect_lasts_rounds', :count => left)
      end
    end
  end
end
