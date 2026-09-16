module AresMUSH
  module Pf2e
    module Chargen

      # Ability boost assignment during chargen and advancement.
      #
      # Boosts are staged in state['boosts_working'] - a map of boost type to a list whose
      # entries are 'open', an assigned ability name, or a nested array of the only options
      # allowed in that slot. They become ledger grants when the stage is committed, not
      # here, so a player can reshuffle their picks without writing history.
      module Boosts

        def self.set(state, args)
          type = args['type']
          ability = args['ability']

          working = deep_copy(state['boosts_working'])
          types = working.keys

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'boost type', 'options' => types.join(", ")) unless types.include?(type)
          return Err.new(:info_not_locked, 'pf2e.lock_info_first') unless state['locks']['baseinfo']

          options = abilities_for(state)
          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'abilities', 'options' => options.join(", ")) unless options.include?(ability)

          slots = working[type]
          return Err.new(:no_duplicate_boosts, 'pf2e.no_duplicate_boosts') if slots.include?(ability)
          return Err.new(:no_free, 'pf2e.no_free', 'element' => type) if slots.is_a?(String)

          index = slot_for(slots, ability)
          return Err.new(:no_free, 'pf2e.no_free', 'element' => type) if index.nil?

          slots[index] = ability
          working[type] = slots

          Ok.new(:state => state.merge('boosts_working' => working))
            .with_message('pf2e.assignment_ok', 'type' => type, 'value' => ability)
        end

        def self.unset(state, args)
          type = args['type']
          ability = args['ability']

          working = deep_copy(state['boosts_working'])
          template = state['boosts'] || {}
          types = working.keys

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'boost type', 'options' => types.join(", ")) unless types.include?(type)
          return Err.new(:info_not_locked, 'pf2e.lock_info_first') unless state['locks']['baseinfo']

          slots = working[type]
          index = slots.is_a?(Array) ? slots.find_index(ability) : nil

          return Err.new(:boost_not_set, 'pf2e.boost_not_assigned', 'value' => ability) if index.nil?

          # A slot goes back to whatever the template had there - 'open', or the list of
          # abilities that slot allows. A template slot naming one ability outright was never
          # the player's to change.
          starting = (template[type] || [])[index]

          return Err.new(:element_locked, 'pf2e.element_cglocked', 'element' => 'boost') if starting.is_a?(String) && starting != 'open'

          slots[index] = starting
          working[type] = slots

          Ok.new(:state => state.merge('boosts_working' => working))
            .with_message('pf2e.reset_ok', 'element' => "#{type} boost", 'option' => ability)
        end

        # A constrained slot - one holding a list of permitted abilities - takes priority
        # over a plain open slot, so a free pick never eats a slot that only one ability can
        # fill.
        def self.slot_for(slots, ability)
          constrained = slots.select { |s| s.is_a?(Array) }.flatten

          if !constrained.empty?
            return slots.index { |s| s.is_a?(Array) && s.include?(ability) } if constrained.include?(ability)
          end

          slots.index('open')
        end

        def self.abilities_for(state)
          listed = state['abilities']

          return listed if listed.is_a?(Array) && !listed.empty?

          [ 'Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma' ]
        end

        def self.deep_copy(hash)
          (hash || {}).each_with_object({}) { |(k, v), h| h[k] = v.is_a?(Array) ? v.map { |e| e.is_a?(Array) ? e.dup : e } : v }
        end
      end
    end
  end
end
