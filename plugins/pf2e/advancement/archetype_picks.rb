module AresMUSH
  module Pf2e
    module Advancement

      # Settling what an archetype left open: its specialty, that specialty's own choice, the key
      # ability for its class DC, its deity and its sanctification.
      #
      # Taking the Dedication feat opens these - Advancement::Onboarding - and
      # `advance/archetype <what>=<value>` closes them. That command was one 430-line `handle`
      # with a five-way case, and each arm re-derived something that already had an owner: which
      # sanctifications a Champion or Cleric archetype allows, which numbered slot the archetype
      # sits in, the list of deities a champion may not worship, and - twice, in two subtly
      # different copies - how to apply an `initial_dedication` block.
      #
      # PICKS is one row per thing that may be settled, in the shape Chargen::BaseInfo uses:
      #
      #   ready    an Err when this archetype has no such pick at all, or it is not the
      #            character's to make; runs before anything else so the reason is the specific one
      #   pending  whether the draft is actually waiting for this pick
      #   idle     what to say when it is not
      #   options  the values it may take, or an Err when they cannot be settled yet
      #   invalid  what to say when the player named something else
      #   guards   further checks on the chosen value, in order, most specific complaint first
      #   apply    the state it produces
      #
      # Pure: config is read through state['config'], and the only thing that changes is the
      # returned state. What a settled pick then *hands over* - trained skills, spellcasting,
      # features - needs the live character, and that half is `deliver`.
      module ArchetypePicks

        # The only archetype whose specialty constrains alignment and sanctification.
        CHAMPION = 'Champion Archetype'.freeze

        PICKS = {
          # ----------------------------------------------------------------------------------
          # The archetype's specialty: a Barbarian's instinct, a Champion's cause, a Sorcerer's
          # bloodline.
          # ----------------------------------------------------------------------------------
          'specialty' => {
            'pending' => lambda { |ctx| ArchetypePicks.open?(ctx[:to_assign]['archetype_specialty']) },
            'idle' => 'pf2e.adv_no_archetype_specialty_needed',
            'options' => lambda { |ctx| (ctx[:config].read('pf2e_archetype_specialty', ctx[:archetype]) || {}).keys },
            'invalid' => lambda { |ctx, options|
              Err.new(:bad_specialty, 'pf2e.adv_invalid_archetype_specialty',
                'archetype' => ctx[:archetype], 'options' => options.sort.join(", "))
            },
            'guards' => [
              # Each of the Champion Archetype's causes demands an alignment, where the game
              # uses alignments at all.
              lambda { |ctx|
                next nil unless ctx[:archetype] == CHAMPION
                next nil unless ctx[:config].read('pf2e', 'use_alignment')

                alignment = ctx[:faith]['alignment']

                next Err.new(:alignment_missing, 'pf2e.alignment_missing') if alignment.blank?

                allowed = Onboarding.names(ArchetypePicks.specialty_info(ctx, ctx[:chosen])['allowed_alignments'])

                next nil if allowed.empty? || allowed.any? { |a| a.casecmp?(alignment) }

                Err.new(:champion_specialty_alignment_mismatch, 'pf2e.adv_champion_specialty_alignment_mismatch',
                  'specialty' => ctx[:chosen], 'options' => allowed.sort.join(", "))
              },
              # And some of them a sanctification. Only worth checking when one is settled -
              # when it is not, the sanctification pick makes the same comparison the other way
              # round, against the cause already chosen.
              lambda { |ctx|
                next nil unless ctx[:archetype] == CHAMPION

                allowed = Onboarding.names(ArchetypePicks.specialty_info(ctx, ctx[:chosen])['allowed_sanctifications'])

                next nil if allowed.empty?

                held = ArchetypePicks.settled_sanctification(ctx)

                next nil if held.blank?
                next nil if allowed.any? { |s| s.casecmp?(held) }

                Err.new(:champion_specialty_sanctification_mismatch, 'pf2e.adv_champion_specialty_sanctification_mismatch',
                  'specialty' => ctx[:chosen], 'sanctification' => held, 'options' => allowed.sort.join(", "))
              }
            ],
            'apply' => lambda { |ctx| ArchetypePicks.specialty(ctx) }
          },

          # ----------------------------------------------------------------------------------
          # The question a specialty itself asks: which animal, which dragon, which bloodline.
          # ----------------------------------------------------------------------------------
          'specialtychoice' => {
            'pending' => lambda { |ctx|
              _archetype, entry = ArchetypePicks.pending_choice(ctx[:to_assign], ctx[:archetype])

              entry && ArchetypePicks.open?(entry['choice'])
            },
            'idle' => 'pf2e.adv_no_archetype_specialty_choice_needed',
            'options' => lambda { |ctx|
              options = ArchetypePicks.choice_options(ctx)

              # The draft says a choice is open but the specialty offers nothing to choose:
              # there is genuinely nothing to do here.
              next Err.new(:nothing_to_assign, 'pf2e.adv_no_archetype_specialty_choice_needed') if options.empty?

              options.keys
            },
            'invalid' => lambda { |_ctx, options|
              Err.new(:bad_specialty_choice, 'pf2e.adv_invalid_archetype_specialty_choice', 'options' => options.sort.join(", "))
            },
            'apply' => lambda { |ctx| ArchetypePicks.specialty_choice(ctx) }
          },

          # ----------------------------------------------------------------------------------
          # The key ability for the archetype's own class DC, when it offers more than one.
          # ----------------------------------------------------------------------------------
          'key ability' => {
            # The slot holds the abilities on offer until one of them is picked.
            'pending' => lambda { |ctx| !Array(ctx[:to_assign]['archetype key ability']).empty? },
            'idle' => 'pf2e.adv_no_archetype_key_ability_needed',
            'options' => lambda { |ctx| Array(ctx[:to_assign]['archetype key ability']) },
            'invalid' => lambda { |ctx, options|
              Err.new(:bad_key_ability, 'pf2e.adv_invalid_archetype_key_ability',
                'archetype' => ctx[:archetype], 'options' => options.join(", "))
            },
            'apply' => lambda { |ctx| ArchetypePicks.key_ability(ctx) }
          },

          # ----------------------------------------------------------------------------------
          # Sanctification, for the two archetypes that have it.
          # ----------------------------------------------------------------------------------
          'sanctification' => {
            'ready' => lambda { |ctx|
              next Err.new(:nothing_to_assign, 'pf2e.adv_no_archetype_sanctification_needed') unless Onboarding::SANCTIFICATION.key?(ctx[:archetype])

              locked = Onboarding.sanctification_locked_for(ctx[:archetype])

              next nil unless locked && ctx[:base_class].to_s.casecmp?(locked)

              Err.new(:sanctification_locked, 'pf2e.adv_archetype_sanctification_locked', 'charclass' => ctx[:base_class])
            },
            'pending' => lambda { |ctx| ArchetypePicks.open?(ctx[:to_assign]['archetype_sanctification']) },
            'idle' => 'pf2e.adv_no_archetype_sanctification_needed',
            'options' => lambda { |ctx|
              allowed = Onboarding.allowed_sanctifications(ctx[:config], ctx[:archetype], ctx[:base_class], ctx[:to_assign])

              # nil means the answer depends on a deity they have not chosen yet.
              next Err.new(:sanctification_needs_deity, 'pf2e.adv_archetype_sanctification_needs_deity') if allowed.nil?

              ArchetypePicks.narrow_by_specialty(ctx, allowed)
            },
            'invalid' => lambda { |_ctx, options|
              Err.new(:bad_sanctification, 'pf2e.adv_invalid_archetype_sanctification', 'options' => options.join(", "))
            },
            'apply' => lambda { |ctx|
              ArchetypePicks
                .staged(ctx,
                  :pool => [ Slots.set('archetype_sanctification', ctx[:chosen]) ],
                  :draft => [ Slots.set('archetype_sanctification', ctx[:chosen]) ])
                .with_message('pf2e.adv_archetype_sanctification_assigned', 'sanctification' => ctx[:chosen])
            }
          },

          # ----------------------------------------------------------------------------------
          # A deity the archetype needs and the character does not already have.
          # ----------------------------------------------------------------------------------
          'deity' => {
            'pending' => lambda { |ctx| ArchetypePicks.open?(ctx[:to_assign]['archetype deity']) },
            'idle' => 'pf2e.adv_no_archetype_deity_needed',
            'options' => lambda { |ctx| (ctx[:config].read('pf2e_deities') || {}).keys },
            'invalid' => lambda { |_ctx, options|
              Err.new(:bad_deity, 'pf2e.adv_invalid_archetype_deity', 'options' => options.sort.join(", "))
            },
            'guards' => [
              # The Champion Archetype carries the class's own restriction with it.
              lambda { |ctx|
                next nil unless ctx[:archetype] == CHAMPION
                next nil unless ArchetypePicks.unholy?(ctx[:chosen])

                Err.new(:champion_deity_mismatch, 'pf2e.adv_champion_deity_mismatch', 'deity' => ctx[:chosen])
              },
              lambda { |ctx|
                next nil unless ctx[:config].read('pf2e', 'use_alignment')

                alignment = ctx[:faith]['alignment']

                next Err.new(:alignment_missing, 'pf2e.alignment_missing') if alignment.blank?

                allowed = Array(ctx[:config].read('pf2e_deities', ctx[:chosen], 'allowed_alignments'))

                next nil if allowed.include?(alignment)

                Err.new(:deity_alignment_mismatch, 'pf2e.adv_archetype_deity_mismatch',
                  'deity' => ctx[:chosen], 'alignment' => alignment, 'options' => allowed.join(", "))
              }
            ],
            'apply' => lambda { |ctx|
              ArchetypePicks
                .staged(ctx,
                  :pool => [ Slots.set('archetype deity', ctx[:chosen]) ],
                  :draft => [ Slots.set('archetype_deity', ctx[:chosen]) ])
                .with_message('pf2e.adv_archetype_deity_assigned', 'deity' => ctx[:chosen], 'archetype' => ctx[:archetype])
            }
          }
        }.freeze

        # ------------------------------------------------------------------------------
        # Settling one
        # ------------------------------------------------------------------------------

        def self.set(state, type, value)
          pick = PICKS[type.to_s]

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'archetype assignment', 'options' => PICKS.keys.join(", ")) unless pick

          ctx = context(state, value)

          # Every one of these belongs to the archetype the Dedication feat put in the draft.
          return Err.new(:no_archetype, 'pf2e.adv_no_archetype_assigned') if ctx[:archetype].blank?

          blocked = pick['ready'] ? pick['ready'].call(ctx) : nil
          return blocked if blocked

          return Err.new(:nothing_to_assign, pick['idle']) unless pick['pending'].call(ctx)

          options = pick['options'].call(ctx)
          return options if options.is_a?(Err)

          ctx[:chosen] = Array(options).find { |option| option.to_s.casecmp?(ctx[:value]) }

          return pick['invalid'].call(ctx, Array(options)) unless ctx[:chosen]

          Array(pick['guards']).each do |guard|
            failure = guard.call(ctx)

            return failure if failure
          end

          pick['apply'].call(ctx)
        end

        def self.context(state, value)
          {
            :state => state,
            :config => state['config'],
            :to_assign => state['to_assign'],
            :advancement => state['advancement'],
            :archetypes => state['archetypes'],
            :archetype => state['to_assign']['archetype'],
            :base_class => state['base_info']['charclass'],
            :faith => state['faith'],
            :value => value.to_s.strip
          }
        end

        # The state a settled pick produces. Both halves of the draft are nested hashes addressed
        # by path, so both go through the slot vocabulary - which brings its copy-on-write with
        # it, so the character's own hashes are never touched here. See Pf2e::Slots.
        def self.staged(ctx, pool: [], draft: [], archetypes: nil)
          to_assign = Slots.apply(ctx[:to_assign], pool)

          return to_assign if to_assign.is_a?(Err)

          advancement = Slots.apply(ctx[:advancement], draft)

          return advancement if advancement.is_a?(Err)

          Ok.new(:state => ctx[:state].merge(
              'to_assign' => to_assign,
              'advancement' => advancement,
              'archetypes' => archetypes || ctx[:archetypes]
            ))
        end

        # ------------------------------------------------------------------------------
        # What each pick does
        # ------------------------------------------------------------------------------

        def self.specialty(ctx)
          specialty = ctx[:chosen]
          choose = ArchetypePicks.specialty_info(ctx, specialty)['choose'] || {}
          options = choose['options'] || {}

          pool = [ Slots.set('archetype_specialty', specialty) ]
          archetypes = Archetypes.set_alongside(ctx[:archetypes], 'archetype_specialty', ctx[:archetype], specialty)

          # A specialty that asks a question of its own opens it, keyed by archetype so each of
          # four archetypes can have one outstanding. Skipped for an archetype the sheet has no
          # numbered slot for, since there would be nowhere to record the answer.
          asks = options.is_a?(Hash) && !options.empty? && !Archetypes.index_of(ctx[:archetypes], ctx[:archetype]).nil?

          if asks
            pool << Slots.set([ 'archetype specialty choice', ctx[:archetype] ],
              { 'specialty' => specialty, 'choice' => Slots::OPEN })
            archetypes = Archetypes.set_alongside(archetypes, 'archetype_specialty_choice', ctx[:archetype], "")
          end

          outcome = staged(ctx, :pool => pool, :archetypes => archetypes)

          if asks
            outcome = outcome.with_ooc('pf2e.adv_archetype_specialty_choice_select',
              'archetype' => ctx[:archetype],
              'specialty' => specialty,
              'choice' => choose['choice_name'] || "specialty choice",
              'options' => options.keys.sort.join(", "))
          end

          outcome.with_message('pf2e.adv_archetype_specialty_assigned', 'specialty' => specialty)
        end

        def self.specialty_choice(ctx)
          archetype, entry = pending_choice(ctx[:to_assign], ctx[:archetype])

          staged(ctx,
            :pool => [ Slots.set([ 'archetype specialty choice', archetype, 'choice' ], ctx[:chosen]) ],
            :archetypes => Archetypes.set_alongside(ctx[:archetypes], 'archetype_specialty_choice', archetype, ctx[:chosen]))
            .with_message('pf2e.adv_archetype_specialty_choice_assigned',
              'choice' => ctx[:chosen], 'specialty' => entry['specialty'])
        end

        def self.key_ability(ctx)
          path = Onboarding.class_dc_path(ctx[:archetype])
          draft = [ Slots.set(path + [ 'key_abil' ], ctx[:chosen]) ]

          # The proficiency belongs to the archetype and is written when the Dedication is taken;
          # filled in here for a draft that came from a path which did not write it.
          prof = ((ctx[:config].read('pf2e_archetype', ctx[:archetype], 'initial_dedication') || {})['combat_stats'] || {})['class_dc']
          draft << Slots.set(path + [ 'prof' ], prof) if prof && Slots.read(ctx[:advancement], path + [ 'prof' ]).nil?

          staged(ctx, :pool => [ Slots.set('archetype key ability', ctx[:chosen]) ], :draft => draft)
            .with_message('pf2e.adv_archetype_key_ability_assigned', 'ability' => ctx[:chosen], 'archetype' => ctx[:archetype])
        end

        # ------------------------------------------------------------------------------
        # Reading the draft
        # ------------------------------------------------------------------------------

        # A slot is waiting whether it holds the open marker on its own or among a list.
        def self.open?(value)
          Array(value).any? { |entry| entry.to_s.casecmp?(Slots::OPEN) }
        end

        # [ archetype, entry ] for the specialty choice this command is about: the archetype being
        # advanced when it has one, otherwise whichever archetype is waiting - a player with a
        # single outstanding choice should not have to name which archetype it belongs to.
        def self.pending_choice(to_assign, archetype)
          assignments = to_assign['archetype specialty choice']

          return [ nil, nil ] unless assignments.is_a?(Hash)

          key = assignments.key?(archetype) ? archetype : assignments.keys.first

          key ? [ key, assignments[key] || {} ] : [ nil, nil ]
        end

        def self.specialty_info(ctx, specialty)
          ctx[:config].read('pf2e_archetype_specialty', ctx[:archetype], specialty) || {}
        end

        # The options the waiting specialty choice offers.
        def self.choice_options(ctx)
          archetype, entry = pending_choice(ctx[:to_assign], ctx[:archetype])

          return {} unless entry

          info = ctx[:config].read('pf2e_archetype_specialty', archetype, entry['specialty']) || {}
          options = ((info['choose'] || {})['options'] || {})

          options.is_a?(Hash) ? options : {}
        end

        # The sanctification a specialty pick has to live with: the one staged in this
        # advancement, or the one the character already holds.
        def self.settled_sanctification(ctx)
          staged = ctx[:to_assign]['archetype_sanctification']

          return staged unless staged.blank? || open?(staged)

          held = ctx[:faith]['sanctification']

          held.blank? || open?(held) ? nil : held
        end

        # A Champion Archetype cause may allow fewer sanctifications than the archetype does, and
        # once the cause is chosen it governs.
        def self.narrow_by_specialty(ctx, allowed)
          return allowed unless ctx[:archetype] == CHAMPION

          specialty = ctx[:to_assign]['archetype_specialty']

          return allowed if specialty.blank? || open?(specialty)

          from_specialty = Onboarding.names(specialty_info(ctx, specialty)['allowed_sanctifications'])

          return allowed if from_specialty.empty?

          allowed.select { |s| from_specialty.any? { |narrowed| narrowed.casecmp?(s) } }
        end

        # Deities no follower of the Champion Archetype may worship - the same ruling chargen
        # makes for the Champion class itself, from the same list.
        def self.unholy?(deity)
          Chargen::BaseInfo::UNHOLY_DEITIES.any? { |unholy| unholy.casecmp?(deity.to_s) }
        end

        # ------------------------------------------------------------------------------
        # The half that needs the live character
        # ------------------------------------------------------------------------------

        # What a settled pick hands over, per type. Not pure, and for the reason Onboarding
        # gives: trained skills, spellcasting and features are held on live objects rather than
        # in the draft, so applying them means touching the character.
        #
        # A specialty and its choice carry an `initial_dedication` block exactly as the archetype
        # does, so Onboarding applies all three - which is how a specialty's `feat` and
        # `archetype_feature` keys started being honoured at all.
        DELIVERS = {
          'specialty' => lambda { |char, state| ArchetypePicks.deliver_specialty(char, state) },
          'specialtychoice' => lambda { |char, state| ArchetypePicks.deliver_specialty_choice(char, state) },
          'deity' => lambda { |char, state|
            Onboarding.deity_skill(char, state['to_assign']['archetype deity'], state['to_assign'], state['advancement'])
          }
        }.freeze

        # Mutates the draft hashes in the state it is handed and returns the messages to speak,
        # as [ locale_key, args ] pairs. The caller writes the draft and speaks them.
        def self.deliver(char, state, type)
          row = DELIVERS[type.to_s]

          row ? Array(row.call(char, state)) : []
        end

        def self.deliver_specialty(char, state)
          ctx = context(state, nil)
          specialty = state['to_assign']['archetype_specialty']

          return [] if specialty.blank? || open?(specialty)

          Onboarding.apply_payload(char, ctx[:archetype],
            specialty_info(ctx, specialty)['initial_dedication'],
            state['to_assign'], state['advancement'],
            :source => 'specialty', :name => specialty)
        end

        def self.deliver_specialty_choice(char, state)
          ctx = context(state, nil)
          archetype, entry = pending_choice(state['to_assign'], ctx[:archetype])

          return [] unless entry

          chosen = entry['choice']

          return [] if chosen.blank? || open?(chosen)

          option = choice_options(ctx)[chosen] || {}

          Onboarding.apply_payload(char, archetype, option['initial_dedication'],
            state['to_assign'], state['advancement'],
            :source => 'specialty choice', :name => chosen)
        end
      end
    end
  end
end
