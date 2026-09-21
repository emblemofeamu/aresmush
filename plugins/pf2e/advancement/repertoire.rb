module AresMUSH
  module Pf2e
    module Advancement

      # Swapping one spell in a spontaneous caster's repertoire, which PF2e allows once per
      # level-up.
      #
      # Pure. The command still resolves spell names and reads the magic object, because both
      # need the live character; what is here are the decisions, which were eight sequential
      # early-returns and a list splice.
      module Repertoire

        # Each row: what makes the swap impossible, and what to say. In order, so the most
        # specific complaint is the one the player gets.
        GUARDS = [
          {
            'name' => 'once per level',
            'check' => lambda { |ctx| ctx[:already_swapped] ? Err.new(:swap_limit, 'pf2e.swapspell_limit') : nil }
          },
          {
            'name' => 'they know the old spell',
            'check' => lambda { |ctx|
              next nil if ctx[:held].any? { |s| s.to_s.casecmp?(ctx[:old].to_s) }

              Err.new(:not_in_list, 'pf2emagic.not_in_list')
            }
          },
          {
            'name' => 'the old spell is theirs to give up',
            'check' => lambda { |ctx|
              next nil unless ctx[:locked].any? { |s| s.to_s.casecmp?(ctx[:old].to_s) }

              Err.new(:locked, 'pf2e.swapspell_locked')
            }
          },
          {
            'name' => 'it is actually a swap',
            'check' => lambda { |ctx|
              ctx[:old].to_s.casecmp?(ctx[:new].to_s) ? Err.new(:same_spell, 'pf2e.swapspell_same') : nil
            }
          },
          {
            'name' => 'they do not know the new one already',
            'check' => lambda { |ctx|
              next nil unless ctx[:held].any? { |s| s.to_s.casecmp?(ctx[:new].to_s) }

              Err.new(:already_has, 'pf2e.already_has', 'item' => 'spell')
            }
          }
        ].freeze

        # The repertoire list with the swap made, or the Err of the first guard that refused.
        #
        #   held             the spells they know at that rank
        #   locked           the ones their specialty granted, which cannot be given up
        #   already_swapped  whether this advancement has already used its one swap
        def self.swap(held, old_spell, new_spell, locked: [], already_swapped: false)
          ctx = {
            :held => Array(held),
            :old => old_spell,
            :new => new_spell,
            :locked => Array(locked),
            :already_swapped => already_swapped
          }

          GUARDS.each do |guard|
            failure = guard['check'].call(ctx)

            return failure if failure
          end

          # A swap is a release and a fill of the same slot, which is what the slot vocabulary
          # already says - so it is one fold rather than an index splice.
          result = Slots.apply({ 'spells' => ctx[:held] }, [
            Slots.release('spells', old_spell, :token => Slots::OPEN),
            Slots.fill('spells', new_spell)
          ])

          result.is_a?(Err) ? result : result['spells']
        end

        # Spells a specialty put in the repertoire, which the character never chose and so
        # cannot trade away. Reads the specialty's own config, at or below the level reached.
        def self.granted(specialty_info, level)
          info = specialty_info || {}
          blocks = [ (info['chargen'] || {})['magic_stats'] ]

          (info['advance'] || {}).each_pair do |at_level, entry|
            next unless at_level.to_i <= level.to_i

            blocks << (entry || {})['magic_stats']
          end

          blocks.compact.flat_map { |magic| Array((magic['addrepertoire'] || {}).values).flatten }
            .compact.map(&:to_s)
        end
      end
    end
  end
end
