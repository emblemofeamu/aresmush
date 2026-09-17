module AresMUSH
  module Pf2e

    # The grant ledger.
    #
    # A character's sheet is derived by folding an ordered, append-only list of grants. Undo marks
    # a transaction reverted and leaves the rows in place, which is how redo works. A grant carries
    # the level it takes effect from, so a boon awarded at level 5 goes dormant when the character
    # is rolled back to 4 and comes back when they climb again.
    #
    # A grant records an outcome: "Arcana to expert". It never records a recipe such as "apply the
    # class table at level 3", so editing game/config/pf2e_*.yml leaves the history of an existing
    # character alone.
    #
    # This file is pure: it takes and returns plain hashes. Ohm storage lives in
    # models/grant.rb and models/sheet_cache.rb; the character-facing API is in
    # helpers/ledger_store.rb.
    module Ledger

      # One row per grant kind, and the only place a kind is defined.
      #
      #   key    - the payload field `explain` matches on when you ask who granted a thing
      #   sheet  - the section of the derived sheet it writes (nil for XP, which is a scalar)
      #   apply  - how the fold folds it in
      #   sync   - how a whole-list assignment of that section is diffed back into grants
      #            ('list' for a flat array, 'bucketed' for a hash of arrays, 'ranked' for a
      #            map of name => rank). Absent means the section cannot be synced.
      #
      # Adding a kind is adding a row. There is no case statement to keep in step.
      KIND_SPECS = {
        'raise_skill' => {
          'key' => 'skill', 'sheet' => 'skills', 'sync' => 'ranked',
          'apply' => lambda { |sheet, p| sheet['skills'][p['skill']] = p['to'] }
        },
        'add_lore' => {
          'key' => 'lore', 'sheet' => 'lores', 'sync' => 'ranked',
          'apply' => lambda { |sheet, p| sheet['lores'][p['lore']] = p['to'] }
        },
        'boost_ability' => {
          'key' => 'ability', 'sheet' => 'boosts', 'sync' => 'counted',
          'apply' => lambda { |sheet, p| sheet['boosts'][p['ability']] = sheet['boosts'].fetch(p['ability'], 0) + 1 }
        },
        # An ancestry's flaw. Counted apart from boosts because the two are worth different amounts
        # at the 18 threshold, and because a score applies its flaws first.
        'flaw_ability' => {
          'key' => 'ability', 'sheet' => 'flaws', 'sync' => 'counted',
          'apply' => lambda { |sheet, p| sheet['flaws'][p['ability']] = sheet['flaws'].fetch(p['ability'], 0) + 1 }
        },
        # A score stated outright, which is what staff correcting a sheet need: most scores derive
        # from counts of boosts and flaws, and 15 is not a number any sequence of boosts reaches.
        #
        # It replaces the derivation *to that point* rather than fixing the score forever: the
        # counts so far are what it supersedes, so they are cleared, and a boost taken at a later
        # level still applies on top of it. The latest one wins.
        'set_ability_score' => {
          'key' => 'ability', 'sheet' => 'ability_overrides',
          'apply' => lambda { |sheet, p|
            sheet['ability_overrides'][p['ability']] = p['to'].to_i
            sheet['boosts'].delete(p['ability'])
            sheet['flaws'].delete(p['ability'])
          }
        },
        'grant_feat' => {
          'key' => 'feat', 'sheet' => 'feats', 'sync' => 'bucketed_multi', 'default_bucket' => 'charclass',
          'apply' => lambda { |sheet, p|
            # One entry per grant row, not per name: a feat the rules let you take more than
            # once (Domain Acumen, Assurance) is held once per taking, and collapsing those
            # would both undercount the sheet and let it be taken past its maximum.
            Ledger.add_occurrence(sheet['feats'], p['bucket'] || 'charclass', p['feat'])
            Ledger.add_to_bucket(sheet['feat_choices'], p['feat'], p['choice']) unless p['choice'].blank?
          }
        },
        'grant_feature' => {
          'key' => 'feature', 'sheet' => 'features', 'sync' => 'bucketed', 'default_bucket' => 'charclass_features',
          'apply' => lambda { |sheet, p| Ledger.add_to_bucket(sheet['features'], p['bucket'] || 'charclass_features', p['feature']) }
        },
        'add_language' => {
          'key' => 'language', 'sheet' => 'languages', 'sync' => 'list',
          'apply' => lambda { |sheet, p| Ledger.add_to_list(sheet['languages'], p['language']) }
        },
        'add_trait' => {
          'key' => 'trait', 'sheet' => 'traits', 'sync' => 'list',
          'apply' => lambda { |sheet, p| Ledger.add_to_list(sheet['traits'], p['trait']) }
        },
        'add_special' => {
          'key' => 'special', 'sheet' => 'specials', 'sync' => 'list',
          'apply' => lambda { |sheet, p| Ledger.add_to_list(sheet['specials'], p['special']) }
        },
        'spell_access' => {
          'key' => 'spell', 'sheet' => 'spells', 'sync' => 'sourced',
          'apply' => lambda { |sheet, p|
            by_rank = (sheet['spells'][p['source']] ||= {})

            Ledger.add_to_list(by_rank[p['rank'].to_s] ||= [], p['spell'])
          }
        },
        'set_prof' => {
          'key' => 'key', 'sheet' => 'profs',
          'apply' => lambda { |sheet, p| (sheet['profs'][p['group']] ||= {})[p['key']] = p['to'] }
        }
      }.freeze

      # XP and money are deliberately absent. They are counters, not build history: a character
      # accumulates thousands of transactions where they accumulate a hundred grants, and
      # folding them meant every sheet read - one that only wanted to know which feats a
      # character has - walked the lot. They live in Pf2e::Audit now, with the running total on
      # the character. See docs/plans/2026-09-16-xp-and-money-balances.md.

      # Kept as the old name so callers and specs that ask "what is this kind's payload key"
      # keep working.
      KINDS = KIND_SPECS.each_with_object({}) { |(kind, spec), h| h[kind] = spec['key'] }.freeze

      # Sections that can be synced from a whole-list assignment, with the shape each uses.
      SYNC_SECTIONS = KIND_SPECS.each_with_object({}) do |(kind, spec), h|
        next unless spec['sync']
        h[spec['sheet']] = { 'kind' => kind, 'item' => spec['key'], 'shape' => spec['sync'] }
      end.freeze

      def self.add_to_bucket(hash, bucket, item)
        list = (hash[bucket] ||= [])
        list << item unless list.include?(item)
      end

      # Appends unconditionally: for a section where holding the same thing twice is
      # meaningful, the grant rows are the count.
      def self.add_occurrence(hash, bucket, item)
        (hash[bucket] ||= []) << item
      end

      def self.add_to_list(list, item)
        list << item unless list.include?(item)
      end

      def self.empty_sheet(level)
        {
          'level' => level.to_i,
          'skills' => {},
          'lores' => {},
          'boosts' => {},
          'flaws' => {},
          'ability_overrides' => {},
          'feats' => {},
          'feat_choices' => {},
          'features' => {},
          'languages' => [],
          'traits' => [],
          'specials' => [],
          'spells' => {},
          'profs' => {},
          'unsupported' => []
        }
      end

      # The grants that count at a given level: live ones, in sequence order, whose effect
      # has started. A nil or zero effective_level means global - it applies at every level.
      def self.applicable(grants, at_level)
        at = at_level.to_i

        grants
          .reject { |g| !g['reverted_by'].blank? }
          .select { |g| global?(g) || g['effective_level'].to_i <= at }
          .sort_by { |g| g['seq'].to_i }
      end

      def self.global?(grant)
        grant['effective_level'].nil? || grant['effective_level'].to_i == 0
      end

      # Folds grant rows (plain hashes) into a derived sheet. Pure: no Redis, no character.
      def self.fold(grants, at_level:)
        sheet = Ledger.empty_sheet(at_level)

        Ledger.applicable(grants, at_level).each { |grant| Ledger.apply(sheet, grant) }

        sheet
      end

      def self.apply(sheet, grant)
        spec = KIND_SPECS[grant['kind']]

        if spec.nil?
          # An unknown kind is neither dropped nor fatal: a sheet with a gap the staff can
          # see beats a sheet that is quietly wrong, and beats a command that explodes.
          sheet['unsupported'] << { 'kind' => grant['kind'], 'payload' => grant['payload'] || {}, 'seq' => grant['seq'] }
          return sheet
        end

        spec['apply'].call(sheet, grant['payload'] || {})

        sheet
      end

      # ------------------------------------------------------------------------------
      # Materialising
      # ------------------------------------------------------------------------------

      # Attributes on Character that are written straight from the derived sheet.
      SHEET_ATTRS = {
        'pf2_feats' => 'feats',
        'pf2_features' => 'features',
        'pf2_traits' => 'traits',
        'pf2_special' => 'specials',
        'pf2_lang' => 'languages',
        'pf2_boosts' => 'boosts',
        'pf2_level_tracker' => nil # kept for the old readers; filled by the store
      }.freeze

      # While a draft is open - an advancement between `advance` and `advance/done` - the
      # character's own lists ARE the draft, holding picks the fold has not seen. Writing the fold
      # over them mid-flight destroys the player's work, so a draft plan touches nothing here. It
      # stays as an empty list because it is where a sheet attribute no draft step writes belongs.
      DRAFT_SAFE_ATTRS = [].freeze

      # Diffs the derived sheet against what the live objects hold. Pure, so the hard part
      # of materialising is testable; the applier that runs these ops is dumb on purpose.
      def self.plan(sheet, current, draft: false)
        ops = []

        if !draft
          skills = effective_skills(sheet)
          held = current['skills'] || {}

          skills.each_pair do |skill, rank|
            ops << { 'op' => 'set_skill', 'skill' => skill, 'to' => rank } if held[skill] != rank
          end

          # A skill the character holds but the sheet does not grant is untrained rather than
          # deleted - and because the ledger keeps every grant, a boon's skill survives a
          # rollback instead of vanishing the way the snapshot restore destroyed it.
          held.each_pair do |skill, _rank|
            ops << { 'op' => 'set_skill', 'skill' => skill, 'to' => 'untrained' } unless skills.key?(skill)
          end
        end

        # Known spells are not one attribute - they live per source, in whichever list that
        # source's casting mode uses - so they get their own op rather than a SHEET_ATTRS row.
        if !draft
          (sheet['spells'] || {}).each_pair do |source, by_rank|
            next if changed?((current['spells'] || {})[source], by_rank) == false

            ops << { 'op' => 'set_known', 'source' => source, 'lists' => by_rank }
          end
        end

        # Ability scores, derived from nothing. Every ability starts at 10, its ancestry flaw applies
        # and then its boosts, and PF2e's rule for each depends only on the score being changed - so
        # counts per ability are enough and a rollback that drops a boost puts the score back.
        if !draft
          (current['ability_scores'] || {}).each_key do |ability|
            override = (sheet['ability_overrides'] || {})[ability]

            # An override is the starting point for whatever came after it; without one a score is
            # 10 plus its boosts, less its flaws.
            wanted = if override
              Pf2eAbilities.boosted_score(override.to_i, (sheet['boosts'] || {})[ability].to_i)
            else
              Pf2eAbilities.derived_score((sheet['flaws'] || {})[ability].to_i,
                                          (sheet['boosts'] || {})[ability].to_i)
            end

            next if current['ability_scores'][ability].to_i == wanted.to_i

            ops << { 'op' => 'set_ability', 'ability' => ability, 'to' => wanted }
          end
        end

        SHEET_ATTRS.each_pair do |attr, key|
          next if key.nil?
          next if draft && !DRAFT_SAFE_ATTRS.include?(attr)
          next unless sheet.key?(key)
          ops << { 'op' => 'set_attr', 'attr' => attr, 'value' => sheet[key] } if changed?(current[key], sheet[key])
        end

        ops
      end

      # Lores are ordinary skill rows in this game - pf2e_skills.yml lists 239 of them - so
      # the two maps materialise through the same path.
      def self.effective_skills(sheet)
        (sheet['skills'] || {}).merge(sheet['lores'] || {})
      end

      # nil and an empty hash/array mean the same thing on a fresh character, so treating
      # them as different would make every materialise write attributes that never moved.
      def self.changed?(held, wanted)
        return false if held.blank? && wanted.blank?

        held != wanted
      end

      # A cache entry is good only for the exact ledger head and level it was built from.
      def self.cache_stale?(cached, head_seq:, level:)
        return true if cached.nil?

        cached['head_seq'].to_i != head_seq.to_i || cached['level'].to_i != level.to_i
      end

      # Source types that belong to the level ladder, and so are what a rollback undoes.
      # A boon or a staff grant is deliberately not in here: rolling back level 5 must not
      # destroy an award that merely happens to take effect at level 5. The fold's level
      # filter already makes such a grant dormant while the character sits below it, and
      # brings it back when they level again.
      LADDER_SOURCES = [ 'level_up' ].freeze

      # The transactions a rollback to `level` should mark reverted.
      def self.rollback_targets(grants, level, ladder: LADDER_SOURCES)
        grants
          .select { |g| g['reverted_by'].blank? }
          .select { |g| ladder.include?(g['source_type']) }
          .reject { |g| global?(g) }
          .select { |g| g['effective_level'].to_i >= level.to_i }
          .map { |g| g['txn'] }
          .uniq
      end

      # ------------------------------------------------------------------------------
      # Syncing whole lists (the migration bridge)
      # ------------------------------------------------------------------------------

      # Turns "here is the whole list now" into ledger entries. Legacy code that assigns a
      # complete list onto the character calls this instead, so its work survives the next
      # fold rather than being erased by it.
      #
      # The three shapes a section can have are declared in KIND_SPECS, so this reads the
      # shape rather than branching per section.
      SYNC_SHAPES = {
        # A flat array: languages, traits, specials.
        'list' => lambda { |sheet, section, value, spec|
          held = Array(sheet[section])
          wanted = Array(value)
          [ (wanted - held).map { |i| { spec['item'] => i } },
            (held - wanted).map { |i| { spec['item'] => i } } ]
        },
        # A hash of arrays keyed by bucket: feats, features.
        'bucketed' => lambda { |sheet, section, value, spec|
          grants = []
          gone = []

          (value || {}).each_pair do |bucket, items|
            held = ((sheet[section] || {})[bucket]) || []
            wanted = Array(items)
            grants.concat((wanted - held).map { |i| { 'bucket' => bucket, spec['item'] => i } })
            gone.concat((held - wanted).map { |i| { spec['item'] => i } })
          end

          [ grants, gone ]
        },
        # Two levels of key: a source, then a rank. Spells known are the only thing shaped this
        # way, because which source knows a spell decides what it is cast at.
        'sourced' => lambda { |sheet, section, value, spec|
          grants = []
          gone = []

          held_all = sheet[section] || {}

          (value || {}).each_pair do |source, by_rank|
            (by_rank || {}).each_pair do |rank, items|
              held = Array((held_all[source] || {})[rank.to_s])

              grants.concat((Array(items) - held).map { |i| { 'source' => source, 'rank' => rank.to_s, spec['item'] => i } })
            end
          end

          # Anything the fold has that the character does not. Scoped to the sources the fragment
          # mentions, so a source it says nothing about is left alone.
          held_all.each_pair do |source, by_rank|
            next unless (value || {}).key?(source)

            (by_rank || {}).each_pair do |rank, items|
              wanted = Array(((value[source]) || {})[rank] || ((value[source]) || {})[rank.to_s])

              gone.concat((Array(items) - wanted).map { |i| { spec['item'] => i } })
            end
          end

          [ grants, gone ]
        },
        # Like 'bucketed', but counting: two copies of a repeatable feat are two grants, and
        # a sheet holding one where the fold holds two revokes exactly one.
        'bucketed_multi' => lambda { |sheet, section, value, spec|
          grants = []
          gone = []

          (value || {}).each_pair do |bucket, items|
            held = Array((sheet[section] || {})[bucket])
            added, removed = Ledger.multiset_diff(Array(items), held)

            grants.concat(added.map { |i| { 'bucket' => bucket, spec['item'] => i } })

            # One copy per revocation: reverting every grant with this name would take the
            # other takings of a repeatable feat with it.
            gone.concat(removed.map { |i| { 'match' => { spec['item'] => i }, 'limit' => 1 } })
          end

          [ grants, gone ]
        },
        # A map of name to how many: attribute boosts. A second boost of the same ability is
        # another grant, not a changed value, so the diff is a difference of counts - `list` and
        # `bucketed` would collapse the duplicates and `ranked` would read four boosts of
        # Strength as one.
        'counted' => lambda { |sheet, section, value, spec|
          held = sheet[section] || {}
          wanted = value || {}

          grants = []
          gone = []

          (held.keys | wanted.keys).each do |name|
            delta = wanted[name].to_i - held[name].to_i

            if delta.positive?
              delta.times { grants << { spec['item'] => name } }
            elsif delta.negative?
              # One at a time, so taking one boost back does not revert the others.
              (-delta).times { gone << { 'match' => { spec['item'] => name }, 'limit' => 1 } }
            end
          end

          [ grants, gone ]
        },
        # A map of name to rank: skills, lores. A changed rank is a new grant, not a duplicate.
        'ranked' => lambda { |sheet, section, value, spec|
          held = sheet[section] || {}
          wanted = value || {}

          grants = wanted.reject { |name, rank| held[name] == rank }
            .map { |name, rank| { spec['item'] => name, 'to' => rank } }
          gone = held.keys.reject { |name| wanted.key?(name) }
            .map { |name| { spec['item'] => name } }

          [ grants, gone ]
        }
      }.freeze

      # Which items `wanted` has that `held` does not, and vice versa, counting duplicates.
      # Returns [ to_add, to_remove ].
      def self.multiset_diff(wanted, held)
        surplus = wanted.dup
        missing = []

        held.each do |item|
          index = surplus.index(item)

          index ? surplus.delete_at(index) : missing << item
        end

        [ surplus, missing ]
      end

      def self.sync_plan(sheet, fragment)
        grants = []
        revocations = []

        fragment.each_pair do |section, value|
          spec = SYNC_SECTIONS[section]
          next unless spec

          added, removed = SYNC_SHAPES[spec['shape']].call(sheet, section, value, spec)

          added.each { |payload| grants << { 'kind' => spec['kind'], 'payload' => payload } }

          removed.each do |entry|
            # A shape may hand back a bare match, or a match with a limit on how many of the
            # grants behind it to revert.
            match = entry.is_a?(Hash) && entry.key?('match') ? entry['match'] : entry
            limit = entry.is_a?(Hash) ? entry['limit'] : nil

            revocation = { 'kind' => spec['kind'], 'match' => match }
            revocation['limit'] = limit if limit

            revocations << revocation
          end
        end

        { 'grants' => grants, 'revocations' => revocations }
      end

      # Live grants of one kind whose payload matches every given pair, case-insensitively on
      # strings. The way a single earlier grant - a chargen pick being taken back - is undone
      # without deleting anything.
      def self.matching_grants(grants, kind, match = {})
        grants
          .select { |g| g['reverted_by'].blank? }
          .select { |g| g['kind'] == kind }
          .select do |g|
            payload = g['payload'] || {}
            match.all? do |key, value|
              held = payload[key]
              held.is_a?(String) && value.is_a?(String) ? held.casecmp?(value) : held == value
            end
          end
      end

      # Which grants put a thing on the sheet, newest first.
      def self.explain(grants, at_level:, kind:, key:)
        payload_key = KINDS[kind]

        Ledger.applicable(grants, at_level)
          .select { |g| g['kind'] == kind }
          .select { |g| payload_key.nil? || (g['payload'] || {})[payload_key].to_s.casecmp?(key.to_s) }
          .reverse
      end

    end
  end
end
