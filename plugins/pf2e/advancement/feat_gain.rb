module AresMUSH
  module Pf2e
    module Advancement

      # Everything gaining a feat implies, in one place.
      #
      # A feat reaches a character three ways: typed at `advance/feat`, handed over by a choice
      # that draws from a feat pool (a Swashbuckler's Stylish Tricks, an Investigator's Skillful
      # Lessons), or granted outright by an archetype. All three run the same consequences, which
      # is what this module is for - 56 feats with `grants` and 16 Dedications are reachable
      # through a choice pool, so a path that applies only a subset is a path that hands out an
      # incomplete feat.
      #
      # EFFECTS is the whole list, in order. Every path runs all of it.
      #
      # Not pure: skills, magic and features live on Ohm objects rather than in CharState, so
      # applying them means touching the character. What this makes legible and testable is the
      # sequence and the decisions.
      module FeatGain

        # A feat's consequences, applied in this order. `when` decides whether a row runs;
        # `apply` returns messages, and may push a callable onto ctx[:after_save] for work that
        # has to happen once the draft is written (staging a choice re-reads the character).
        EFFECTS = [
          {
            'name' => 'record',
            'when' => lambda { |_ctx| true },
            'apply' => lambda { |ctx| FeatGain.record(ctx) }
          },
          {
            'name' => 'dedication',
            'when' => lambda { |ctx| FeatGain.dedication?(ctx[:details]) && ctx[:to_assign]['archetype'].blank? },
            'apply' => lambda { |ctx| FeatGain.dedication(ctx) }
          },
          {
            'name' => 'grants',
            'when' => lambda { |ctx| ctx[:details]['grants'] },
            'apply' => lambda { |ctx| FeatGain.grants(ctx) }
          },
          {
            'name' => 'magic',
            'when' => lambda { |ctx| ctx[:details]['magic_stats'] },
            'apply' => lambda { |ctx| FeatGain.magic(ctx) }
          },
          {
            'name' => 'at_level',
            'when' => lambda { |_ctx| true },
            'apply' => lambda { |ctx| FeatGain.at_level(ctx) }
          },
          {
            'name' => 'choice',
            'when' => lambda { |_ctx| true },
            'apply' => lambda { |ctx| FeatGain.choice(ctx) }
          }
        ].freeze

        # Applies every effect to the draft hashes passed in. Returns
        # { :messages => [...], :after_save => [callables] } - the caller writes the draft, then
        # runs the callables.
        #
        # `bucket` is the feat list it belongs in. advance/feat uses the slot the player is
        # filling; a feat arriving from a choice uses the feat's own first type.
        def self.apply(char, fname, details, bucket:, to_assign:, advancement:, client: nil)
          # DraftSheet is the one place that knows whether a level is open, and which level a rule
          # is measured against while it is. Chargen has nothing that drains staged grants, so it
          # applies a feat's block outright - see `grants`.
          draft = DraftSheet.of(char)
          chargen = !draft.drafting?

          ctx = {
            :char => char,
            :feat => fname,
            :details => details,
            :bucket => bucket.to_s,
            :to_assign => to_assign,
            :advancement => advancement,
            :client => client,
            :chargen => chargen,
            :level => draft.level,
            :after_save => []
          }

          messages = EFFECTS.flat_map do |effect|
            next [] unless effect['when'].call(ctx)

            Array(effect['apply'].call(ctx))
          end

          { :messages => messages.compact, :after_save => ctx[:after_save] }
        end

        def self.dedication?(details)
          Array(details['feat_type']).any? { |t| t.to_s.casecmp?('Dedication') }
        end

        # ------------------------------------------------------------------------------
        # The effects
        # ------------------------------------------------------------------------------

        def self.record(ctx)
          feats = (ctx[:advancement]['feats'] ||= {})
          feats[ctx[:bucket]] = Array(feats[ctx[:bucket]]) + [ ctx[:feat] ]

          []
        end

        def self.dedication(ctx)
          archetype = Array(ctx[:details]['assoc_archetype']).first

          return [] if archetype.blank?

          ctx[:to_assign]['archetype'] = archetype

          # Written here rather than left for the caller's save: the archetype slots are a
          # character attribute, not part of the draft the caller promised to write, so a caller
          # that does not save loses the archetype.
          ctx[:char].update(:pf2_archetypeinfo => Onboarding.claim_slot(ctx[:char].pf2_archetypeinfo || {}, archetype))

          messages = Onboarding.apply(ctx[:char], archetype, ctx[:to_assign], ctx[:advancement])

          messages + [ [ 'pf2e.adv_archetype_assigned', { :archetype => archetype } ] ]
        end

        # A feat's grants split into what lands now and what waits for advance/done. Skills
        # among them are trained through the shared helper, so a grant of a skill the character
        # already has turns into a free pick rather than being lost.
        #
        # Chargen does not split them at all. The 'advance' half is staged against an
        # advance/done that chargen never runs, and pf2_advancement is discarded outright when
        # the character is approved, so a grant staged during chargen is simply lost. Chargen
        # applies the whole block immediately instead - the same path cg_lock_base_options takes
        # for the feats an ancestry or background hands over.
        def self.grants(ctx)
          return apply_grants_now(ctx, ctx[:details]['grants']) if ctx[:chargen]

          assessed = Pf2e.assess_feat_grants(ctx[:details]['grants'])

          now = assessed['assign'].empty? ? nil : assessed['assign']
          later = assessed['advance'].empty? ? nil : assessed['advance']
          messages = []

          if later && later['skill']
            result = Pf2e.add_training_skills(ctx[:char], later['skill'], ctx[:to_assign], ctx[:advancement])

            if result[:free_count].to_i > 0
              messages << [ 'pf2e.adv_free_skill_open', { :item => "#{ctx[:feat]} feat" } ]
            end

            if result[:open_count].to_i > 0 || result[:open_lore_count].to_i > 0
              messages << [ 'pf2e.adv_duplicate_skill_open', { :item => "#{ctx[:feat]} feat" } ]
            end

            later = later.reject { |key, _v| key == 'skill' }
            later = nil if later.empty?
          end

          messages << [ 'pf2e.advancement_feat_grants_addl', { :element => 'item' } ] if later

          # The 'assign' half opens slots the player fills before advance/done, so it is applied
          # now and speaks for itself. Nothing drains to_assign['grants'], and Outstanding counts
          # whatever sits there as an unresolved item, which refuses advance/done.
          messages.concat(apply_grants_now(ctx, now)) if now

          if later
            grants = (ctx[:advancement]['grants'] ||= {})
            grants[ctx[:feat]] = later
          end

          messages
        end

        # Applies a grants block through the live-character path, once the draft is written.
        #
        # Deferred rather than called here, because do_feat_grants writes the character and
        # re-reads pf2_to_assign itself. Run inline it would read the draft the caller has not
        # saved yet, and its own write would then be clobbered by the caller's save.
        # ctx[:after_save] is the hook for exactly this - see `choice`.
        def self.apply_grants_now(ctx, payload)
          return [] if payload.blank?

          char = ctx[:char]
          client = ctx[:client]
          charclass = char.pf2_base_info['charclass']

          ctx[:after_save] << lambda do
            # do_feat_grants renders its own text, so it is passed through already rendered.
            # Deduplicated because a grant of two open skills - Natural Skill's two - answers
            # with the same sentence once per skill, and saying it twice tells the player
            # nothing the count in cg/review does not.
            Pf2e.do_feat_grants(char, payload, charclass, client).uniq.map { |msg| [ nil, msg ] }
          end

          []
        end

        def self.apply_slots(ctx, *deltas)
          updated = Slots.apply(ctx[:to_assign], deltas.flatten)

          ctx[:to_assign].replace(updated) unless updated.is_a?(Err)

          updated
        end

        def self.magic(ctx)
          options = Pf2e.stage_feat_magic_stats(ctx[:char], ctx[:feat], ctx[:details], ctx[:to_assign], ctx[:advancement])

          return [ [ 'pf2e.feat_grants_magic', {} ] ] if options.empty?

          # Already rendered text rather than locale keys.
          Pf2e.magic_option_messages(options).map { |msg| [ nil, msg ] }
        end

        # Clauses keyed to a level the character has already reached, including the one they
        # are gaining now. These stage a grants block like any other, so chargen applies them
        # outright for the same reason `grants` does.
        def self.at_level(ctx)
          Pf2e.feat_at_level_catch_up(ctx[:details], ctx[:level]).map do |level, payload|
            if ctx[:chargen]
              apply_grants_now(ctx, payload)
            else
              grants = (ctx[:advancement]['grants'] ||= {})
              grants["#{ctx[:feat]} (level #{level})"] = payload
            end

            [ 'pf2e.feat_level_clause_applied', { :feat => ctx[:feat], :level => level } ]
          end
        end

        # A feat carrying its own choice. One decided by current state is resolved here rather
        # than asked about; one with nothing left to give is not opened at all.
        def self.choice(ctx)
          block = Pf2e.feat_choice_def(ctx[:details])
          instance = Pf2e.feat_taken_count(ctx[:char], ctx[:feat]) + 1

          block = nil unless Pf2e.feat_choice_opens_at?(block, instance)

          return [] unless block

          automatic = Pf2e.auto_choice?(block)
          label = automatic ? Pf2e.auto_choice_label(ctx[:char], block, ctx[:advancement]) : nil

          # Opening the feat's own choice is the same operation as opening any other slot, and
          # FeatSlots is what says so.
          if !automatic || label
            apply_slots(ctx, FeatSlots.deltas(ctx[:feat], ctx[:details], :opens_choice => true))
          end

          return opened(ctx, block) unless automatic
          return [ [ 'pf2e.choice_auto_none', { :choice => ctx[:feat] } ] ] unless label

          # Resolving the choice re-reads and saves the character, so it waits until the draft is
          # written.
          feat = ctx[:feat]
          char = ctx[:char]
          client = ctx[:client]

          ctx[:after_save] << lambda do
            Pf2e.resolve_feat_choice(char, feat, block, label, client).map { |msg| [ nil, msg ] } +
              [ [ 'pf2e.choice_auto_resolved', { :choice => feat, :value => label } ] ]
          end

          []
        end

        def self.opened(ctx, block)
          [ [ 'pf2e.choice_opened', {
                :choice => ctx[:feat],
                :summary => Pf2e.choice_summary(block),
                :cmd => Pf2e.choice_info_cmd(ctx[:char])
              } ] ]
        end

        # ------------------------------------------------------------------------------
        # Speaking
        # ------------------------------------------------------------------------------

        # A message is [ locale_key, args ], or [ nil, text ] for one already rendered.
        def self.render(messages)
          Array(messages).map { |key, args| key.nil? ? args : t(key, **(args || {})) }
        end

        def self.emit!(client, messages)
          render(messages).each { |msg| client.emit_ooc msg }
        end
      end
    end
  end
end
