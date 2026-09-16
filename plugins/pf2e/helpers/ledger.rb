module AresMUSH
  module Pf2e

    # The grant ledger.
    #
    # A character's sheet is not stored; it is *derived* by folding an ordered, append-only
    # list of grants. Undo marks a transaction reverted rather than deleting it, which is
    # what makes redo possible. A grant carries the level it takes effect from, so a boon
    # awarded at level 5 goes dormant if the character is rolled back to 4 instead of being
    # destroyed.
    #
    # Grants record *outcomes, not recipes* - "Arcana to expert", never "apply the class
    # table at level 3" - so that editing game/config/pf2e_*.yml never rewrites the history
    # of an existing character.
    #
    # This file is pure: it takes and returns plain hashes. Ohm storage lives in
    # models/grant.rb and models/sheet_cache.rb; the character-facing API is in
    # helpers/ledger_store.rb.
    module Ledger

      # Every grant kind the fold understands. A payload key named here is what `explain`
      # matches on when you ask who granted a given thing.
      KINDS = {
        'raise_skill'   => 'skill',
        'add_lore'      => 'lore',
        'boost_ability' => 'ability',
        'grant_feat'    => 'feat',
        'grant_feature' => 'feature',
        'add_language'  => 'language',
        'add_trait'     => 'trait',
        'add_special'   => 'special',
        'spell_access'  => 'spell',
        'set_prof'      => 'key',
        'xp_award'      => 'amount',
        'xp_spend'      => 'amount'
      }.freeze

      def self.empty_sheet(level)
        {
          'level' => level.to_i,
          'xp' => 0,
          'skills' => {},
          'lores' => {},
          'boosts' => {},
          'feats' => {},
          'feat_choices' => {},
          'features' => {},
          'languages' => [],
          'traits' => [],
          'specials' => [],
          'spell_access' => [],
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
        payload = grant['payload'] || {}

        case grant['kind']
        when 'raise_skill'
          sheet['skills'][payload['skill']] = payload['to']
        when 'add_lore'
          sheet['lores'][payload['lore']] = payload['to']
        when 'boost_ability'
          ability = payload['ability']
          sheet['boosts'][ability] = sheet['boosts'].fetch(ability, 0) + 1
        when 'grant_feat'
          bucket = payload['bucket'] || 'charclass'
          list = (sheet['feats'][bucket] ||= [])
          list << payload['feat'] unless list.include?(payload['feat'])
          if !payload['choice'].blank?
            choices = (sheet['feat_choices'][payload['feat']] ||= [])
            choices << payload['choice'] unless choices.include?(payload['choice'])
          end
        when 'grant_feature'
          bucket = payload['bucket'] || 'charclass_features'
          list = (sheet['features'][bucket] ||= [])
          list << payload['feature'] unless list.include?(payload['feature'])
        when 'add_language'
          sheet['languages'] << payload['language'] unless sheet['languages'].include?(payload['language'])
        when 'add_trait'
          sheet['traits'] << payload['trait'] unless sheet['traits'].include?(payload['trait'])
        when 'add_special'
          sheet['specials'] << payload['special'] unless sheet['specials'].include?(payload['special'])
        when 'spell_access'
          sheet['spell_access'] << payload
        when 'set_prof'
          group = (sheet['profs'][payload['group']] ||= {})
          group[payload['key']] = payload['to']
        when 'xp_award'
          sheet['xp'] = sheet['xp'] + payload['amount'].to_i
        when 'xp_spend'
          sheet['xp'] = sheet['xp'] - payload['amount'].to_i
        else
          # An unknown kind is neither dropped nor fatal: a sheet with a gap the staff can
          # see beats a sheet that is quietly wrong, and beats a command that explodes.
          sheet['unsupported'] << { 'kind' => grant['kind'], 'payload' => payload, 'seq' => grant['seq'] }
        end

        sheet
      end

      # ------------------------------------------------------------------------------
      # Materialising
      # ------------------------------------------------------------------------------

      # Attributes on Character that are written straight from the derived sheet.
      SHEET_ATTRS = {
        'pf2_xp' => 'xp',
        'pf2_feats' => 'feats',
        'pf2_features' => 'features',
        'pf2_traits' => 'traits',
        'pf2_special' => 'specials',
        'pf2_lang' => 'languages',
        'pf2_boosts' => 'boosts',
        'pf2_level_tracker' => nil # kept for the old readers; filled by the store
      }.freeze

      # Diffs the derived sheet against what the live objects hold. Pure, so the hard part
      # of materialising is testable; the applier that runs these ops is dumb on purpose.
      def self.plan(sheet, current)
        ops = []

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

        SHEET_ATTRS.each_pair do |attr, key|
          next if key.nil?
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

      # Sections a caller may sync, with the grant kind and payload shape each uses.
      SYNC_SECTIONS = {
        'feats' => { 'kind' => 'grant_feat', 'item' => 'feat', 'bucket' => 'bucket' },
        'features' => { 'kind' => 'grant_feature', 'item' => 'feature', 'bucket' => 'bucket' },
        'traits' => { 'kind' => 'add_trait', 'item' => 'trait' },
        'specials' => { 'kind' => 'add_special', 'item' => 'special' },
        'languages' => { 'kind' => 'add_language', 'item' => 'language' }
      }.freeze

      # Turns "here is the whole list now" into ledger entries. Legacy code that assigns a
      # complete list onto the character calls this instead, so its work survives the next
      # fold rather than being erased by it.
      def self.sync_plan(sheet, fragment)
        grants = []
        revocations = []

        fragment.each_pair do |section, value|
          # Skills are a map of name to rank rather than a list, so a changed rank is a new
          # grant and a dropped skill is a revocation.
          if section == 'skills' || section == 'lores'
            kind = section == 'lores' ? 'add_lore' : 'raise_skill'
            item = section == 'lores' ? 'lore' : 'skill'
            held = sheet[section] || {}
            wanted = value || {}

            wanted.each_pair do |name, rank|
              next if held[name] == rank
              grants << { 'kind' => kind, 'payload' => { item => name, 'to' => rank } }
            end

            held.each_pair do |name, _rank|
              next if wanted.key?(name)
              revocations << { 'kind' => kind, 'match' => { item => name } }
            end

            next
          end

          spec = SYNC_SECTIONS[section]
          next unless spec

          if spec['bucket']
            (value || {}).each_pair do |bucket, items|
              held = ((sheet[section] || {})[bucket]) || []
              added, removed = delta(held, Array(items))

              added.each { |item| grants << { 'kind' => spec['kind'], 'payload' => { 'bucket' => bucket, spec['item'] => item } } }
              removed.each { |item| revocations << { 'kind' => spec['kind'], 'match' => { spec['item'] => item } } }
            end
          else
            held = Array(sheet[section])
            added, removed = delta(held, Array(value))

            added.each { |item| grants << { 'kind' => spec['kind'], 'payload' => { spec['item'] => item } } }
            removed.each { |item| revocations << { 'kind' => spec['kind'], 'match' => { spec['item'] => item } } }
          end
        end

        { 'grants' => grants, 'revocations' => revocations }
      end

      def self.delta(held, wanted)
        [ wanted - held, held - wanted ]
      end

      # Live grants of one kind whose payload matches every given pair, case-insensitively
      # on strings. Used to undo a single earlier grant - taking back a chargen pick - without
      # deleting anything.
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

      # Which grants put a thing on the sheet, newest first. This is the question the old
      # model could not answer at all.
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
