module AresMUSH
  module Pf2e
    module Advancement

      # What a level hands out, and whether the character may take it.
      #
      # A level's entry comes from the class table, with the specialty's own table merged over
      # it where one exists - a Wizard's arcane school, a Champion's cause. The merge is
      # recursive because either side may nest, and lists are combined rather than replaced so
      # a specialty adds to what the class gives instead of quietly removing it.
      module Plan

        # Reasons a character cannot start an advancement, checked in this order. Each row is
        # a question about state plus the message to give when the answer is yes. In an
        # encounter is passed in by the shell, because only the live game knows.
        BLOCKERS = [
          { 'when' => lambda { |state, _args| state['advancing'] }, 'key' => 'pf2e.already_advancing' },
          { 'when' => lambda { |state, _args| state['xp'].to_i < Pf2e::ADVANCEMENT_XP_COST }, 'key' => 'pf2e.not_enough_xp' },
          { 'when' => lambda { |_state, args| args['in_encounter'] }, 'key' => 'pf2e.already_in_encounter' },
          { 'when' => lambda { |state, _args| state['level'].to_i == state['config'].read('pf2e', 'max_level').to_i }, 'key' => 'pf2e.already_max_level' }
        ].freeze

        # nil when they may advance, an Err naming the reason when they may not.
        def self.can_advance(state, args = {})
          blocker = BLOCKERS.find { |rule| rule['when'].call(state, args) }

          return nil unless blocker

          Err.new(:cannot_advance, blocker['key'])
        end

        # The merged advance entry for the level this character is about to gain.
        def self.for_level(state, level)
          charclass = state['base_info']['charclass']

          return nil if charclass.blank?

          from_class = (state['config'].read('pf2e_class', charclass, 'advance') || {})[level]
          from_specialty = specialty_entry(state, charclass, level)

          merge(from_class, from_specialty)
        end

        def self.specialty_entry(state, charclass, level)
          specialize = state['base_info']['specialize']

          return nil if specialize.blank?

          table = (state['config'].read('pf2e_specialty', charclass, specialize) || {})['advance']

          table && table[level]
        end

        # Deep merge: hashes recurse, lists combine, anything else the specialty wins.
        def self.merge(base, extra)
          return extra if base.nil?
          return base if extra.nil?
          return extra unless base.is_a?(Hash) && extra.is_a?(Hash)

          base.merge(extra) do |_key, from_base, from_extra|
            if from_base.is_a?(Hash) && from_extra.is_a?(Hash)
              merge(from_base, from_extra)
            elsif from_base.is_a?(Array) && from_extra.is_a?(Array)
              (from_base + from_extra).uniq
            else
              from_extra
            end
          end
        end
      end
    end
  end
end
