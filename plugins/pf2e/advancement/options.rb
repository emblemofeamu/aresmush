module AresMUSH
  module Pf2e
    module Advancement

      # Choosing the option a class feature asks for: a Monk's Path to Perfection save, a
      # Champion's Blessing of the Devoted, a Fighter's weapon group.
      #
      # The pick lands in the advancement draft. What makes a pick legal is either the option
      # list the level offered, or - for a feature that is one of a family - what the earlier
      # members of that family already took.
      module Options

        # Where a pending feature list may be found, oldest key first.
        SLOTS = [ 'class option', 'charclass', 'charclass option' ].freeze

        # Class feature choices whose legality depends on earlier picks in the same family.
        # Each row names the record the family keeps and whether this pick has to be one the
        # character does not hold yet, or one they already do.
        #
        # Monk, PF2e Player Core: Path to Perfection raises a save to master, Second Path to
        # Perfection raises "a different saving throw", and Third Path to Perfection raises
        # "one of the saving throws you selected" for the earlier two, to legendary.
        FAMILIES = {
          'Path to Perfection' => { 'record' => 'Path to Perfection', 'requires' => 'unheld' },
          'Second Path to Perfection' => { 'record' => 'Path to Perfection', 'requires' => 'unheld' },
          'Third Path to Perfection' => { 'record' => 'Path to Perfection', 'requires' => 'held' }
        }.freeze

        def self.choose(state, args)
          feature_key = args['feature'].to_s

          slot = SLOTS.find { |key| state['to_assign'][key].is_a?(Hash) }

          return Err.new(:not_an_option, 'pf2e.adv_not_an_option') unless slot

          pending = state['to_assign'][slot]
          feature = pending.keys.find { |f| f.to_s.casecmp?(feature_key) }

          return Err.new(:not_an_option, 'pf2e.adv_not_an_option') unless feature

          options = option_list(pending[feature])
          value = args['value'].to_s

          chosen = options.find { |o| o.to_s.casecmp?(value) }

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => feature, 'options' => options.join(", ")) unless chosen
          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => feature, 'options' => options.join(", ")) unless allowed?(state, feature, chosen)

          filled = pending.merge(feature => chosen)

          Ok.new(:state => state.merge(
              'to_assign' => state['to_assign'].merge(slot => filled),
              'advancement' => state['advancement'].merge('charclass_feature option' => filled)
            ))
            .with_message('pf2e.adv_option_selected', 'option' => chosen, 'feature' => feature)
        end

        # What a feature's pending entry offers. Three shapes, read the way the command has
        # always read them: a hash carrying an options list, a hash whose keys *are* the
        # options, or a plain list whose entries may themselves be [label, info] pairs.
        def self.option_list(data)
          if data.is_a?(Hash) && data.key?('options')
            Array(data['options'])
          elsif data.is_a?(Hash)
            data.keys
          else
            Array(data).map { |opt| opt.is_a?(Array) ? opt.first : opt }
          end
        end

        # A feature outside any family has no constraint beyond its own option list.
        def self.allowed?(state, feature, option)
          family = FAMILIES[feature.to_s]

          return true unless family

          held = Array((state['saves'] || {})[family['record']])

          # Case-insensitive on purpose: the option arrives spelled the way config spells it,
          # while the record holds whatever an earlier pick stored.
          already = held.any? { |s| s.to_s.casecmp?(option.to_s) }

          family['requires'] == 'held' ? already : !already
        end
      end
    end
  end
end
