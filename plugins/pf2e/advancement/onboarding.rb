module AresMUSH
  module Pf2e
    module Advancement

      # Taking an archetype's Dedication feat: claim a slot for the archetype, then apply
      # everything its `initial_dedication` block hands over.
      #
      # This was two hundred and thirty lines inside advance/feat's single method, and the
      # only path that ran it was typing `advance/feat` - so a Dedication gained any other way
      # (a class feature choice whose pool includes one, and sixteen of them do) left the
      # character holding a Dedication feat with no archetype behind it.
      #
      # PAYLOAD is that block's vocabulary, one row per key it may carry. Each row says how to
      # apply it and what to tell the player. Adding a key is adding a row; the order is the
      # order they are applied in, and deity comes first because sanctification reads it.
      #
      # Not pure, and honest about why: skills, magic and features are held on live Ohm
      # objects rather than in CharState, so applying them means touching the character. The
      # sequencing and the decisions are what this makes legible and testable; making it pure
      # would mean bringing the magic and combat models into the state first.
      module Onboarding

        # Tidies a config list into trimmed, non-empty, unique strings.
        def self.names(value)
          Array(value).compact.map { |v| v.to_s.strip }.reject(&:empty?).uniq
        end

        PAYLOAD = [
          # A deity the archetype needs. Taken from the character when they already have one,
          # otherwise opened for them to pick - and their deity's skill comes with it.
          {
            'key' => 'use_deity',
            'from' => 'archetype',
            'apply' => lambda { |ctx|
              held = ctx[:char].pf2_faith['deity']

              if held.blank?
                ctx[:to_assign]['archetype deity'] = 'open'

                next [ [ 'pf2e.adv_archetype_deity_select', { :archetype => ctx[:archetype] } ] ]
              end

              ctx[:to_assign]['archetype deity'] = held
              ctx[:advancement]['archetype_deity'] = held

              msgs = [ [ 'pf2e.adv_archetype_deity_assigned', { :deity => held, :archetype => ctx[:archetype] } ] ]
              skill = Global.read_config('pf2e_deities', held, 'divine_skill')

              next msgs if skill.blank?

              msgs.concat(Onboarding.train(ctx, [ skill ], 'deity', 'pf2e.adv_archetype_deity_skill_assigned',
                :deity => held, :skill => skill))

              msgs
            }
          },
          # Skills the archetype trains outright.
          {
            'key' => 'skills',
            'apply' => lambda { |ctx|
              skills = Onboarding.names(ctx[:payload]['skills'])

              next [] if skills.empty?

              Onboarding.train(ctx, skills, 'archetype', 'pf2e.adv_archetype_skills_assigned',
                :skills => skills.join(", "))
            }
          },
          # A skill increase restricted to a named list.
          {
            'key' => 'skill choice',
            'apply' => lambda { |ctx|
              choices = Onboarding.names(ctx[:payload]['skill choice'])

              next [] if choices.empty?

              ctx[:to_assign]['raise skill choice'] = (Array(ctx[:to_assign]['raise skill choice']) + choices).uniq

              [ [ 'pf2e.adv_archetype_open_skill_assigned', { :skills => choices.join(", ") } ] ]
            }
          },
          # Named feats the archetype grants, which land in the general bucket.
          {
            'key' => 'feat',
            'apply' => lambda { |ctx|
              feats = Onboarding.names(ctx[:payload]['feat'])

              next [] if feats.empty?

              ctx[:to_assign]['feats'] ||= {}
              ctx[:to_assign]['feats']['general'] = (Array(ctx[:to_assign]['feats']['general']) + feats).uniq

              ctx[:advancement]['feats'] ||= {}
              ctx[:advancement]['feats']['general'] = (Array(ctx[:advancement]['feats']['general']) + feats).uniq

              [ [ 'pf2e.adv_archetype_feats_assigned', { :feats => feats.join(", ") } ] ]
            }
          },
          # Feat slots the archetype opens for the player to fill.
          {
            'key' => 'choose_feat',
            'apply' => lambda { |ctx|
              types = Onboarding.names(ctx[:payload]['choose_feat'])

              next [] if types.empty?

              ctx[:to_assign]['feats'] ||= {}
              types.each { |type| ctx[:to_assign]['feats'][type] = Array(ctx[:to_assign]['feats'][type]) + [ 'open' ] }

              types.include?('skill') ? [ [ 'pf2e.adv_archetype_open_skill_feat_assigned', {} ] ] : []
            }
          },
          # Combat stats, and the archetype's own class DC - whose key ability is a choice
          # when the archetype offers more than one.
          {
            'key' => 'combat_stats',
            'apply' => lambda { |ctx|
              stats = (ctx[:payload]['combat_stats'] || {}).dup

              next [] if stats.empty?

              msgs = []
              class_dc = stats.delete('archetype_class_dc')

              if class_dc
                dcs = ((ctx[:advancement]['combat_stats'] ||= {})['archetype_class_dcs'] ||= {})
                entry = (dcs[ctx[:archetype]] ||= {})
                entry['prof'] = class_dc

                abilities = Onboarding.names(ctx[:info]['key_abil'])

                if abilities.size > 1
                  ctx[:to_assign]['archetype key ability'] = abilities
                  msgs << [ 'pf2e.adv_archetype_key_ability_select', { :archetype => ctx[:archetype], :options => abilities.join(", ") } ]
                else
                  chosen = abilities.first || ctx[:char].combat&.key_abil
                  entry['key_abil'] = chosen if chosen
                end
              end

              if !stats.empty?
                ctx[:advancement]['combat_stats'] ||= {}
                ctx[:advancement]['combat_stats'] = Pf2e.merge_combat_stats(ctx[:advancement]['combat_stats'], stats)
                msgs << [ 'pf2e.adv_archetype_combat_stats_assigned', {} ]
              end

              msgs
            }
          },
          # Spellcasting the archetype brings, kept under the archetype's own key so it does
          # not mix with the base class's.
          {
            'key' => 'magic_stats',
            'apply' => lambda { |ctx|
              magic = ctx[:payload]['magic_stats'] || {}

              next [] if magic.empty?

              assessed = PF2Magic.assess_magic_stats(ctx[:char], magic)

              ctx[:advancement]['magic_stats'] ||= {}
              Pf2e.wrap_adv_magic_stats(ctx[:advancement], ctx[:base_class])
              ctx[:advancement]['magic_stats'][ctx[:archetype]] = assessed['magic_stats']

              options = assessed['magic_options'] || {}

              next [] if options.empty?

              options.each_pair do |key, value|
                Pf2e.wrap_magic_assign(ctx[:to_assign], key, ctx[:base_class])
                ctx[:to_assign][key] ||= {}
                ctx[:to_assign][key][ctx[:archetype]] = value
              end

              # Already rendered, so passed through as literal text rather than a locale key.
              Pf2e.magic_option_messages(options.keys).map { |msg| [ nil, msg ] }
            }
          },
          # Features the archetype grants. Recorded in the draft as well as on the sheet, so
          # advance/reset knows which ones it put there.
          {
            'key' => 'archetype_feature',
            'apply' => lambda { |ctx|
              wanted = Onboarding.names(ctx[:payload]['archetype_feature'])

              next [] if wanted.empty?

              features = ctx[:char].pf2_features
              held = (features['archetype_features'] ||= [])
              added = wanted.reject { |f| held.any? { |h| h.to_s.casecmp?(f.to_s) } }

              held.concat(added)

              # A character attribute rather than part of the draft, so written now - see the
              # same note in FeatGain.dedication.
              ctx[:char].update(:pf2_features => features)

              ctx[:advancement]['archetype_features'] = Array(ctx[:advancement]['archetype_features']) + added unless added.empty?

              [ [ 'pf2e.adv_archetype_features_assigned', { :features => wanted.join(", ") } ] ]
            }
          },
          # A specialty to choose, if the archetype has any.
          {
            'key' => 'specialty',
            'from' => 'archetype',
            'apply' => lambda { |ctx|
              specialties = Global.read_config('pf2e_archetype_specialty', ctx[:archetype])

              next [] if specialties.blank?

              ctx[:to_assign]['archetype_specialty'] = 'open'

              [ [ 'pf2e.adv_archetype_specialty_select',
                  { :archetype => ctx[:archetype], :options => specialties.keys.sort.join(", ") } ] ]
            }
          },
          # Sanctification, for the two archetypes that have it.
          {
            'key' => 'sanctification',
            'from' => 'archetype',
            'apply' => lambda { |ctx| Onboarding.sanctification(ctx) }
          }
        ].freeze

        # ------------------------------------------------------------------------------
        # Applying it
        # ------------------------------------------------------------------------------

        # Returns the messages to speak. Mutates to_assign, advancement and - for features -
        # the character, which the caller saves.
        def self.apply(char, archetype, to_assign, advancement)
          info = Global.read_config('pf2e_archetype', archetype) || {}

          ctx = {
            :char => char,
            :archetype => archetype,
            :info => info,
            :payload => info['initial_dedication'] || {},
            :base_class => char.pf2_base_info['charclass'],
            :to_assign => to_assign,
            :advancement => advancement
          }

          PAYLOAD.flat_map do |row|
            # A row reading the archetype rather than its dedication payload says so; the rest
            # are skipped when the payload has nothing under their key.
            next [] if row['from'] != 'archetype' && !ctx[:payload].key?(row['key'])
            next [] if row['key'] == 'use_deity' && !info['use_deity']

            Array(row['apply'].call(ctx))
          end
        end

        # Which numbered archetype slot a new archetype takes: the lowest free one.
        def self.claim_slot(archetypes, archetype)
          slots = Archetypes.keys_for('archetype')
          free = slots.find { |key| archetypes[key].to_s.strip.empty? }

          free ? archetypes.merge(free => archetype) : archetypes
        end

        def self.train(ctx, skills, item, key, args = {})
          result = Pf2e.add_training_skills(ctx[:char], skills, ctx[:to_assign], ctx[:advancement])
          msgs = []

          msgs << [ key, args ] if result[:assigned].any?
          msgs << [ 'pf2e.adv_duplicate_skill_open', { :item => item } ] if result[:open_count].to_i > 0 || result[:open_lore_count].to_i > 0

          msgs
        end

        # ------------------------------------------------------------------------------
        # Sanctification
        # ------------------------------------------------------------------------------

        # Champion and Cleric archetypes both care about sanctification, and which one the
        # character may have depends on what they already are. Each row is a case: whose
        # sanctification list governs, and what to say when it cannot be settled here.
        SANCTIFICATION = {
          'Champion Archetype' => {
            # A Cleric's sanctification comes from their deity and an archetype cannot move it.
            'locked_for' => 'Cleric',
            'allowed' => lambda { |ctx| Array(Global.read_config('pf2e_archetype', ctx[:archetype], 'allowed_sanctifications')) },
            'needs' => nil
          },
          'Cleric Archetype' => {
            'locked_for' => nil,
            # A Champion taking the Cleric archetype must be Holy.
            'allowed' => lambda { |ctx|
              next [ 'Holy' ] if ctx[:base_class].to_s.casecmp?('Champion')

              deity = ctx[:to_assign]['archetype deity']
              deity = nil if deity.blank? || deity.to_s.casecmp?('open')

              deity.blank? ? nil : Array(Global.read_config('pf2e_deities', deity, 'allowed_sanctifications'))
            },
            # What to say when the deity it depends on is not settled yet.
            'needs' => 'pf2e.adv_archetype_sanctification_needs_select'
          }
        }.freeze

        def self.sanctification(ctx)
          rule = SANCTIFICATION[ctx[:archetype]]

          return [] unless rule

          if rule['locked_for'] && ctx[:base_class].to_s.casecmp?(rule['locked_for'])
            return [ [ 'pf2e.adv_archetype_sanctification_locked', { :charclass => ctx[:base_class] } ] ]
          end

          allowed = rule['allowed'].call(ctx)

          # nil means the answer depends on something not chosen yet.
          if allowed.nil?
            ctx[:to_assign]['archetype_sanctification'] = 'open'

            return [ [ rule['needs'], { :archetype => ctx[:archetype] } ] ]
          end

          held = ctx[:char].pf2_faith['sanctification']

          if !held.blank? && allowed.any? { |s| s.to_s.casecmp?(held.to_s) }
            ctx[:to_assign]['archetype_sanctification'] = held
            ctx[:advancement]['archetype_sanctification'] = held

            return [ [ 'pf2e.adv_archetype_sanctification_auto', { :sanctification => held, :archetype => ctx[:archetype] } ] ]
          end

          ctx[:to_assign]['archetype_sanctification'] = 'open'

          # A Champion forced to Holy gets its own line, since "pick one of: Holy" reads oddly.
          if ctx[:archetype] == 'Cleric Archetype' && ctx[:base_class].to_s.casecmp?('Champion')
            return [ [ 'pf2e.adv_archetype_sanctification_champion_cleric', {} ] ]
          end

          [ [ 'pf2e.adv_archetype_sanctification_select', { :archetype => ctx[:archetype], :options => allowed.join(", ") } ] ]
        end
      end
    end
  end
end
