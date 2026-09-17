module AresMUSH
  module Pf2e
    module Advancement

      # What a finished level-up writes to the sheet, one row per draft key.
      #
      # `advance/done` is the commit boundary, so this is the one place a level's picks stop being a
      # draft and become the character. Every key the draft can hold has a row; a key with no row is
      # logged, because config or code naming something nothing applies is a fault for staff to see
      # rather than a sentence for the player.
      #
      # A row returns [ locale key, args, kind ] messages and the shell emits them, so the rules
      # here neither render nor hold a client. `kind` is :ooc or :failure, and nil for a plain line.
      module Apply

        KEYS = {
          'charclass_feature' => {
            'apply' => lambda { |ctx| Apply.add_features(ctx[:char], 'charclass_features', ctx[:value]) }
          },
          # Written to the sheet when the archetype was joined, and recorded in the draft so
          # advance/reset can take it back. Applying it again settles the two.
          'archetype_features' => {
            'apply' => lambda { |ctx| Apply.add_features(ctx[:char], 'archetype_features', ctx[:value]) }
          },
          'combat_stats' => {
            'apply' => lambda { |ctx|
              Pf2eCombat.update_combat_stats(ctx[:char], ctx[:value])

              []
            }
          },
          # Either a block of stats for the character's own class, or one keyed by class for an
          # archetype's. PF2Magic names the stat keys, which is what tells the two apart.
          'magic_stats' => {
            'apply' => lambda { |ctx|
              if PF2Magic.stats_block?(ctx[:value])
                PF2Magic.update_magic(ctx[:char], ctx[:charclass], ctx[:value], ctx[:client])
              else
                Array(ctx[:value]).each do |class_key, stats|
                  PF2Magic.update_magic(ctx[:char], class_key, stats, ctx[:client])
                end
              end

              []
            }
          },
          # A level that raises what a caster casts at. The same key update_magic uses, so it is
          # handed straight to it.
          'tradition' => {
            'apply' => lambda { |ctx|
              PF2Magic.update_magic(ctx[:char], ctx[:charclass], { 'tradition' => ctx[:value] }, ctx[:client])

              []
            }
          },
          'action' => {
            'apply' => lambda { |ctx| Apply.add_actions(ctx[:char], 'actions', ctx[:value]) }
          },
          'reaction' => {
            'apply' => lambda { |ctx| Apply.add_actions(ctx[:char], 'reactions', ctx[:value]) }
          },
          # The score moves so the sheet shows it, and the count is recorded so commit_level_up!
          # can diff it into boost_ability grants - which is what lets a rollback take it back.
          'raise ability' => {
            'apply' => lambda { |ctx|
              boosts = ctx[:char].pf2_boosts

              Array(ctx[:value]).each do |ability|
                Pf2eAbilities.update_base_score(ctx[:char], ability)
                boosts[ability] = boosts[ability].to_i + 1
              end

              ctx[:char].pf2_boosts = boosts

              []
            }
          },
          # Already in the draft, where the pick put it. The commit reads the draft and the
          # materialiser writes the sheet from the fold afterwards, so copying it onto pf2_lang
          # here would put it in both stores and the commit would record it twice.
          'languages' => {
            'apply' => lambda { |_ctx| [] }
          },
          'raise skill' => {
            'apply' => lambda { |ctx| Apply.raise_skills(ctx[:char], ctx[:value]) }
          },
          'raise skill choice' => {
            'apply' => lambda { |ctx| Apply.raise_skills(ctx[:char], ctx[:value]) }
          },
          'feats' => {
            'apply' => lambda { |ctx| Apply.add_feats(ctx) }
          },
          'charclass_feature option' => {
            'apply' => lambda { |ctx| Apply.feature_options(ctx) }
          },
          'spellbook' => {
            'apply' => lambda { |ctx| Apply.add_known(ctx, :spellbook) }
          },
          'repertoire' => {
            'apply' => lambda { |ctx| Apply.add_known(ctx, :repertoire) }
          },
          'signature' => {
            'apply' => lambda { |ctx| Apply.designate_signatures(ctx) }
          },
          'archetype_deity' => {
            'apply' => lambda { |ctx| Apply.set_faith(ctx[:char], 'deity', ctx[:value]) }
          },
          'archetype_sanctification' => {
            'apply' => lambda { |ctx| Apply.sanctify(ctx[:char], ctx[:value]) }
          },
          'grants' => {
            'apply' => lambda { |ctx|
              Array(ctx[:value]).each do |feat, info|
                Pf2e.do_feat_grants(ctx[:char], info, ctx[:charclass], ctx[:client])
              end

              []
            }
          },
          # An innate spell is granted by the magic_stats entry that opened its slot, which records
          # the chosen spell as its name. Nothing is left to apply.
          'innate' => { 'apply' => lambda { |_ctx| [] } },
          # Applied when the swap was made, at advance/swapspell.
          'repertoire_swap' => { 'apply' => lambda { |_ctx| [] } }
        }.freeze

        def self.keys
          KEYS.keys
        end

        # Writes a whole finished draft. Returns the messages the shell should emit; the character
        # is saved by the caller, once.
        def self.all(char, draft, charclass:, client:)
          (draft || {}).flat_map do |key, value|
            row = KEYS[key.to_s]

            unless row
              Global.logger.error "A level-up draft holds '#{key}', which nothing applies. Keys: #{keys.join(', ')}."
              next [ [ 'pf2e.adv_unknown_draft_key', { :key => key }, :ooc ] ]
            end

            Array(row['apply'].call(:char => char, :value => value,
                                    :charclass => charclass, :client => client))
          end
        end

        # ------------------------------------------------------------------------------
        # The longer rows
        # ------------------------------------------------------------------------------

        def self.add_features(char, bucket, value)
          features = char.pf2_features
          features[bucket] = (Array(features[bucket]) + Array(value)).uniq
          char.pf2_features = features

          []
        end

        def self.add_actions(char, bucket, value)
          actions = char.pf2_actions
          actions[bucket] = (Array(actions[bucket]) + Array(value)).uniq.sort
          char.pf2_actions = actions

          []
        end

        # One rank up for each skill the level raised. A skill with no row is skipped and logged:
        # abandoning the rest of the level-up over it would leave the sheet half written.
        def self.raise_skills(char, value)
          Array(value).each do |name|
            next if name.to_s.strip.empty?
            next if Pf2e.open_skill_token?(name)

            skill = Pf2eSkills.find_skill(name, char)

            next Global.logger.error("#{char.name} raised '#{name}', which is not one of their skills.") unless skill

            skill.update(:prof_level => Pf2eSkills.get_next_prof(char, name))
          end

          []
        end

        # The feats this level took. They stay in the draft: the commit reads it, and the materialiser
        # writes the sheet from the fold afterwards. Copying them onto the sheet here would put each
        # one in both stores, and the commit would then record it twice - which a rollback then took
        # back twice.
        #
        # What this arm does is the work each feat implies beyond being recorded.
        def self.add_feats(ctx)
          # A hash of bucket => feats, which Array() turns into pairs.
          Array(ctx[:value]).each do |(_bucket, taken)|
            Array(taken).each do |name|
              found = Pf2e.get_feat_details(name)

              next if found.is_a?(String)

              Pf2e.apply_init_magic_feat(ctx[:char], found[0], found[1], ctx[:client])
            end
          end

          []
        end

        def self.set_faith(char, key, value)
          faith = char.pf2_faith
          faith[key] = value
          char.pf2_faith = faith

          []
        end

        # ------------------------------------------------------------------------------
        # A class feature with an option, and what each option is worth
        # ------------------------------------------------------------------------------
        #
        # The feature is recorded by name either way. A row here is for one that also moves a
        # proficiency, and a feature with no row is a gap in the code rather than in the data - so
        # it is logged and said out of character, and the feature is still recorded.

        FEATURE_OPTIONS = {
          'Path to Perfection' => { 'apply' => lambda { |ctx| Apply.path_to_perfection(ctx, 'master') } },
          'Second Path to Perfection' => { 'apply' => lambda { |ctx| Apply.path_to_perfection(ctx, 'master') } },
          'Third Path to Perfection' => { 'apply' => lambda { |ctx| Apply.path_to_perfection(ctx, 'legendary') } },
          'Fighter Weapon Mastery' => {
            'apply' => lambda { |ctx|
              Apply.weapon_group(ctx, 'simple' => 'master', 'martial' => 'master',
                                      'unarmed' => 'master', 'advanced' => 'expert')
            }
          },
          'Weapon Legend' => {
            'apply' => lambda { |ctx|
              combat = Pf2eCombat.get_create_combat_obj(ctx[:char])
              profs = combat.weapon_prof || {}

              { 'simple' => 'master', 'martial' => 'master',
                'unarmed' => 'master', 'advanced' => 'expert' }.each_pair do |group, rank|
                profs[group] = Pf2e.higher_prof(profs[group], rank)
              end

              combat.update(:weapon_prof => profs)

              Apply.weapon_group(ctx, 'simple' => 'legendary', 'martial' => 'legendary',
                                      'unarmed' => 'legendary', 'advanced' => 'master')
            }
          },
          # Recorded among the class features, and nothing else to do yet.
          'Divine Ally' => { 'apply' => lambda { |_ctx| [] } }
        }.freeze

        def self.feature_options(ctx)
          Array(ctx[:value]).flat_map do |feature, option|
            record_feature_option(ctx[:char], feature, option)

            row = FEATURE_OPTIONS[feature.to_s]

            unless row
              Global.logger.error "The class feature '#{feature}' takes an option that nothing applies."
              next [ [ 'pf2e.missing_charclass_option_code', { :feature => feature }, :ooc ] ]
            end

            Array(row['apply'].call(ctx.merge(:feature => feature, :option => option)))
          end
        end

        def self.record_feature_option(char, feature, option)
          features = char.pf2_features
          label = "#{feature} (#{option})"
          held = Array(features['charclass_features'])

          features['charclass_features'] = held + [ label ] unless held.include?(label)
          char.pf2_features = features
        end

        # A monk's saving throw progression. The second path must be a save they have not already
        # perfected; the third has to be one they have.
        def self.path_to_perfection(ctx, rank)
          option = ctx[:option]
          third = ctx[:feature].to_s == 'Third Path to Perfection'
          combat = Pf2eCombat.get_create_combat_obj(ctx[:char])
          saves = combat.saves
          chosen = Array(saves['Path to Perfection'])
          already = chosen.any? { |save| save.to_s.casecmp?(option.to_s) }

          return [ [ 'pf2e.path_perfection_needs_earlier', { :option => option }, :failure ] ] if third && !already
          return [ [ 'pf2e.path_perfection_needs_new', { :option => option }, :failure ] ] if !third && already

          saves[option] = rank
          saves['Path to Perfection'] = already ? chosen : chosen + [ option ]

          combat.update(:saves => saves)

          []
        end

        def self.weapon_group(ctx, ranks)
          combat = Pf2eCombat.get_create_combat_obj(ctx[:char])
          groups = combat.weapon_group_prof || {}
          groups[ctx[:option]] = ranks

          combat.update(:weapon_group_prof => groups)

          []
        end

        # ------------------------------------------------------------------------------
        # Spells a level added
        # ------------------------------------------------------------------------------

        # A draft's spell picks are either keyed by rank for the character's own class, or by class
        # for an archetype's list. A spell with no rank of its own is filed by the rank its config
        # gives it.
        def self.add_known(ctx, attr)
          magic = ctx[:char].magic

          return [] unless magic

          held = magic.send(attr) || {}

          by_class(ctx).each_pair do |source, picks|
            for_source = held[source] || {}

            ranked(picks).each_pair do |rank, spells|
              for_source[rank] = Array(for_source[rank]) + Array(spells)
            end

            held[source] = for_source
          end

          magic.update(attr => held)

          []
        end

        # Signature spells are designated rather than added, so an open marker is dropped instead of
        # being recorded as a spell named "open".
        def self.designate_signatures(ctx)
          magic = ctx[:char].magic

          return [] unless magic

          held = magic.signature_spells || {}

          by_class(ctx).each_pair do |source, picks|
            for_source = held[source] || {}

            next unless picks.is_a?(Hash)

            picks.each_pair do |rank, spells|
              chosen = Array(spells).reject { |spell| spell.to_s.strip.empty? || spell.to_s.casecmp?('open') }

              for_source[rank] = chosen unless chosen.empty?
            end

            held[source] = for_source
          end

          magic.update(:signature_spells => held)

          []
        end

        # source => picks. A draft keyed by rank belongs to the character's own class.
        def self.by_class(ctx)
          value = ctx[:value]
          keyed_by_class = value.is_a?(Hash) && value.keys.any? { |key| !Pf2e.level_key?(key) }

          keyed_by_class ? value : { ctx[:charclass] => value }
        end

        # rank => spells. A flat list is filed by each spell's own rank.
        def self.ranked(picks)
          return picks if picks.is_a?(Hash)

          Array(picks).each_with_object({}) do |spell, by_rank|
            found = Pf2emagic.get_spell_details(spell)
            rank = found.is_a?(Array) ? found[1]['base_level'].to_s : '1'

            by_rank[rank] = Array(by_rank[rank]) + [ spell ]
          end
        end

        # A sanctification is a trait as well as a field, and a character holds only one of them.
        def self.sanctify(char, value)
          set_faith(char, 'sanctification', value)

          traits = Array(char.pf2_traits).reject { |trait| trait.to_s.casecmp?('holy') || trait.to_s.casecmp?('unholy') }
          traits = (traits + [ value.to_s.downcase ]).uniq.sort unless value.blank? || value.to_s.casecmp?('Unsanctified')

          char.pf2_traits = traits

          []
        end
      end
    end
  end
end
