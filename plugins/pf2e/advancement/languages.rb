module AresMUSH
  module Pf2e
    module Advancement

      # Learning a language during a level-up.
      #
      # The slot lives in to_assign['open languages'] as an 'open' marker, and the pick is
      # recorded in the advancement draft rather than on the sheet: it becomes a grant when
      # the level is committed, attributed to the level being gained.
      module Languages

        SLOT = 'open languages'.freeze

        def self.pick(state, args)
          language = args['language'].to_s

          options = available(state)

          chosen = options.find { |l| l.casecmp?(language) }

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'language', 'options' => options.sort.join(", ")) unless chosen

          slots = Array(state['to_assign'][SLOT])

          return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'language') if state['to_assign'][SLOT].nil?

          return Err.new(:already_knows, 'pf2e.already_knows_language', 'language' => chosen) if known?(state, chosen)

          index = slots.index { |l| l.to_s.casecmp?('open') }

          return Err.new(:no_free, 'pf2e.no_free', 'element' => SLOT) if index.nil?

          filled = slots.dup
          filled[index] = chosen

          picked = Array(state['advancement']['languages']) + [ chosen ]

          Ok.new(:state => state.merge(
              'to_assign' => state['to_assign'].merge(SLOT => filled),
              'advancement' => state['advancement'].merge('languages' => picked.uniq { |l| l.to_s.downcase })
            ))
            .with_message('pf2e.add_ok', 'item' => chosen, 'list' => 'languages')
        end

        # Every language in a group the game lets a character select from.
        def self.available(state)
          groups = state['config'].read('pf2e_languages') || {}

          Array(state['config'].read('pf2e', 'can_select_language')).flat_map do |key|
            (groups[key] || {}).keys
          end
        end

        # Held already, or picked earlier in this same advancement.
        def self.known?(state, language)
          held = Array(state['sheet']['languages']) + Array(state['lang']) + Array(state['advancement']['languages'])

          held.any? { |l| l.to_s.casecmp?(language) }
        end
      end
    end
  end
end
