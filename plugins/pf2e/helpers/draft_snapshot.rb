module AresMUSH
  module Pf2e

    # What a character's draft looks like, and how to move it back to an earlier shape.
    #
    # A draft lives in three places: attributes on the character, the skill rows, and the ability
    # rows. A snapshot reads all three; a diff of two snapshots holds only what changed, with the
    # value from the `before` side; restoring writes those values back.
    #
    # Attributes are taken by rule rather than by list - everything the chargen and advancement
    # code can write, minus the few things a draft does not own. A list would have to be extended
    # whenever an attribute is added, and the failure mode of forgetting is a value that silently
    # does not come back. The rule covers a new attribute on its own.
    module DraftSnapshot

      # Not part of a draft: a balance, a condition, a display preference, or a timestamp. Undoing
      # a pick must not take back an XP award that happened to land during the same command.
      NOT_DRAFT = %w{
        pf2_xp pf2_money pf2_conditions pf2_is_dead pf2_last_refresh pf2_viewsheet
        pf2_roll_aliases pf2_known_for pf2_gear pf2_invested_list pf2_ledger_entries
      }.freeze

      # Attributes outside the pf2_ prefix that a draft does own.
      ALSO_DRAFT = %w{chargen_stage advancing}.freeze

      def self.attrs
        @attrs ||= (Character.attributes.map(&:to_s).select { |a| a.start_with?('pf2_') } + ALSO_DRAFT)
          .reject { |a| NOT_DRAFT.include?(a) }
          .sort
          .freeze
      end

      # One row per place a draft is held: how to read it, and how to write one back.
      SLICES = {
        'attrs' => {
          'read' => lambda { |char| DraftSnapshot.attrs.each_with_object({}) { |a, h| h[a] = char.send(a) } },
          'write' => lambda { |char, values| values.each_pair { |a, v| char.update(a.to_sym => v) } }
        },
        'skills' => {
          'read' => lambda { |char| DraftSnapshot.skill_ranks(char) },
          'write' => lambda { |char, values|
            values.each_pair do |name, held|
              row = Pf2eSkills.find_skill(name, char) || Pf2eSkills.create_skill_for_char(name, char)

              # No entry on the before side means the step created the row. An untrained row is how
              # a skill goes away: the row itself is kept, because that is what the game does with a
              # skill nobody has trained.
              rank, cg_skill = held || [ 'untrained', false ]

              row.update(:prof_level => rank, :cg_skill => cg_skill)
            end
          }
        },
        'abilities' => {
          'read' => lambda { |char| DraftSnapshot.ability_scores(char) },
          'write' => lambda { |char, values|
            # A score of nil would mean the step created the row, which nothing does: the six rows
            # are made together when the character is.
            values.each_pair { |name, score| Ledger.apply_ability_score(char, name, score) unless score.nil? }
          }
        },
        'magic' => {
          'read' => lambda { |char|
            magic = char.magic

            next {} unless magic

            PF2Magic.attributes.each_with_object({}) { |a, h| h[a.to_s] = magic.send(a) }
          },
          'write' => lambda { |char, values|
            magic = char.magic

            next unless magic

            # Nil means there was no magic object when the step ran. Undoing a pick is not a reason
            # to take a caster's whole spellcasting away, so the attribute is left as it is.
            values.each_pair { |a, v| magic.update(a.to_sym => v) unless v.nil? }
          }
        }
      }.freeze

      # Every skill row's rank, in two round trips rather than one per row.
      #
      # A character holds a row for every skill the game defines - 255 of them - and
      # `char.skills.to_a` builds an object per row, each its own HGETALL. A snapshot is taken on
      # every draft command a player types, on the one reactor thread the whole game shares, so the
      # rows are read in one pipeline instead: 1.4 ms for a whole snapshot rather than twenty.
      def self.skill_ranks(char)
        ids = char.skills.ids

        return {} if ids.empty?

        ids.each { |id| Ohm.redis.queue('HGETALL', Pf2eSkills.key[id]) }

        Ohm.redis.commit.each_with_object({}) do |flat, ranks|
          row = Hash[*Array(flat)]

          next if row['name'].blank?

          ranks[row['name']] = [ row['prof_level'], row['cg_skill'] == 'true' ]
        end
      end

      # The six ability scores, read the same way and for the same reason.
      def self.ability_scores(char)
        ids = char.abilities.ids

        return {} if ids.empty?

        ids.each { |id| Ohm.redis.queue('HGETALL', Pf2eAbilities.key[id]) }

        Ohm.redis.commit.each_with_object({}) do |flat, scores|
          row = Hash[*Array(flat)]

          next if row['name'].blank?

          scores[row['name']] = row['base_val'].to_i
        end
      end

      def self.of(char)
        SLICES.each_with_object({}) { |(name, slice), shot| shot[name] = slice['read'].call(char) }
      end

      # What to write to turn `after` back into `before`: the before value of every key the two
      # disagree on, and nothing for a slice they agree on entirely.
      def self.diff(before, after)
        SLICES.keys.each_with_object({}) do |name, delta|
          was = before[name] || {}
          now = after[name] || {}
          changed = (was.keys | now.keys).reject { |key| was[key] == now[key] }

          next if changed.empty?

          # A key present only in `now` is one the step created. Writing the before value back is
          # how it goes away, and a nil skill rank reads as untrained.
          delta[name] = changed.each_with_object({}) { |key, slice| slice[key] = was[key] }
        end
      end

      # A short, stable fingerprint of a whole snapshot. Sorted so two equal drafts agree whatever
      # order Ohm handed their rows back in.
      def self.digest(shot)
        Digest::SHA1.hexdigest(stable(shot).to_s)
      end

      def self.stable(value)
        case value
        when Hash then value.keys.map(&:to_s).sort.map { |key| [ key, stable(value[key] || value[key.to_sym]) ] }
        when Array then value.map { |v| stable(v) }
        else value.to_s
        end
      end

      def self.restore!(char, delta)
        Array(delta).each do |name, values|
          SLICES[name]['write'].call(char, values) if SLICES.key?(name)
        end

        Character[char.id]
      end
    end
  end
end
