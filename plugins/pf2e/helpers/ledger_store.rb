module AresMUSH
  module Pf2e

    # The character-facing half of the ledger: reads and writes Ohm, delegates every
    # decision to the pure functions in helpers/ledger.rb.
    #
    #   Pf2e::Ledger.write(char, source_type: 'level_up', effective_level: 3) do |txn|
    #     txn.grant('raise_skill', 'skill' => 'Arcana', 'to' => 'expert')
    #     txn.grant('grant_feat',  'bucket' => 'charclass', 'feat' => 'Counterspell')
    #   end
    #
    # Writing a txn invalidates the cache and re-materialises the live objects, so callers
    # never touch pf2_* attributes or skill rows directly again.
    module Ledger

      # Collects the grants of one transaction so a caller writes them as a unit.
      class Txn
        attr_reader :id, :grants

        def initialize(id, defaults)
          @id = id
          @defaults = defaults
          @grants = []
        end

        # Payload and overrides are plain hashes, not keywords: a payload's keys are
        # strings, and Ruby 3 would try to read a brace-less string-keyed hash as keyword
        # arguments and raise.
        #
        #   txn.grant('raise_skill', 'skill' => 'Arcana', 'to' => 'expert')
        #   txn.grant('add_language', { 'language' => 'Silya' }, { 'effective_level' => nil })
        def grant(kind, payload = {}, overrides = {})
          @grants << {
            'kind' => kind,
            'payload' => payload,
            'effective_level' => overrides.key?('effective_level') ? overrides['effective_level'] : @defaults[:effective_level],
            'source_ref' => overrides.key?('source_ref') ? overrides['source_ref'] : @defaults[:source_ref]
          }
          self
        end
      end

      def self.rows(char)
        char.grants.to_a.map { |g| g.to_row }
      end

      def self.head_seq(char)
        char.grants.to_a.map { |g| g.seq.to_i }.max || 0
      end

      def self.next_txn_id(char)
        "#{char.id}-#{Time.now.to_i}-#{rand(1000)}"
      end

      # Appends a transaction, drops stale caches and re-materialises. Returns the txn id.
      def self.write(char, source_type:, source_ref: nil, effective_level: nil, granted_by: nil, materialize: true)
        txn = Txn.new(next_txn_id(char), { :effective_level => effective_level, :source_ref => source_ref })
        yield txn if block_given?

        return txn.id if txn.grants.empty?

        seq = head_seq(char)
        now = Time.now

        txn.grants.each do |g|
          seq += 1
          Pf2eGrant.create(
            :character => char,
            :seq => seq,
            :txn => txn.id,
            :kind => g['kind'],
            :payload => g['payload'],
            :source_type => source_type,
            :source_ref => g['source_ref'],
            :effective_level => g['effective_level'],
            :granted_at => now,
            :granted_by => granted_by
          )
        end

        invalidate!(char)
        materialize!(char) if materialize

        txn.id
      end

      # ------------------------------------------------------------------------------
      # Reading
      # ------------------------------------------------------------------------------

      # The derived sheet at a level, from cache when the ledger has not moved.
      def self.derived(char, at_level: nil)
        level = (at_level || char.pf2_level || 1).to_i
        head = head_seq(char)
        cached = cache_for(char, level)

        if !Ledger.cache_stale?(cached&.to_row, :head_seq => head, :level => level)
          return cached.sheet
        end

        sheet = Ledger.fold(rows(char), :at_level => level)

        cached.delete if cached
        Pf2eSheetCache.create(:character => char, :level => level, :head_seq => head, :sheet => sheet, :built_at => Time.now)

        sheet
      end

      def self.cache_for(char, level)
        char.sheet_caches.to_a.find { |c| c.level.to_i == level.to_i }
      end

      def self.invalidate!(char)
        char.sheet_caches.to_a.each { |c| c.delete }
      end

      # Who granted a thing, newest first.
      def self.explain_for(char, kind:, key:, at_level: nil)
        Ledger.explain(rows(char), :at_level => (at_level || char.pf2_level).to_i, :kind => kind, :key => key)
      end

      # ------------------------------------------------------------------------------
      # Materialising onto the live objects
      # ------------------------------------------------------------------------------

      # What the live character currently holds, in the shape `plan` diffs against.
      def self.current_state(char)
        skills = {}
        char.skills.each do |s|
          skills[s.name] = s.prof_level unless s.prof_level.to_s == 'untrained'
        end

        {
          'level' => char.pf2_level,
          'xp' => char.pf2_xp,
          'skills' => skills,
          'feats' => char.pf2_feats,
          'features' => char.pf2_features,
          'traits' => char.pf2_traits,
          'specials' => char.pf2_special,
          'languages' => char.pf2_lang,
          'boosts' => char.pf2_boosts
        }
      end

      # Applies the derived sheet to the character's Ohm objects. Idempotent: running it
      # twice plans nothing the second time.
      def self.materialize!(char, at_level: nil)
        sheet = derived(char, :at_level => at_level)
        ops = Ledger.plan(sheet, current_state(char))

        ops.each do |op|
          case op['op']
          when 'set_skill'
            apply_skill(char, op['skill'], op['to'])
          when 'set_attr'
            char.update(op['attr'].to_sym => op['value'])
          end
        end

        # The level itself is not a grant - it is the ledger's read position.
        char.update(:pf2_level => sheet['level']) if char.pf2_level.to_i != sheet['level'].to_i

        # Kept so the old readers (Assurance, repeatable-feat checks) keep working while
        # they are migrated to explain_for.
        char.update(:pf2_level_tracker => tracker_view(char, sheet))

        ops.size
      end

      def self.apply_skill(char, name, rank)
        skill = Pf2eSkills.find_skill(name, char)

        if !skill
          return if rank.to_s == 'untrained'
          Pf2eSkills.create_skill_for_char(name, char)
        end

        Pf2eSkills.update_skill_for_char(name, char, rank, false)
      end

      # Rebuilds the level -> feat_choices view the old code reads, from the ledger.
      def self.tracker_view(char, sheet)
        tracker = {}

        rows(char).each do |row|
          next if !row['reverted_by'].blank?
          next unless row['kind'] == 'grant_feat'
          next if (row['payload'] || {})['choice'].blank?

          key = row['effective_level'].to_i.to_s
          entry = (tracker[key] ||= {})
          choices = (entry['feat_choices'] ||= {})
          list = (choices[row['payload']['feat']] ||= [])
          list << row['payload']['choice'] unless list.include?(row['payload']['choice'])
        end

        tracker
      end

      # ------------------------------------------------------------------------------
      # Undo and redo
      # ------------------------------------------------------------------------------


      # Marks a transaction undone. Nothing is deleted, which is what makes redo possible.
      def self.revert_txn!(char, txn_id, by:)
        char.grants.find(:txn => txn_id).each do |grant|
          grant.update(:reverted_by => by) if grant.live?
        end
      end

      # Marks the live grants matching a kind and payload as reverted. Returns how many.
      def self.revert_matching!(char, kind, match, by:)
        targets = Ledger.matching_grants(rows(char), kind, match)

        targets.each do |row|
          grant = Pf2eGrant[row['id']]
          grant.update(:reverted_by => by) if grant && grant.live?
        end

        invalidate!(char) if !targets.empty?

        targets.size
      end

      def self.unrevert_txn!(char, txn_id)
        char.grants.find(:txn => txn_id).each do |grant|
          grant.update(:reverted_by => nil)
        end
      end

      # Puts the character back to just before `level`: every non-global txn at or above it
      # is marked reverted, and a boon with no effective level is untouched.
      def self.rollback_to_level!(char, level, enactor = nil)
        marker = "rollback-#{Time.now.to_i}-to-#{level.to_i}"

        Ledger.rollback_targets(rows(char), level).each { |id| revert_txn!(char, id, :by => marker) }

        invalidate!(char)
        char.update(:pf2_level => (level.to_i - 1))
        materialize!(char)

        marker
      end

      # Undoes an undo: every grant reverted by that marker comes back.
      def self.redo_rollback!(char, marker)
        restored = char.grants.find(:reverted_by => marker).to_a

        return 0 if restored.empty?

        level = restored.map { |g| g.effective_level.to_i }.max
        restored.each { |g| g.update(:reverted_by => nil) }

        invalidate!(char)
        char.update(:pf2_level => level)
        materialize!(char)

        restored.size
      end

      # ------------------------------------------------------------------------------
      # Bootstrapping
      # ------------------------------------------------------------------------------

      # Turns a character who predates the ledger into one honest `imported` transaction.
      # Coarse on purpose: the old stores cannot say which level trained which skill, so
      # inventing per-level history here would be a lie.
      def self.seed_from_sheet!(char, granted_by: 'System')
        return nil if char.grants.count > 0

        level = (char.pf2_level || 1).to_i

        write(char, :source_type => 'imported', :source_ref => 'pre-ledger sheet', :granted_by => granted_by, :effective_level => 1, :materialize => false) do |txn|
          txn.grant('xp_award', 'amount' => char.pf2_xp.to_i) if char.pf2_xp.to_i > 0

          char.skills.each do |skill|
            next if skill.prof_level.to_s == 'untrained'
            txn.grant('raise_skill', 'skill' => skill.name, 'to' => skill.prof_level)
          end

          (char.pf2_feats || {}).each_pair do |bucket, feats|
            Array(feats).each { |feat| txn.grant('grant_feat', 'bucket' => bucket, 'feat' => feat) }
          end

          (char.pf2_features || {}).each_pair do |bucket, features|
            Array(features).each { |f| txn.grant('grant_feature', 'bucket' => bucket, 'feature' => f) }
          end

          Array(char.pf2_lang).each { |l| txn.grant('add_language', 'language' => l) }
          Array(char.pf2_traits).each { |t| txn.grant('add_trait', 'trait' => t) }
          Array(char.pf2_special).each { |s| txn.grant('add_special', 'special' => s) }

          (char.pf2_boosts || {}).each_pair do |ability, count|
            count.to_i.times { txn.grant('boost_ability', 'ability' => ability) }
          end
        end
      end

    end
  end
end
