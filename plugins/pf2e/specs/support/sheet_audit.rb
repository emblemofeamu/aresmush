module AresMUSH
  module Pf2e

    # Every element of a finished character, checked against what the class's tables promised.
    #
    # One row per dimension, each returning the mismatches it found, so the audit reports all of
    # them in one run. A climb wrong in six ways says so once. Adding a dimension is adding a row.
    #
    # Counting feats alone would miss a feature that never arrived, a proficiency the engine
    # dropped, a spell slot short, or a class choice never resolved.
    module SheetAudit

      DIMENSIONS = [
        {
          'name' => 'level',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            char.pf2_level == level ? [] : [ "level is #{char.pf2_level}, not #{level}" ]
          }
        },
        {
          'name' => 'features',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            held = SheetAudit.all_features(char)

            want['features'].reject { |name| held.any? { |h| h.to_s.casecmp?(name) } }
                            .map { |name| "feature '#{name}' is missing" }
          }
        },
        {
          'name' => 'granted feats',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            held = SheetAudit.all_feats(char)

            want['granted_feats'].reject { |name| held.any? { |h| h.to_s.casecmp?(name) } }
                                 .map { |name| "feat '#{name}', granted outright, is missing" }
          }
        },
        {
          'name' => 'feat slots',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            held = char.pf2_feats || {}

            want['feat_slots'].filter_map do |type, levels|
              actual = Array(held[type]).size
              next if actual >= levels.size

              "#{levels.size} #{type} feat slots were offered (levels #{levels.join(', ')}) but only #{actual} #{type} feats are held"
            end
          }
        },
        {
          'name' => 'feats are real',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            known = SheetAudit.configured_feat_names

            SheetAudit.all_feats(char).reject { |name| name.to_s.casecmp?('open') || known.include?(name.to_s.downcase) }
                                      .map { |name| "feat '#{name}' is not a feat in the game's data" }
          }
        },
        {
          'name' => 'feats match their slot',
          # A feat filed under 'general' had better be a general feat. A mis-filed one shows under
          # the wrong heading and changes what the next slot accepts.
          'check' => lambda { |ctx|
            char = ctx['char']
            types = SheetAudit.feat_types

            (char.pf2_feats || {}).flat_map do |bucket, feats|
              slot = bucket.to_s.downcase
              # Archetype and dedication slots hold feats of several types by design.
              next [] if %w(archetype dedication).include?(slot)

              Array(feats).filter_map do |name|
                next if name.to_s.casecmp?('open')

                held = types[name.to_s.downcase]
                next if held.nil? || held.empty?
                next if held.include?(slot)

                "'#{name}' is filed as a #{slot} feat but the game calls it #{held.join('/')}"
              end
            end
          }
        },
        {
          'name' => 'saves',
          'check' => lambda { |ctx| SheetAudit.compare_map('save', ctx['want']['saves'], ctx['char'].combat&.saves) }
        },
        {
          'name' => 'weapon proficiency',
          'check' => lambda { |ctx| SheetAudit.compare_map('weapon', ctx['want']['weapon_prof'], ctx['char'].combat&.weapon_prof) }
        },
        {
          'name' => 'armour proficiency',
          'check' => lambda { |ctx| SheetAudit.compare_map('armour', ctx['want']['armor_prof'], ctx['char'].combat&.armor_prof) }
        },
        {
          'name' => 'perception, class DC and sneak attack',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            combat = char.combat

            [ [ 'perception', want['perception'], combat&.perception ],
              [ 'class DC', want['class_dc'], combat&.class_dc ],
              [ 'sneak attack', want['sneak_attack'], combat&.sneak_attack ] ].filter_map do |label, wanted, actual|
              next if wanted.nil?
              next if actual.to_s.casecmp?(wanted.to_s)

              "#{label} is #{actual.inspect}, not #{wanted.inspect}"
            end
          }
        },
        {
          'name' => 'actions and reactions',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            held = char.pf2_actions || {}
            actions = Array(held['actions']).map(&:to_s)
            reactions = Array(held['reactions']).map(&:to_s)

            missing = want['actions'].reject { |a| actions.any? { |h| h.casecmp?(a) } }.map { |a| "action '#{a}' is missing" }
            missing + want['reactions'].reject { |r| reactions.any? { |h| h.casecmp?(r) } }.map { |r| "reaction '#{r}' is missing" }
          }
        },
        {
          'name' => 'languages',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            held = Array(char.pf2_lang).map(&:to_s)

            want['languages'].reject { |l| held.any? { |h| h.casecmp?(l) } }.map { |l| "language '#{l}' is missing" }
          }
        },
        {
          'name' => 'spell slots per rank',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            return [] if want['spells_per_day'].empty?

            actual = ((char.magic&.spells_per_day || {})[cc] || {})

            # A floor. Feats add slots: Cantrip Expansion gives a prepared caster two more cantrips,
            # so a count above what the table promises is correct, and one below it is a fault.
            want['spells_per_day'].filter_map do |rank, count|
              held = SheetAudit.at_rank(actual, rank).to_i
              next if held >= count.to_i

              "rank #{rank} has #{held} slots, fewer than the #{count} the tables grant"
            end
          }
        },
        {
          'name' => 'spells known',
          # Two claims, because the tables make two kinds of promise. A rank key pins the pick to
          # that rank, as a Wizard's ten cantrips and five first-rank spells do at chargen. `any`
          # lets the player place it, so for those only the total can be checked.
          'check' => lambda { |ctx|
            char, cc, want = ctx.values_at('char', 'charclass', 'want')

            pinned = want['known_picks']
            total_wanted = pinned.values.sum + want['known_anywhere']
            next [] if total_wanted.zero?

            known = SheetAudit.known_by_rank(char, cc)

            problems = pinned.filter_map do |rank, count|
              held = Array(SheetAudit.at_rank(known, rank)).size
              next if held >= count.to_i

              "rank #{rank} should hold #{count} spells; it holds #{held}"
            end

            held_total = known.values.sum(&:size)
            unless held_total >= total_wanted
              problems << "#{total_wanted} spells should be known or in the spellbook; #{held_total} are"
            end

            problems
          }
        },
        {
          'name' => 'signature spells',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            wanted = want['signature'].values.sum
            return [] if wanted.zero?

            held = ((char.magic&.signature_spells || {})[cc] || {}).values.flatten.compact.size
            return [] if held >= wanted

            [ "#{wanted} signature spells should be designated; #{held} are" ]
          }
        },
        {
          'name' => 'focus pool',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            return [] if want['focus_pool'].zero?

            held = (char.magic&.focus_pool || {})['max'].to_i
            # PF2e caps a focus pool at three however many sources feed it.
            wanted = [ want['focus_pool'], 3 ].min
            return [] if held >= wanted

            [ "focus pool maximum is #{held}, not #{wanted}" ]
          }
        },
        {
          'name' => 'attribute boosts',
          # Four at each of 5th, 10th, 15th and 20th, each to a different attribute, and each a
          # `boost_ability` grant attributed to its level. Chargen's own boosts are grants too, at
          # level 1, so the level filter is what separates the two.
          'check' => lambda { |ctx|
            char, want = ctx.values_at('char', 'want')

            wanted = want['boosts'] * 4
            recorded = SheetAudit.grants_of(char, 'boost_ability').select { |g| g.effective_level.to_i > 1 }

            problems = []

            unless recorded.size == wanted
              problems << "#{wanted} boosts should be in the ledger above level 1; #{recorded.size} are"
            end

            # PF2e: "When you gain multiple ability boosts at the same time, you must apply each
            # one to a different score."
            recorded.group_by { |g| g.effective_level.to_i }.each_pair do |level, at_level|
              abilities = at_level.map { |g| g.payload['ability'] }
              next if abilities.uniq.size == abilities.size

              problems << "level #{level} boosted #{abilities.tally.select { |_a, n| n > 1 }.keys.join(', ')} more than once"
            end

            # And every score has to be what its flaws and boosts make of 10.
            flaws = SheetAudit.grants_of(char, 'flaw_ability')
                              .group_by { |g| g.payload['ability'] }.transform_values(&:size)
            boosts = SheetAudit.grants_of(char, 'boost_ability')
                               .group_by { |g| g.payload['ability'] }.transform_values(&:size)

            char.abilities.to_a.each do |ability|
              expected = Pf2eAbilities.derived_score(flaws[ability.name].to_i, boosts[ability.name].to_i)

              next if ability.base_val.to_i == expected

              problems << "#{ability.name} is #{ability.base_val}, not the #{expected} that " \
                          "#{flaws[ability.name].to_i} flaws and #{boosts[ability.name].to_i} boosts make of 10"
            end

            problems
          }
        },
        {
          'name' => 'skill increases',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            recorded = SheetAudit.grants_of(char, 'raise_skill').count { |g| g.effective_level.to_i > 1 }
            return [] if recorded >= want['skill_increases']

            [ "#{want['skill_increases']} skill increases should be in the ledger; #{recorded} are" ]
          }
        },
        {
          'name' => 'class choices resolved',
          # Resolving a `charclass_choice` writes a feature labelled "<choice> (<option>)", such as
          # "Path to Perfection (Fortitude)". That label is what to look for. Where the mechanical
          # effect lands varies by choice: a save rank, a weapon group proficiency, or only the
          # label.
          'check' => lambda { |ctx|
            char, want = ctx.values_at('char', 'want')

            held = SheetAudit.all_features(char) + SheetAudit.all_feats(char)
            groups = (char.combat&.weapon_group_prof || {}).keys.map(&:to_s)

            want['choices'].filter_map do |choice|
              next if choice['options'].empty?

              resolved = choice['options'].any? do |option|
                label = "#{choice['name']} (#{option})"

                held.any? { |h| h.to_s.casecmp?(label) || h.to_s.casecmp?(option) } ||
                  groups.any? { |g| g.casecmp?(option) }
              end
              next if resolved

              "'#{choice['name']}' at level #{choice['level']} was never resolved (options: #{choice['options'].first(4).join(', ')})"
            end
          }
        },
        {
          'name' => 'feat choices resolved',
          # A feature whose choice is a named set of feats has to have left one of them on the
          # sheet. The Druid's Voice of Nature grants Animal Empathy or Plant Empathy.
          'check' => lambda { |ctx|
            char, want = ctx.values_at('char', 'want')

            held = SheetAudit.all_feats(char)

            want['feat_choices'].filter_map do |choice|
              next if choice['feats'].empty?
              next if choice['feats'].any? { |f| held.any? { |h| h.to_s.casecmp?(f) } }

              "'#{choice['name']}' at level #{choice['level']} left none of #{choice['feats'].join(' or ')} on the sheet"
            end
          }
        },
        {
          'name' => 'the ledger explains the sheet',
          'check' => lambda { |ctx|
            char, cc, want, level = ctx.values_at('char', 'charclass', 'want', 'level')
            # The sheet is a projection of the ledger, so a second materialise is a fixed point.
            # Anything that moves was written outside the ledger.
            before = Pf2e::Ledger.current_state(char)
            Pf2e::Ledger.invalidate!(char)
            Pf2e::Ledger.materialize!(char)
            after = Pf2e::Ledger.current_state(char)

            return [] if before == after

            differing = before.keys.select { |k| before[k] != after[k] }

            [ "re-folding the ledger changed #{differing.join(', ')}" ]
          }
        }
      ].freeze

      # Every mismatch, across every dimension.
      #
      # `baseline` carries what has to be measured before the climb. The ability totals at level 1
      # are there because nothing on the finished sheet records what they were.
      def self.diff(char, charclass, level, baseline = {})
        ctx = {
          'char' => char,
          'charclass' => charclass,
          'level' => level,
          'want' => ExpectedSheet.for(charclass, level, :specialize => (char.pf2_base_info || {})['specialize']),
          'baseline' => baseline
        }

        DIMENSIONS.flat_map do |dimension|
          Array(dimension['check'].call(ctx)).map { |msg| "[#{dimension['name']}] #{msg}" }
        end
      end

      # ----------------------------------------------------------------------------
      # Reading the sheet
      # ----------------------------------------------------------------------------

      # A map of name => proficiency rank, compared entry by entry so the report can name the save
      # or weapon category that is wrong instead of printing two hashes.
      def self.compare_map(label, wanted, actual)
        actual = actual || {}

        (wanted || {}).filter_map do |name, rank|
          key = actual.keys.find { |k| k.to_s.casecmp?(name.to_s) }
          held = key && actual[key]

          next if held.to_s.casecmp?(rank.to_s)

          "#{label} #{name} is #{held.inspect}, not #{rank.inspect}"
        end
      end

      def self.score_of(char, name)
        ability = char.abilities.to_a.find { |a| a.name.to_s.casecmp?(name.to_s) }

        ability && ability.base_val.to_i
      end

      def self.ability_total(char)
        char.abilities.to_a.sum { |a| (a.mod_val || a.base_val).to_i }
      end

      def self.all_features(char)
        (char.pf2_features || {}).values.flatten.compact.map(&:to_s)
      end

      def self.all_feats(char)
        (char.pf2_feats || {}).values.flatten.compact.map(&:to_s)
      end

      # Grants still in force, of one kind. A reverted grant stays in the ledger as history and no
      # longer describes the sheet.
      def self.grants_of(char, kind)
        char.grants.to_a.select { |g| g.kind == kind && g.reverted_by.blank? }
      end

      # Slot counts are keyed by rank, and the tables are inconsistent about whether a rank is a
      # string or an integer.
      def self.at_rank(map, rank)
        key = (map || {}).keys.find { |k| k.to_s.casecmp?(rank.to_s) }

        key && map[key]
      end

      # rank => [ spells ] across both a repertoire and a spellbook, unfilled slots dropped.
      def self.known_by_rank(char, charclass)
        magic = char.magic
        return {} unless magic

        [ magic.repertoire, magic.spellbook ].each_with_object({}) do |source, out|
          ((source || {})[charclass] || {}).each_pair do |rank, spells|
            filled = Array(spells).compact.reject { |s| s.to_s.casecmp?('open') }

            out[rank.to_s] = Array(out[rank.to_s]) + filled
          end
        end
      end

      def self.known_count(char, charclass)
        known_by_rank(char, charclass).values.sum(&:size)
      end

      # feat name (downcased) => the types the game says it is.
      def self.feat_types
        @feat_types ||= (Global.read_config('pf2e_feats') || {}).each_with_object({}) do |(name, info), out|
          next unless info.is_a?(Hash)

          out[name.to_s.downcase] = Array(info['feat_type']).map { |t| t.to_s.downcase }
        end
      end

      # Every feat name the game defines, downcased, so a held feat can be checked for being real.
      # All five feat files load into one `pf2e_feats` section, which is how the game reads them.
      def self.configured_feat_names
        @configured_feat_names ||= (Global.read_config('pf2e_feats') || {}).keys.map { |k| k.to_s.downcase }
      end

      def self.reset_cache!
        @configured_feat_names = nil
        @feat_types = nil
      end
    end
  end
end
