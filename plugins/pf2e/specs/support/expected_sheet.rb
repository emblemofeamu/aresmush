module AresMUSH
  module Pf2e

    # What a character of one class should hold at one level, folded out of the class's own tables.
    #
    # A class table is declarative throughout. `charclass_feature` names features, `combat_stats`
    # names proficiency ranks, `magic_stats` names slot and spell counts, `choose_feat` names slots
    # to fill, `raise` names boosts and skill increases, and `feat` names feats granted outright.
    # The finished sheet therefore follows from the tables, which is what lets a climb be checked
    # against all of it.
    #
    # Pure: config in, an expectation hash out. Whether the tables themselves match PF2e is a
    # separate question, asserted in class_table_specs.rb. A config that has drifted from the rules
    # fails there; an engine that has drifted from config fails here.
    module ExpectedSheet

      BLANK = {
        'features' => [],
        'granted_feats' => [],
        'feat_slots' => {},
        'saves' => {},
        'weapon_prof' => {},
        'armor_prof' => {},
        'perception' => nil,
        'class_dc' => nil,
        'sneak_attack' => nil,
        'actions' => [],
        'reactions' => [],
        'languages' => [],
        'spells_per_day' => {},
        'known_picks' => {},
        'known_anywhere' => 0,
        'signature' => {},
        'focus_pool' => 0,
        'boosts' => 0,
        'skill_increases' => 0,
        'choices' => [],
        'feat_choices' => [],
        'unknown_feat_slots' => []
      }.freeze

      # The feat slot types the engine understands. A `choose_feat` entry outside this list opens no
      # slot and grants nothing.
      FEAT_SLOT_TYPES = %w(charclass skill general ancestry archetype dedication).freeze

      # How each key in a chargen or advance block contributes. One row per key; a key with no row
      # is listed by `unabsorbed`, which is asserted empty, so the expectation cannot fall behind
      # the config.
      ABSORBERS = {
        'charclass_feature' => lambda { |acc, value, _lv| acc['features'] |= Array(value).map(&:to_s) },
        'archetype_feature' => lambda { |acc, value, _lv| acc['features'] |= Array(value).map(&:to_s) },
        'feat' => lambda { |acc, value, _lv| acc['granted_feats'] |= Array(value).map(&:to_s) },
        'action' => lambda { |acc, value, _lv| acc['actions'] |= Array(value).map(&:to_s) },
        'reaction' => lambda { |acc, value, _lv| acc['reactions'] |= Array(value).map(&:to_s) },
        'languages' => lambda { |acc, value, _lv| acc['languages'] |= Array(value).map(&:to_s) },

        # A slot the player fills, counted by type and level, so the audit can name the level whose
        # slot went unfilled.
        'choose_feat' => lambda { |acc, value, lv|
          Array(value).each do |type|
            name = type.to_s.downcase

            if FEAT_SLOT_TYPES.include?(name)
              (acc['feat_slots'][name] ||= []) << lv
            else
              acc['unknown_feat_slots'] << { 'entry' => type.to_s, 'level' => lv }
            end
          end
        },

        # `raise` is a list of what goes up at this level.
        'raise' => lambda { |acc, value, _lv|
          Array(value).each do |kind|
            case kind.to_s.downcase
            when 'ability' then acc['boosts'] += 1
            when 'skill' then acc['skill_increases'] += 1
            end
          end
        },

        'combat_stats' => lambda { |acc, value, _lv| ExpectedSheet.absorb_combat(acc, value) },
        'magic_stats' => lambda { |acc, value, lv| ExpectedSheet.absorb_magic(acc, value, lv) },

        # A class feature that asks the player to pick. The pick has to have been made.
        'charclass_choice' => lambda { |acc, value, lv|
          next unless value.is_a?(Hash)

          # Options are written either as a list or as a hash keyed by option name.
          options = value['options']
          options = options.is_a?(Hash) ? options.keys : Array(options)

          acc['choices'] << {
            'name' => value['choice_name'].to_s,
            'level' => lv,
            'options' => options.map(&:to_s)
          }
        },

        # A feature that hands over a feat from a pool of its own - Skillful Lessons, Stylish
        # Tricks. The character ends up holding one more feat of the pool's type.
        'grant_choice' => lambda { |acc, value, lv|
          Array(value).each { |name| (acc['granted_choices'] ||= []) << { 'name' => name.to_s, 'level' => lv } }
        },

        # Keys that contribute nothing to the dimensions this expectation covers. They are listed
        # anyway, because `unabsorbed` is asserted empty: a key the tables grow has to be considered
        # before the audit passes again.
        'skills' => lambda { |_acc, _value, _lv| nil },
        'skill choice' => lambda { |_acc, _value, _lv| nil },
        # A feature that hands over one of a named set of feats. The Druid's Voice of Nature grants
        # "your choice of the Animal Empathy or Plant Empathy druid feat". Where the pool is a named
        # list, the expectation can say which feats satisfy it.
        'feat_choice' => lambda { |acc, value, lv|
          next unless value.is_a?(Hash)

          value.each_pair do |name, definition|
            next unless definition.is_a?(Hash)

            names = Array((definition['from_feats'] || {})['names']).map(&:to_s)

            acc['feat_choices'] << { 'name' => name.to_s, 'level' => lv, 'feats' => names }
          end
        },
        'reagents' => lambda { |_acc, _value, _lv| nil },
        'familiar' => lambda { |_acc, _value, _lv| nil },
        'companion' => lambda { |_acc, _value, _lv| nil },
        'formula_book' => lambda { |_acc, _value, _lv| nil },
        'curse' => lambda { |_acc, _value, _lv| nil },
        'anathema' => lambda { |_acc, _value, _lv| nil },
        'tradition' => lambda { |_acc, _value, _lv| nil }
      }.freeze

      # Proficiency keys that hold name => rank, and the ones that hold a bare value.
      PROF_MAPS = { 'saves' => 'saves', 'weapon_prof' => 'weapon_prof', 'armor_prof' => 'armor_prof' }.freeze
      PROF_VALUES = { 'perception' => 'perception', 'class_dc' => 'class_dc', 'sneak_attack' => 'sneak_attack' }.freeze

      def self.absorb_combat(acc, value)
        (value || {}).each_pair do |key, sub|
          name = key.to_s

          if PROF_MAPS.key?(name)
            (sub || {}).each_pair { |item, rank| acc[PROF_MAPS[name]][item.to_s] = rank.to_s }
          elsif PROF_VALUES.key?(name)
            acc[PROF_VALUES[name]] = sub.to_s
          end
        end
      end

      # Slots and spells. `spells_per_day` is per rank and last-wins, matching the engine's
      # apply_stat_delta. `spellbook` and `repertoire` count picks: a rank key gives that many
      # spells at that rank, while `any` gives that many at the player's choice of rank, so for
      # those only the total can be predicted.
      def self.absorb_magic(acc, value, level = nil)
        (value || {}).each_pair do |key, sub|
          case key.to_s
          when 'spells_per_day'
            (sub || {}).each_pair { |rank, count| acc['spells_per_day'][rank.to_s] = apply_delta(acc['spells_per_day'][rank.to_s], count) }
          when 'spellbook', 'repertoire'
            # A rank key pins the pick to that rank; `any` lets the player place it, so only the
            # total is predictable for those.
            #
            # A chargen figure states the total, and a specialty's supersedes the class's. A
            # Wizard's school says 11 cantrips and 7 first-rank, which is the class's 10 and 5 with
            # the curriculum's 1 and 2 already counted in. Advance blocks grant increments, so those
            # accumulate.
            chargen = level.to_i <= 1

            (sub || {}).each_pair do |rank, count|
              if rank.to_s.casecmp?('any')
                acc['known_anywhere'] += count.to_i
              elsif chargen
                acc['known_picks'][rank.to_s] = count.to_i
              else
                acc['known_picks'][rank.to_s] = acc['known_picks'][rank.to_s].to_i + count.to_i
              end
            end
          when 'signature_spells'
            (sub || {}).each_pair { |rank, count| acc['signature'][rank.to_s] = acc['signature'][rank.to_s].to_i + count.to_i }
          when 'focus_pool'
            acc['focus_pool'] = apply_delta(acc['focus_pool'], sub).to_i
          end
        end
      end

      # The engine reads "+1" as a delta and a bare number as a value. The expectation has to agree,
      # or it will call a correct climb wrong.
      def self.apply_delta(current, value)
        return current.to_i + value.strip.to_i if value.is_a?(String) && value.strip.match?(/\A[+-]\d+\z/)

        value.to_i
      end

      # The blocks one config section contributes: its chargen block, then every advance entry
      # from 2 up to and including the level.
      def self.blocks_in(config, level)
        config = config || {}
        advance = config['advance'] || {}

        blocks = [ [ 1, config['chargen'] ] ]

        advance.keys.sort_by { |k| k.to_i }.each do |key|
          next if key.to_i > level

          blocks << [ key.to_i, advance[key] ]
        end

        blocks.select { |_lv, block| block.is_a?(Hash) }
      end

      # Everything that shapes a character of this class: the class table, plus the specialty's own
      # table when one was chosen. A Warpriest Cleric's expert fortitude and martial weapon
      # proficiency are in the specialty's blocks, so an expectation built from the class alone
      # calls a correct character wrong.
      def self.blocks(charclass, level, specialize: nil)
        found = blocks_in(Global.read_config('pf2e_class', charclass), level)

        return found if specialize.blank?

        found + blocks_in(Global.read_config('pf2e_specialty', charclass.to_s, specialize.to_s), level)
      end

      def self.for(charclass, level, specialize: nil)
        acc = deep_blank

        blocks(charclass, level, :specialize => specialize).each do |lv, block|
          block.each_pair do |key, value|
            absorber = ABSORBERS[key.to_s]
            absorber&.call(acc, value, lv)
          end
        end

        acc['feat_slots'].each_value(&:sort!)
        acc
      end

      # Config keys no absorber knows about. An empty list is the claim that the expectation
      # covers everything the tables say.
      def self.unabsorbed
        found = []

        sections = (Global.read_config('pf2e_class') || {}).map { |name, config| [ name, config ] }

        (Global.read_config('pf2e_specialty') || {}).each_pair do |charclass, specialties|
          next unless specialties.is_a?(Hash)

          specialties.each_pair { |name, config| sections << [ "#{charclass}/#{name}", config ] }
        end

        sections.each do |label, config|
          next unless config.is_a?(Hash)

          blocks = [ [ 'chargen', config['chargen'] ] ] + (config['advance'] || {}).map { |lv, b| [ lv.to_s, b ] }

          blocks.each do |where, block|
            next unless block.is_a?(Hash)

            (block.keys.map(&:to_s) - ABSORBERS.keys).each { |key| found << "#{label} at #{where}: #{key}" }
          end
        end

        found.sort.uniq
      end

      # `choose_feat` entries that are not slot types, across every class. Such an entry opens no
      # slot and grants nothing.
      def self.inert_feat_slots
        (Global.read_config('pf2e_class') || {}).each_with_object({}) do |(charclass, config), found|
          bad = blocks_in(config, 20).flat_map do |_lv, block|
            Array(block['choose_feat']).map(&:to_s).reject { |t| FEAT_SLOT_TYPES.include?(t.downcase) }
          end

          found[charclass] = bad.uniq unless bad.empty?
        end
      end

      def self.deep_blank
        BLANK.each_with_object({}) do |(key, value), acc|
          acc[key] = value.is_a?(Array) || value.is_a?(Hash) ? value.dup : value
        end
      end
    end
  end
end
