module AresMUSH
  module Pf2e
    module Advancement

      # Abandoning an advancement.
      #
      # Under the draft model this is almost nothing: the picks live in pf2_advancement and
      # pf2_to_assign, so throwing those away throws away the level-up. What is left is the
      # handful of things a pick writes to the sheet before the level is committed - the
      # archetype slots, granted archetype features, a repertoire swap - which have to be put
      # back by hand. Each of those is a place the draft leaks, and a candidate for moving
      # into the draft proper.
      module Lifecycle

        def self.reset(state, _args = {})
          Ok.new(:state => state.merge(
              'to_assign' => {},
              'advancement' => {},
              'archetypes' => Archetypes.undo_advancement(state)
            ))
            .with_message('pf2e.adv_reset_ok')
        end

        # Archetype features this advancement granted, which the shell removes from the sheet
        # because features are not part of the state a core may write.
        def self.granted_features(state)
          Array(state['advancement']['archetype_features'])
        end

        # The repertoire swap this advancement made, as { 'level', 'old', 'new' }, or nil.
        def self.repertoire_swap(state)
          state['advancement']['repertoire_swap']
        end
      end
    end
  end
end
