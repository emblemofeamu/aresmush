module AresMUSH
  module Pf2e
    module Chargen

      # Language picks.
      #
      # A pick takes one of the character's open language slots (staged in
      # state['to_assign']['open languages']) and grants the language. Taking it back frees
      # the slot and revokes that grant - the ledger keeps the row, marked reverted, so the
      # history of a player changing their mind is still there.
      module Languages

        def self.learn(state, args)
          language = args['language']
          slots = Array(state['to_assign']['open languages']).dup

          available = selectable(state)

          unless available.any? { |l| l.casecmp?(language.to_s) }
            return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'language', 'options' => available.sort.join(", "))
          end

          return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'language') if state['to_assign']['open languages'].nil?

          canonical = available.find { |l| l.casecmp?(language.to_s) }

          return Err.new(:already_has, 'pf2e.already_has', 'item' => 'language') if known?(state, canonical)

          index = slots.index('open')

          return Err.new(:no_free, 'pf2e.no_free', 'element' => 'open languages') if index.nil?

          slots[index] = canonical
          to_assign = state['to_assign'].merge('open languages' => slots)

          Ok.new(:state => state.merge('to_assign' => to_assign))
            .with_grant('add_language', { 'language' => canonical }, { 'effective_level' => 1 })
            .with_message('pf2e.add_ok', 'item' => canonical, 'list' => 'languages')
        end

        def self.forget(state, args)
          language = args['language']

          return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'language') if state['to_assign']['open languages'].nil?

          slots = Array(state['to_assign']['open languages']).dup
          index = slots.index { |s| s.is_a?(String) && s.casecmp?(language.to_s) }

          # A language from an ancestry, heritage or background is not in the player's slots
          # and is not theirs to drop.
          return Err.new(:not_in_list, 'pf2e.not_in_list', 'option' => language) if index.nil?

          canonical = slots[index]
          slots[index] = 'open'
          to_assign = state['to_assign'].merge('open languages' => slots)

          Ok.new(:state => state.merge('to_assign' => to_assign))
            .with_revocation('add_language', 'language' => canonical)
            .with_message('pf2e.reset_ok', 'option' => canonical, 'element' => 'language')
        end

        # The languages a player may choose: every language in the rarity buckets listed by
        # pf2e.can_select_language, which is why rare and secret ones never appear.
        def self.selectable(state)
          config = state['config']
          buckets = Array(config.read('pf2e', 'can_select_language'))

          buckets.flat_map { |bucket| (config.read('pf2e_languages', bucket) || {}).keys }
        end

        def self.known?(state, language)
          Array(state['sheet']['languages']).any? { |l| l.to_s.casecmp?(language.to_s) }
        end
      end
    end
  end
end
