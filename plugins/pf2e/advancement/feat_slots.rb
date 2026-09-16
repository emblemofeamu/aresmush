module AresMUSH
  module Pf2e
    module Advancement

      # What gaining a feat does to the pool of things still to pick, as data.
      #
      # Pure: a feat's config plus a little context in, slot deltas out. It reads no character,
      # writes nothing, and calls nothing that does - so "what does taking this feat open up?"
      # is a question a spec can ask directly, which it could not be when the answer was an
      # array append buried three conditionals deep in a four-hundred-line method.
      #
      # `Advancement::FeatGain` is the imperative half that applies these alongside the effects
      # that genuinely need the live sheet - training a skill depends on what the character is
      # already trained in, and staging spellcasting depends on their magic object.
      module FeatSlots

        # One row per way a feat can change the pool. `when` decides whether it applies;
        # `deltas` returns what it contributes. Adding a way is adding a row.
        RULES = [
          # The slot being spent. `bucket` is the list it goes in - the slot the player is
          # filling when they typed advance/feat, or the feat's own first type when a choice
          # handed it over.
          {
            'name' => 'spend the slot',
            'when' => lambda { |ctx| ctx[:bucket] },
            'deltas' => lambda { |ctx| [ Slots.fill([ 'feats', ctx[:bucket] ], ctx[:feat]) ] }
          },
          # A feat that carries its own choice opens one, for the player to resolve with
          # advance/option. `opens_choice` is worked out by the caller, because whether a
          # choice opens depends on how many times the feat has been taken.
          {
            'name' => 'its own choice',
            'when' => lambda { |ctx| ctx[:opens_choice] },
            'deltas' => lambda { |ctx| [ Slots.open([ 'feat choice', ctx[:feat] ]) ] }
          },
          # Two more cantrips, for a spontaneous caster only.
          {
            'name' => 'cantrip expansion',
            'when' => lambda { |ctx| (ctx[:details]['grants'] || {})['cantrip_expansion'] && ctx[:spontaneous] },
            'deltas' => lambda { |ctx| [ Slots.open(ctx[:cantrip_path], :count => 2) ] }
          }
        ].freeze

        # The deltas gaining this feat implies.
        #
        #   bucket        the feat list it goes into, or nil to record it without spending a slot
        #   opens_choice  whether the feat's choice opens on this taking
        #   spontaneous   whether the character casts spontaneously
        #   cantrip_path  where their cantrip list lives
        def self.deltas(feat, details, bucket: nil, opens_choice: false, spontaneous: false, cantrip_path: nil)
          ctx = {
            :feat => feat,
            :details => details || {},
            :bucket => bucket,
            :opens_choice => opens_choice,
            :spontaneous => spontaneous,
            :cantrip_path => cantrip_path || [ 'repertoire', 'cantrip' ]
          }

          RULES.flat_map do |rule|
            next [] unless rule['when'].call(ctx)

            Array(rule['deltas'].call(ctx))
          end
        end

        # What taking this feat would open up, as slot label => how many. What a player asking
        # "what do I get for this?" is really asking.
        def self.openings(feat, details, **options)
          Slots.openings(deltas(feat, details, **options))
        end
      end
    end
  end
end
