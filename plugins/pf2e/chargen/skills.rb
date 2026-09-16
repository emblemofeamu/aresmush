module AresMUSH
  module Pf2e
    module Chargen

      # Skill training picks, for both chargen and advancement.
      #
      # A pick spends a slot staged in state['to_assign'] and grants the training. The awkward
      # case the rules require: a background or class skill the character already has is not
      # wasted - it converts into an extra free skill pick, flagged so taking it back hands
      # the free pick in rather than untraining a skill they hold from elsewhere.
      module Skills

        # Player-facing type to the to_assign key it spends.
        TYPES = {
          'background' => 'bgskill',
          'free' => 'open skills',
          'bgchoice' => 'bg skill choice',
          'classchoice' => 'class skill choice',
          'specialtychoice' => 'specialty skill choice'
        }.freeze

        CHOICE_TYPES = [ 'bg skill choice', 'class skill choice', 'specialty skill choice' ].freeze

        def self.train(state, args)
          type = args['type']
          skill = args['skill']

          key = TYPES[type]

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'skill type', 'options' => TYPES.keys.sort.join(", ")) unless key
          return Err.new(:bad_skill, 'pf2e.bad_option_condensedskill') unless known_skill?(state, skill)

          to_assign = deep_copy(state['to_assign'])
          slots = to_assign[key]

          return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'skill') if slots.nil?

          trained = trained?(state, skill)
          duplicate = trained && CHOICE_TYPES.include?(key)

          return Err.new(:already_has_skill, 'pf2e.already_has_skill') if trained && !duplicate

          updated = spend_slot(slots, key, skill, duplicate)

          return updated if updated.is_a?(Err)

          to_assign[key] = updated

          # The duplicate converts into a free skill the player picks later.
          if duplicate
            open_skills = Array(to_assign['open skills']).dup
            open_skills << 'open'
            to_assign['open skills'] = open_skills
          end

          outcome = Ok.new(:state => state.merge('to_assign' => to_assign))
          outcome = outcome.with_grant('raise_skill', { 'skill' => skill, 'to' => 'trained' }, { 'effective_level' => 1 }) unless trained

          if duplicate
            outcome.with_message('pf2e.skill_choice_duplicate', 'item' => skill)
          else
            outcome.with_message('pf2e.add_ok', 'item' => skill, 'list' => 'skills')
          end
        end

        def self.untrain(state, args)
          type = args['type']
          skill = args['skill']

          key = TYPES[type]

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'skill type', 'options' => TYPES.keys.sort.join(", ")) unless key
          return Err.new(:bad_skill, 'pf2e.bad_option', 'element' => 'skill name') unless known_skill?(state, skill)

          to_assign = deep_copy(state['to_assign'])
          slots = to_assign[key]

          return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'skill') if slots.nil?

          duplicate = slots.is_a?(Hash) && slots['duplicate'] && slots['selected'] == skill

          return Err.new(:does_not_have, 'pf2e.does_not_have', 'item' => 'skill') if !duplicate && !trained?(state, skill)
          return Err.new(:element_locked, 'pf2e.element_cglocked', 'element' => 'skill') if !duplicate && locked?(state, skill)

          case key
          when 'bgskill'
            to_assign[key] = slots
          when 'open skills'
            index = Array(slots).index(skill)

            return Err.new(:not_in_list, 'pf2e.not_in_list', 'option' => skill) if index.nil?

            slots = slots.dup
            slots[index] = 'open'
            to_assign[key] = slots
          else
            return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'skill') unless slots.is_a?(Hash)
            return Err.new(:not_in_list, 'pf2e.not_in_list', 'option' => skill) unless slots['selected'] == skill

            if duplicate
              open_skills = Array(to_assign['open skills']).dup
              index = open_skills.index('open')

              # The free skill the duplicate bought has already been used on something else,
              # so there is nothing to hand back.
              return Err.new(:free_skill_spent, 'pf2e.free_skill_spent', 'item' => skill) if index.nil?

              open_skills.delete_at(index)
              to_assign['open skills'] = open_skills
              slots = slots.reject { |k, _v| k == 'duplicate' }
            end

            slots = slots.merge('selected' => 'open')
            to_assign[key] = slots
          end

          outcome = Ok.new(:state => state.merge('to_assign' => to_assign))
          outcome = outcome.with_revocation('raise_skill', 'skill' => skill) unless duplicate

          outcome.with_message('pf2e.reset_ok', 'option' => skill, 'element' => 'skill')
        end

        # ------------------------------------------------------------------------------

        def self.spend_slot(slots, key, skill, duplicate)
          case key
          when 'bgskill'
            matches = Array(slots).select { |s| s == skill }

            return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'skill option', 'options' => Array(slots).sort.join(", ")) if matches.empty?
            return Err.new(:ambiguous, 'pf2e.ambiguous_target') if matches.size > 1

            matches.first
          when 'open skills'
            index = Array(slots).index('open')

            return Err.new(:no_free, 'pf2e.no_free', 'element' => 'free') if index.nil?

            filled = slots.dup
            filled[index] = skill
            filled
          else
            return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'skill') unless slots.is_a?(Hash)

            selected = slots['selected']

            return Err.new(:no_free, 'pf2e.no_free', 'element' => 'choice') if selected && selected != 'open'

            options = Array(slots['options'])

            return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'skill option', 'options' => options.sort.join(", ")) unless options.include?(skill)

            updated = slots.merge('selected' => skill)
            duplicate ? updated.merge('duplicate' => true) : updated.reject { |k, _v| k == 'duplicate' }
          end
        end

        def self.known_skill?(state, skill)
          (state['config'].read('pf2e_skills') || {}).key?(skill)
        end

        def self.trained?(state, skill)
          rank = (state['sheet']['skills'] || {})[skill] || (state['sheet']['lores'] || {})[skill]

          !rank.nil? && rank.to_s != 'untrained'
        end

        # Skills locked in by a committed chargen stage are not the player's to drop.
        def self.locked?(state, skill)
          Array(state['cg_skills']).include?(skill)
        end

        def self.deep_copy(hash)
          (hash || {}).each_with_object({}) do |(k, v), h|
            h[k] = case v
                   when Array then v.dup
                   when Hash then v.dup
                   else v
                   end
          end
        end
      end
    end
  end
end
