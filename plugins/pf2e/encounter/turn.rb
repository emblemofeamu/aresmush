module AresMUSH
  module Pf2e
    module Encounters

      # Whose turn it is, and what moving through the order does to the round.
      #
      # The arithmetic was written twice, forwards in `encounter/next` and backwards in
      # `encounter/prev`, and the backwards copy was wrong in two ways: it read a round counter it
      # had never assigned, and it indexed one past the end of the order. Both raised
      # `NoMethodError`, so backing up into the previous round could not work.
      #
      # Pure: a list size, a position and a round number in, the new position and round out.
      module Turn

        # One row per direction. `step` moves the position; `wraps` says the move crosses a round
        # boundary, which is where the round counter changes.
        DIRECTIONS = {
          'next' => {
            'label' => 'pf2e.init_advances',
            'wraps' => lambda { |ctx| ctx[:at].zero? },
            'round' => lambda { |ctx| ctx[:round].to_i + 1 },
            'current' => lambda { |ctx| ctx[:at] }
          },
          'prev' => {
            'label' => 'pf2e.init_backs_up',
            'wraps' => lambda { |ctx| ctx[:at].zero? },
            'round' => lambda { |ctx| ctx[:round].to_i - 1 },
            # Backing up from the top of the order lands on the last participant, which is the one
            # before this round's first.
            'current' => lambda { |ctx| ctx[:at].zero? ? ctx[:size] - 1 : ctx[:at] - 1 }
          }
        }.freeze

        def self.directions
          DIRECTIONS.keys
        end

        # Where the order stands after moving one step.
        #
        #   current  the participant whose turn it now is, as an index
        #   upcoming the one after them
        #   round    the round number, changed only when the move crossed a boundary
        #   new_round whether it did
        def self.move(direction, size:, at:, round:)
          row = DIRECTIONS[direction.to_s]

          return Err.new(:unknown_direction, 'pf2e.bad_option', 'element' => 'direction',
                         'options' => directions.join(', ')) unless row
          return Err.new(:no_participants, 'pf2e.encounter_empty') if size.to_i < 1

          ctx = { :size => size.to_i, :at => at.to_i, :round => round.to_i }
          wraps = row['wraps'].call(ctx)
          current = row['current'].call(ctx)

          Ok.new(:state => {
            'current' => current,
            'upcoming' => (current + 1) % size.to_i,
            'round' => wraps ? row['round'].call(ctx) : round.to_i,
            'new_round' => wraps,
            'label' => row['label']
          })
        end
      end
    end
  end
end
