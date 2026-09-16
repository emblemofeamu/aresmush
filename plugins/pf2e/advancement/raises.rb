module AresMUSH
  module Pf2e
    module Advancement

      # Spending the raise slots a level hands out: ability boosts, a skill increase, or a
      # skill increase restricted to a named list.
      #
      # Each type is a row in TYPES saying which to_assign key it spends and which function
      # spends it. Everything lands in the advancement draft; nothing touches the sheet until
      # the level is committed.
      module Raises

        BOOSTS_PER_LEVEL = 4

        # A skill slot can be marked open in four ways, and which of them a given pick may
        # spend depends on whether the skill is a Lore and whether the character is untrained
        # in it. Listed most specific first: the first token this pick is allowed to spend is
        # the one it takes.
        SLOT_PREFERENCE = {
          # [ lore?, untrained? ] => the tokens it may spend, in order
          [ true, true ] => [ 'open lore untrained', 'open lore', 'open untrained', 'open' ],
          [ true, false ] => [ 'open lore', 'open' ],
          [ false, true ] => [ 'open untrained', 'open' ],
          [ false, false ] => [ 'open' ]
        }.freeze

        def self.set(state, args)
          type = args['type'].to_s.downcase
          spec = TYPES[type]

          return Err.new(:bad_option, 'pf2e.adv_not_an_option') unless spec

          key = "raise #{type}"

          return Err.new(:bad_option, 'pf2e.adv_not_an_option') if state['to_assign'][key].nil?

          spec['spend'].call(state, key, args['value'].to_s)
        end

        # ------------------------------------------------------------------------------
        # Ability boosts: four at once, all different, none already taken this level
        # ------------------------------------------------------------------------------

        def self.boost(state, key, value)
          wanted = value.split(/[\s,]+/).reject(&:empty?)

          return Err.new(:boost_count, 'pf2e.adv_ability_boost_count') unless wanted.size == BOOSTS_PER_LEVEL
          return Err.new(:boost_unique, 'pf2e.adv_ability_boost_unique') unless wanted.uniq { |a| a.to_s.upcase }.size == wanted.size

          names = wanted.map { |w| Array(state['abilities']).find { |a| a.to_s.casecmp?(w) } }

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'ability', 'options' => Array(state['abilities']).join(", ")) unless names.all?

          slots = Array(state['to_assign'][key])

          return Err.new(:no_free, 'pf2e.no_free', 'element' => 'ability boosts') if slots.count('open') < BOOSTS_PER_LEVEL

          taken = slots.reject { |s| s == 'open' }

          return Err.new(:boost_unique, 'pf2e.adv_ability_boost_unique') if taken.any? { |t| names.any? { |n| n.to_s.casecmp?(t.to_s) } }

          filled = (taken + names).sort

          to_assign = state['to_assign'].merge(key => filled)
          advancement = state['advancement'].merge(key => filled)

          outcome = Ok.new(:state => state.merge('to_assign' => to_assign, 'advancement' => advancement))
            .with_message('pf2e.adv_raise_selected', 'name' => names.join(", "))

          intelligence_bonus(outcome, names)
        end

        # Raising Intelligence far enough to move the modifier hands out a skill and a
        # language, which are themselves slots to spend.
        def self.intelligence_bonus(outcome, names)
          state = outcome.state

          return outcome unless names.any? { |n| n.to_s.casecmp?('Intelligence') }

          score = (state['ability_scores'] || {})['Intelligence'].to_i
          raised = score + (score < 18 ? 2 : 1)

          return outcome unless Pf2eAbilities.abilmod(raised) > Pf2eAbilities.abilmod(score)

          to_assign = state['to_assign'].dup
          advancement = state['advancement'].dup

          # Shared with the legacy path on purpose: the token vocabulary belongs in one place.
          Pf2e.add_open_skill_slot(to_assign, advancement, false, true)
          to_assign['open languages'] = Array(to_assign['open languages']) + [ 'open' ]

          Ok.new(
            :state => state.merge('to_assign' => to_assign, 'advancement' => advancement),
            :grants => outcome.grants,
            :messages => outcome.messages + [ { 'key' => 'pf2e.adv_int_mod_bonus', 'args' => {}, 'type' => 'ooc' } ],
            :revocations => outcome.revocations
          )
        end

        # ------------------------------------------------------------------------------
        # Skill increases
        # ------------------------------------------------------------------------------

        def self.increase(state, key, value)
          skills = (state['config'].read('pf2e_skills') || {}).keys
          skill = skills.find { |s| s.to_s.casecmp?(value) }

          return Err.new(:bad_skill, 'pf2e.bad_skill', 'name' => value) unless skill

          spend_skill_slot(state, key, skill)
        end

        # A slot that came with its own list of allowed skills.
        def self.increase_choice(state, key, value)
          allowed = Array(state['to_assign'][key])
          skill = allowed.find { |s| s.to_s.casecmp?(value) }

          return Err.new(:bad_skill_choice, 'pf2e.bad_skill_choice', 'options' => allowed.join(", ")) unless skill

          level_failure = too_low?(state, skill)
          return level_failure if level_failure

          staged(state, key, skill)
        end

        def self.spend_skill_slot(state, key, skill)
          level_failure = too_low?(state, skill)
          return level_failure if level_failure

          slots = Array(state['to_assign'][key])
          open = slots.select { |s| Pf2e.open_skill_token?(s) }

          # Nothing open means the slot holds an earlier pick rather than markers, and picking
          # again replaces it - which is how the command has always behaved.
          if open.empty?
            return staged(state, key, skill)
          end

          untrained = current_prof(state, skill).to_s.casecmp?('untrained')

          # Which markers this skill is allowed to spend, most specific first. Slots.fill takes
          # the first of them that is actually open.
          allowed = SLOT_PREFERENCE[[ Pf2e.lore_skill?(skill), untrained ]]
          filled = Slots.apply(state['to_assign'], [ Slots.fill(key, skill, :tokens => allowed) ])

          if filled.is_a?(Err)
            # Say *why* it could not be spent: a slot reserved for untrained skills reads
            # differently from one reserved for lores.
            blocked = open.any? { |s| Pf2e.untrained_only_token?(s) } && !untrained

            return Err.new(:untrained_only, 'pf2e.adv_untrained_only') if blocked

            return Err.new(:lore_required, 'pf2e.adv_lore_required')
          end

          Ok.new(:state => state.merge(
              'to_assign' => filled,
              'advancement' => state['advancement'].merge(key => filled[key])
            ))
            .with_message('pf2e.adv_raise_selected', 'name' => skill)
        end

        # A re-pick, replacing what was chosen before.
        def self.staged(state, key, value)
          Ok.new(:state => state.merge(
              'to_assign' => state['to_assign'].merge(key => value),
              'advancement' => state['advancement'].merge(key => value)
            ))
            .with_message('pf2e.adv_raise_selected', 'name' => value)
        end

        # ------------------------------------------------------------------------------
        # Proficiency questions, answered from the sheet rather than from Redis
        # ------------------------------------------------------------------------------

        def self.current_prof(state, skill)
          sheet = state['sheet']
          held = (sheet['skills'] || {}).merge(sheet['lores'] || {})

          key = held.keys.find { |k| k.to_s.casecmp?(skill.to_s) }

          key ? held[key] : 'untrained'
        end

        def self.next_prof(state, skill)
          progression = Array(state['config'].read('pf2e', 'prof_progression'))
          index = progression.index(current_prof(state, skill).to_s)

          index ? progression[index + 1] : nil
        end

        # The level a proficiency may first be reached at, per pf2e.min_level_for_prof.
        def self.min_level(state, prof)
          progression = Array(state['config'].read('pf2e', 'prof_progression'))
          index = progression.index(prof)

          return nil unless index

          Array(state['config'].read('pf2e', 'min_level_for_prof'))[index]
        end

        # The raise applies at the level being gained, which is one past where they are now.
        def self.too_low?(state, skill)
          required = min_level(state, next_prof(state, skill)).to_i

          return nil if state['level'].to_i + 1 >= required

          Err.new(:not_minimum_level, 'pf2e.not_minimum_level', 'level' => required)
        end

        TYPES = {
          'ability' => { 'spend' => lambda { |state, key, value| Raises.boost(state, key, value) } },
          'skill' => { 'spend' => lambda { |state, key, value| Raises.increase(state, key, value) } },
          'skill choice' => { 'spend' => lambda { |state, key, value| Raises.increase_choice(state, key, value) } }
        }.freeze
      end
    end
  end
end
