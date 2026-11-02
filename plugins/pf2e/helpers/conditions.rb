module AresMUSH
  module Pf2e

    def self.get_condition_value(char, condition)
      # Returns 0 if that condition does not have a value, nil if that condition is not present.
      c = held_conditions(char)[canonical_condition(condition)]
      return nil if !c

      v = c['value']
      return 0 if !v

      return v
    end

    # What a condition is worth to arithmetic: its value, or zero when it is absent or carries none.
    #
    # get_condition_value tells absent from valueless, which a display needs. Anything doing sums
    # wants a number - the dying rules add and subtract three conditions at once, and one absent
    # condition there made it `1 + nil`.
    def self.condition_level(char, condition)
      held = held_conditions(char)[canonical_condition(condition)]

      held ? held['value'].to_i : 0
    end

    # The catalogue's own spelling of a condition, whatever the caller typed. `Off-Guard` capitalised is
    # `Off-guard`, and a grant naming `Off-Guard` has to find the one a player set.
    def self.canonical_condition(condition)
      wanted = Domains.slug(condition)

      (Global.read_config('pf2e_conditions') || {}).keys.find { |name| Domains.slug(name) == wanted } ||
        condition.to_s
    end

    ENCUMBERED = 'Encumbered'.freeze
    CARRYING_TOO_MUCH = 'Bulk'.freeze

    # Every condition a character has: the ones set on them, and the ones those bring with them.
    #
    #   { 'Off-Guard' => { 'value' => nil, 'granted_by' => 'Grabbed', 'derived' => true }, … }
    #
    # A derived one is never stored - it exists because its granter does, and goes when it goes - so it
    # is worked out here each time rather than written anywhere. A condition held in its own right
    # outranks one derived: being off-guard because someone flanked you does not stop when you are
    # released from a grab.
    def self.held_conditions(char)
      held = (char.pf2_conditions || {}).each_with_object({}) do |(name, info), out|
        info = {} unless info.is_a?(Hash)

        out[name] = { 'value' => info['value'], 'granted_by' => info['granted_by'], 'derived' => false }
        # Who holds them, where the condition is a hold (`Holding`).
        out[name]['by'] = info['by'] if info['by']
      end

      # What the character's effects bring with them for as long as they last: an effect that knocks you
      # prone, a stance that makes you off-guard. And what a creature's stat block makes it for good.
      (ActiveEffects.derived_conditions(char) + Actors.of(char).permanent_conditions).each do |grant, effect|
        name = canonical_condition(grant['name'])

        next if held.key?(name)

        held[name] = { 'value' => grant['value'] || default_condition_value(name),
                       'granted_by' => effect, 'derived' => true }
      end

      # What they carry, past what they can carry easily. It goes when the bulk does.
      if !held.key?(ENCUMBERED) && Actors.of(char).carries_items? && Pf2egear::Bulk.encumbered?(char)
        held[ENCUMBERED] = { 'value' => nil, 'granted_by' => CARRYING_TOO_MUCH, 'derived' => true }
      end

      derive_conditions(held, held.keys).to_h do |name, one|
        # What an effect does to a condition's value while it lasts.
        [ name, one['value'] ? one.merge('value' => Alterations.condition(char, name, one['value'])) : one ]
      end
    end

    # Whether what granted a condition still holds: a condition set on the character, or an effect they
    # are under.
    def self.granter_holds?(char, granter)
      (char.pf2_conditions || {}).key?(granter) || ActiveEffects.active?(char, granter)
    end

    # The grants a set of granters bring, followed to the end: Unconscious brings Prone, and Prone
    # brings Off-Guard.
    def self.derive_conditions(held, granters)
      pending = granters.dup
      seen = {}

      until pending.empty?
        granter = pending.shift

        next if seen[granter]

        seen[granter] = true

        condition_grants(granter).select { |grant| grant['derived'] }.each do |grant|
          name = canonical_condition(grant['name'])

          next if held.key?(name)
          # Conditions on conditions are unconditional in their data; a grant asking about the
          # character would need the character's facts, which are built from this list.
          next unless grant['predicate'].nil?

          held[name] = { 'value' => grant['value'] || default_condition_value(name),
                         'granted_by' => granter, 'derived' => true }
          pending << name
        end
      end

      held
    end

    def self.condition_grants(name)
      rules = Global.read_config('pf2e_conditions', canonical_condition(name), 'rules')

      Grants.of(rules).select { |grant| grant['catalogue'] == 'conditions' }
    end

    # A valued condition granted without a value is at one, which is what Foundry's condition items
    # carry until something changes them.
    def self.default_condition_value(name)
      Global.read_config('pf2e_conditions', name, 'value') ? 1 : nil
    end

    # Each condition as a sheet shows it: its value if it has one, and what brought it if something did.
    # `Frightened 2`, `Off-Guard (Grabbed)`.
    def self.condition_labels(char, colored = true)
      colors = colored ? (Global.read_config('pf2e', 'condition_colors') || {}) : {}

      return [ DEAD ] if dead?(char)

      held_conditions(char).sort.map do |name, held|
        value = held['value'] ? " #{held['value']}" : ''
        from = held['granted_by'] ? " (#{held['granted_by']})" : ''
        from = " (by #{held['by']})" if held['by']

        "#{colors[name]}#{name}#{value}#{colored ? '%xn' : ''}#{from}"
      end
    end

    # Whether they are immune to a condition, which then never lands on them however it came.
    def self.immune_to?(char, condition)
      IWR.immune_to_condition?(IWR.for(char), condition)
    end

    # Death is not a condition the catalogue holds: it is said of a character, and is all they are
    # listed as under. `condition/set <who>=dead` says it, and `dead/0` takes it back.
    DEAD = 'Dead'.freeze

    def self.dead?(char)
      char.respond_to?(:pf2_is_dead) && char.pf2_is_dead ? true : false
    end

    # Sets a condition, and whatever it brings with it that is stored in its own right - Dying makes you
    # unconscious, and unconsciousness puts you on the ground. `granted` records how it came to be
    # there when another condition brought it (see `Pf2e::Grants::FIELDS`).
    #
    # A value of nothing clears it, the same as `remove_condition`, and answers the same way.
    def self.set_condition(char, condition, value = nil, granted = {})
      condition = canonical_condition(condition)

      return remove_condition(char, condition) if value && value.zero?
      return Err.new(:immune, 'pf2e.condition_immune', 'name' => char.name, 'condition' => condition) if immune_to?(char, condition)

      list = char.pf2_conditions || {}
      cv = list[condition] || {}
      before = list.key?(condition) ? cv['value'] : nil
      max_before = HitPointLoss.takes?(Global.read_config('pf2e_conditions', condition, 'rules')) ? HitPointLoss.max_hp(char) : nil

      cv['value'] = value if value
      # Held without a value, it still has to be held as something.
      cv['status'] = true
      cv.merge!(granted.slice(*Grants::FIELDS)) if granted.any? && !list.key?(condition)

      list[condition] = cv
      char.update(pf2_conditions: list)

      # Drained costs hit points as it arrives and more as it worsens.
      HitPointLoss.condition_changed(char, condition, before, cv['value'], max_before)
      grant_stored_conditions(char, condition)

      # A condition may write as well as modify - Confused cannot flank - and what it writes is derived,
      # so it is rebuilt once the whole chain of grants has landed.
      Paths.apply_all!(char) if granted.empty?

      Ok.new(:state => char.pf2_conditions)
    end

    def self.grant_stored_conditions(char, granter)
      condition_grants(granter).reject { |grant| grant['derived'] }.each do |grant|
        name = canonical_condition(grant['name'])

        # A condition already held is not granted again, and is not claimed by this granter either:
        # someone who was prone before they fell unconscious is not stood up by waking.
        next if (char.pf2_conditions || {}).key?(name)
        next unless grant['predicate'].nil? || Predicate.test(grant['predicate'], Effects.facts(char))

        set_condition(char, name, grant['value'] || default_condition_value(name),
                      'granted_by' => granter,
                      'when_granter_goes' => grant['when_granter_goes'],
                      'restricted' => grant['restricted'])
      end
    end

    # Takes a condition away, and with it whatever it granted that goes when it goes. A condition its
    # granter restricts cannot be taken away while the granter holds: clear Dying, and Unconscious goes
    # with it.
    def self.remove_condition(char, condition, forced = false)
      condition = canonical_condition(condition)
      list = char.pf2_conditions || {}
      held = list[condition]

      return Ok.new(:state => list) unless held

      granter = held.is_a?(Hash) ? held['granted_by'] : nil

      if !forced && granter && held['restricted'] && granter_holds?(char, granter)
        return Err.new(:restricted, 'pf2e.condition_restricted', 'condition' => condition,
                       'granter' => granter)
      end

      list.delete(condition)
      char.update(pf2_conditions: list)

      release_grants(char, condition)

      Paths.apply_all!(char) unless forced

      Ok.new(:state => char.pf2_conditions)
    end

    # What becomes of the conditions this one granted, now that it has gone.
    def self.release_grants(char, granter)
      granted = (char.pf2_conditions || {}).select { |_name, info|
        info.is_a?(Hash) && info['granted_by'] == granter
      }

      granted.each do |name, info|
        if info['when_granter_goes'] == 'detach'
          list = char.pf2_conditions
          list[name] = info.reject { |field, _| Grants::FIELDS.include?(field) }
          char.update(pf2_conditions: list)
        else
          remove_condition(char, name, true)
        end
      end
    end

  end
end
