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

      # Throws a character's recorded build away. For starting over - a respec or a reset - where
      # the character stops having made those choices at all, which a revocation cannot say: a
      # revocation is a record that they made the choice and it was taken back.
      def self.delete_all!(char)
        char.grants.to_a.each { |g| g.delete }
        invalidate!(char)
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
          'boosts' => char.pf2_boosts,
          'spells' => Pf2emagic::Entries.known_lists(char),
          # What the derived scores are compared against.
          'ability_scores' => char.abilities.each_with_object({}) { |a, h| h[a.name] = a.base_val }
        }
      end

      # True once the ledger is this character's source of truth. Before approval a character
      # is a *draft*: the pf2_* fields and skill rows are the working copy the player is still
      # editing, the ledger is empty, and folding would wipe the draft rather than describe it.
      def self.finalized?(char)
        char.is_approved? || char.grants.count > 0
      end

      # Is there an open draft? Chargen before approval, and an advancement between
      # `advance` and `advance/done`, are both stretches where the character's own fields
      # hold picks the ledger has not been told about yet. Nothing may write the fold over
      # them until the matching commit boundary turns them into history.
      def self.drafting?(char)
        !finalized?(char) || !!char.advancing
      end

      # Applies the derived sheet to the character's Ohm objects. Idempotent: running it
      # twice plans nothing the second time. A no-op for a draft character, whose fields are
      # the draft rather than a projection of anything.
      def self.materialize!(char, at_level: nil)
        return 0 unless finalized?(char)

        # Mid-advancement only the attributes no draft step writes may be refreshed, so that
        # an xp award or a boon landing while a player is choosing does not wipe the choices
        # they have already made.
        draft = !!char.advancing

        sheet = derived(char, :at_level => at_level)
        ops = Ledger.plan(sheet, current_state(char), :draft => draft)

        ops.each do |op|
          case op['op']
          when 'set_skill'
            apply_skill(char, op['skill'], op['to'])
          when 'set_attr'
            char.update(op['attr'].to_sym => op['value'])
          when 'set_known'
            Pf2emagic::Entries.set_known!(char, op['source'], op['lists'])
          when 'set_ability'
            apply_ability_score(char, op['ability'], op['to'])
          end
        end

        return ops.size if draft

        # The level itself is not a grant - it is the ledger's read position.
        char.update(:pf2_level => sheet['level']) if char.pf2_level.to_i != sheet['level'].to_i

        # Kept so the old readers (Assurance, repeatable-feat checks) keep working while
        # they are migrated to explain_for.
        char.update(:pf2_level_tracker => tracker_view(char, sheet))

        ops.size
      end

      def self.apply_ability_score(char, name, score)
        ability = char.abilities.to_a.find { |a| a.name.to_s.casecmp?(name.to_s) }

        ability&.update(:base_val => score)
      end

      def self.apply_skill(char, name, rank)
        skill = Pf2eSkills.find_skill(name, char)

        if !skill
          return if rank.to_s == 'untrained'
          Pf2eSkills.create_skill_for_char(name, char)
        end

        Pf2eSkills.update_skill_for_char(name, char, rank, false)
      end

      # Rebuilds the level -> feat_choices view the legacy readers want, from the ledger.
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

      # Records a whole-list assignment as ledger entries. The bridge that lets legacy
      # chargen and advancement code keep computing complete lists while the ledger stays the
      # record of truth.
      def self.sync!(char, fragment, source_type:, source_ref: nil, effective_level: nil, granted_by: nil)
        seed_from_sheet!(char)

        plan = Ledger.sync_plan(derived(char), fragment)

        return 0 if plan['grants'].empty? && plan['revocations'].empty?

        marker = "sync-#{Time.now.to_i}-#{rand(1000)}"

        plan['revocations'].each { |r| revert_matching!(char, r['kind'], r['match'], :by => marker, :materialize => false, :limit => r['limit']) }

        if !plan['grants'].empty?
          write(char, :source_type => source_type, :source_ref => source_ref, :effective_level => effective_level, :granted_by => granted_by, :materialize => false) do |txn|
            plan['grants'].each { |g| txn.grant(g['kind'], g['payload']) }
          end
        end

        invalidate!(char)
        materialize!(char)

        plan['grants'].size + plan['revocations'].size
      end

      # Syncs every ledger-owned list from whatever the character's attributes currently say.
      # Called at the end of a chargen stage or an advancement commit, so the many small direct
      # writes inside those paths land in the ledger as one transaction instead of being erased
      # by the next fold.
      def self.sync_sheet!(char, source_type:, source_ref: nil, effective_level: nil)
        skills = {}
        char.skills.each do |skill|
          next if skill.prof_level.to_s == 'untrained'
          skills[skill.name] = skill.prof_level
        end

        sync!(char, {
            'skills' => skills,
            'feats' => char.pf2_feats,
            'features' => char.pf2_features,
            'traits' => char.pf2_traits,
            'specials' => char.pf2_special,
            'languages' => char.pf2_lang
          },
          :source_type => source_type, :source_ref => source_ref, :effective_level => effective_level
        )
      end

      # ------------------------------------------------------------------------------
      # Undo and redo
      # ------------------------------------------------------------------------------


      # Marks a transaction undone. Nothing is deleted, which is what makes redo possible.
      # Reverting refreshes the sheet by default, for the same reason `write` does: a caller
      # that has taken something away should not have to remember to refold, and a stale
      # sheet after a revoke is indistinguishable from the revoke not having worked. A batch
      # caller passes materialize: false and refolds once at the end.
      def self.revert_txn!(char, txn_id, by:, materialize: true)
        reverted = 0

        char.grants.find(:txn => txn_id).each do |grant|
          next unless grant.live?

          grant.update(:reverted_by => by)
          reverted += 1
        end

        if reverted > 0
          invalidate!(char)
          materialize!(char) if materialize
        end

        reverted
      end

      # Marks the live grants matching a kind and payload as reverted. Returns how many.
      # `limit` reverts only that many of the matching grants, newest first - which is what
      # taking back one taking of a repeatable feat means.
      def self.revert_matching!(char, kind, match, by:, materialize: true, limit: nil)
        targets = Ledger.matching_grants(rows(char), kind, match)
        targets = targets.last(limit.to_i) if limit

        targets.each do |row|
          grant = Pf2eGrant[row['id']]
          grant.update(:reverted_by => by) if grant && grant.live?
        end

        if !targets.empty?
          invalidate!(char)
          materialize!(char) if materialize
        end

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
        marker = "rollback-#{Time.now.to_i}-#{rand(1000)}-to-#{level.to_i}"

        Ledger.rollback_targets(rows(char), level).each { |id| revert_txn!(char, id, :by => marker, :materialize => false) }

        invalidate!(char)
        char.update(:pf2_level => (level.to_i - 1))
        materialize!(char)

        marker
      end

      # A redo only makes sense while the history it would restore is still the newest
      # history for those levels. Once the character takes one of them again, the whole
      # rolled-back branch is abandoned: those levels are deleted outright rather than kept
      # as a redo nobody can safely take, which is also what stops a character who changes
      # their mind repeatedly from accumulating dead history forever.
      #
      # Only the ladder is deleted. A rollback marks nothing but `level_up` transactions
      # (Ledger::LADDER_SOURCES), so a boon, a staff grant or chargen never carries the
      # marker and is never touched here.
      def self.supersede_rollback!(char, level)
        marker = char.pf2_rollback_marker

        return 0 if marker.blank?

        abandoned = char.grants.find(:reverted_by => marker).to_a

        return 0 if abandoned.none? { |g| g.effective_level.to_i >= level.to_i }

        abandoned.each { |grant| grant.delete }

        char.update(:pf2_rollback_marker => nil)
        invalidate!(char)

        abandoned.size
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
      # Draft edits
      # ------------------------------------------------------------------------------

      # How a grant reads while the character is still a draft. Every kind a pick or a staff
      # correction can produce before the character is finalized needs an entry: a draft is not
      # folded from the ledger, so a grant with no row here would be written nowhere.
      DRAFT_EFFECTS = {
        'raise_skill' => lambda { |char, p| Ledger.apply_skill(char, p['skill'], p['to']) },
        'add_lore' => lambda { |char, p| Ledger.apply_skill(char, p['lore'], p['to']) },
        'add_language' => lambda { |char, p| char.update(:pf2_lang => (Array(char.pf2_lang) + [ p['language'] ]).uniq) },
        'grant_feat' => lambda { |char, p| Pf2e.record_feat(char, p['bucket'] || 'charclass', p['feat']) },
        'grant_feature' => lambda { |char, p|
          features = char.pf2_features || {}
          bucket = p['bucket'] || 'charclass_features'
          list = Array(features[bucket])
          features[bucket] = list + [ p['feature'] ] unless list.include?(p['feature'])
          char.update(:pf2_features => features)
        },
        'add_trait' => lambda { |char, p| char.update(:pf2_traits => (Array(char.pf2_traits) + [ p['trait'] ]).uniq) },
        'add_special' => lambda { |char, p| char.update(:pf2_special => (Array(char.pf2_special) + [ p['special'] ]).uniq) },
        'set_ability_score' => lambda { |char, p| Ledger.apply_ability_score(char, p['ability'], p['to'].to_i) },
        'spell_access' => lambda { |char, p|
          known = Pf2emagic::Entries.known(char.magic, p['source'])
          at_rank = Array(known[p['rank'].to_s])

          next if at_rank.any? { |spell| spell.to_s.casecmp?(p['spell'].to_s) }

          Pf2emagic::Entries.set_known!(char, p['source'],
            known.merge(p['rank'].to_s => at_rank + [ p['spell'] ]))
        }
      }.freeze

      DRAFT_UNDO = {
        'raise_skill' => lambda { |char, match| Ledger.apply_skill(char, match['skill'], 'untrained') },
        'add_lore' => lambda { |char, match| Ledger.apply_skill(char, match['lore'], 'untrained') },
        'add_language' => lambda { |char, match| char.update(:pf2_lang => Array(char.pf2_lang).reject { |l| l.to_s.casecmp?(match['language'].to_s) }) },
        # Out of both stores, because a draft holds its picks and the sheet holds what a fold left.
        'grant_feat' => lambda { |char, match| Pf2e.forget_feat(char, match['feat']) },
        'grant_feature' => lambda { |char, match|
          features = char.pf2_features || {}
          features.each_key { |bucket| features[bucket] = Array(features[bucket]).reject { |f| f.to_s.casecmp?(match['feature'].to_s) } }
          char.update(:pf2_features => features)
        },
        'add_trait' => lambda { |char, match| char.update(:pf2_traits => Array(char.pf2_traits).reject { |t| t.to_s.casecmp?(match['trait'].to_s) }) },
        'add_special' => lambda { |char, match| char.update(:pf2_special => Array(char.pf2_special).reject { |s| s.to_s.casecmp?(match['special'].to_s) }) },
        'spell_access' => lambda { |char, match|
          known = Pf2emagic::Entries.known(char.magic, match['source'])
          without = known.each_with_object({}) do |(rank, spells), kept|
            kept[rank] = Array(spells).reject { |spell| spell.to_s.casecmp?(match['spell'].to_s) }
          end

          Pf2emagic::Entries.set_known!(char, match['source'], without)
        }
      }.freeze

      def self.apply_draft!(char, grants)
        Array(grants).each do |grant|
          effect = DRAFT_EFFECTS[grant['kind']]

          next Global.logger.warn("PF2e draft has no effect for grant kind #{grant['kind']}") unless effect

          effect.call(char, grant['payload'] || {})
        end
      end

      def self.undo_draft!(char, revocations)
        Array(revocations).each do |revocation|
          undo = DRAFT_UNDO[revocation['kind']]

          next Global.logger.warn("PF2e draft cannot undo grant kind #{revocation['kind']}") unless undo

          undo.call(char, revocation['match'] || {})
        end
      end

      # ------------------------------------------------------------------------------
      # Commit boundaries
      # ------------------------------------------------------------------------------

      # The draft becomes history. Called once, when a character is approved: everything
      # chargen produced is written as a single `chargen` transaction at level 1, and from
      # then on the ledger is the source of truth and the sheet fields are its projection.
      def self.commit_chargen!(char, granted_by: 'System')
        return nil if char.grants.count > 0

        txn = seed_from_sheet!(char, :granted_by => granted_by, :source_type => 'chargen', :source_ref => 'chargen')

        # The character stops being a draft here, so the sheet becomes the fold's projection: what
        # chargen staged has just been recorded as grants, and the draft hash is history.
        char.update(:pf2_advancement => {})
        invalidate!(char)
        materialize!(char)

        # The draft's own history ends here too: past this point the grants are the record and
        # admin/rollback is the undo.
        DraftJournal.clear!(char)

        txn
      end

      # A level-up becomes history: one transaction, attributed to the level just gained, for
      # everything the advancement produced plus the XP it cost. Called from do_advancement
      # after the new level is saved, which is what makes the attribution right.
      def self.commit_level_up!(char, level, cost: nil)
        seed_from_sheet!(char, :source_type => 'chargen', :source_ref => 'chargen')

        # Taking this level again is what makes a pending redo of it stale.
        supersede_rollback!(char, level)

        cost = Pf2e::ADVANCEMENT_XP_COST if cost.nil?

        skills = {}
        char.skills.each do |skill|
          next if skill.prof_level.to_s == 'untrained'
          skills[skill.name] = skill.prof_level
        end

        # Diffed against the fold at the level they are *leaving*, because that is what the
        # character's materialised sheet currently reflects. Diffing against the new level
        # would read anything that falls due there - a boon written for this level, dormant
        # until now - as something the advancement removed, and revoke it on arrival.
        plan = Ledger.sync_plan(derived(char, :at_level => level.to_i - 1), {
          'skills' => skills,
          # Both stores, because a feat handed over at the boundary may land in either: the level's
          # picks are in the draft, and a granted feat is written as the grant is applied.
          'feats' => DraftSheet.of(char).feats_by_bucket,
          'features' => char.pf2_features,
          'traits' => char.pf2_traits,
          'specials' => char.pf2_special,
          'languages' => char.pf2_lang,
          # Every boost the character holds, counted per ability. The materialiser writes this
          # attribute from the fold, so it already carries chargen's, and `raise ability` adds this
          # level's on top. A fragment holding only this level's would read chargen's as gone.
          'boosts' => char.pf2_boosts,
          # Only enumerated casters contribute: a Cleric prepares from the whole divine list, so
          # there is nothing to record and nothing a rollback could take away.
          'spells' => Pf2emagic::Entries.known_lists(char)
        })

        marker = "level-#{level}-#{Time.now.to_i}"

        plan['revocations'].each { |r| revert_matching!(char, r['kind'], r['match'], :by => marker, :materialize => false, :limit => r['limit']) }

        txn_id = write(char, :source_type => 'level_up', :source_ref => "advance to level #{level}", :effective_level => level, :materialize => false) do |txn|
          plan['grants'].each { |g| txn.grant(g['kind'], g['payload']) }
        end

        invalidate!(char)
        materialize!(char)

        # The cost is an audit entry rather than a folded grant, tagged with the transaction
        # that incurred it so a rollback can find and reverse exactly this level's spend.
        Audit.post(char, 'xp', -cost.to_i, :by => 'System', :reason => "advance to level #{level}", :ref => txn_id) if cost.to_i > 0

        # The level's draft is history now, so its steps go: what can still be taken back is the
        # whole level, through admin/rollback.
        DraftJournal.clear!(char)

        plan['grants'].size
      end

      # ------------------------------------------------------------------------------
      # Bootstrapping
      # ------------------------------------------------------------------------------

      # Turns a character who predates the ledger into one honest `imported` transaction.
      # Coarse on purpose: the old stores cannot say which level trained which skill, so
      # inventing per-level history here would be a lie.
      def self.seed_from_sheet!(char, granted_by: 'System', source_type: 'imported', source_ref: 'pre-ledger sheet')
        return nil if char.grants.count > 0

        # Spells an enumerated caster already knows, so the fold is a complete account of what
        # they have. Without this the materialiser - which writes the known lists from the fold -
        # would erase every spell chosen before the ledger knew about them.
        known = Pf2emagic::Entries.known_lists(char)
        boosts = boost_tally(char)

        write(char, :source_type => source_type, :source_ref => source_ref, :granted_by => granted_by, :effective_level => 1, :materialize => false) do |txn|
          known.each_pair do |source, by_rank|
            by_rank.each_pair do |rank, spells|
              Array(spells).each { |spell| txn.grant('spell_access', 'source' => source, 'rank' => rank, 'spell' => spell) }
            end
          end

          char.skills.each do |skill|
            next if skill.prof_level.to_s == 'untrained'
            txn.grant('raise_skill', 'skill' => skill.name, 'to' => skill.prof_level)
          end

          # Through DraftSheet, because a pick made during chargen is in the draft rather than on
          # the sheet, and this is the boundary that turns it into history.
          DraftSheet.of(char).feats_by_bucket.each_pair do |bucket, feats|
            Array(feats).each { |feat| txn.grant('grant_feat', 'bucket' => bucket, 'feat' => feat) }
          end

          (char.pf2_features || {}).each_pair do |bucket, features|
            Array(features).each { |f| txn.grant('grant_feature', 'bucket' => bucket, 'feature' => f) }
          end

          Array(char.pf2_lang).each { |l| txn.grant('add_language', 'language' => l) }
          Array(char.pf2_traits).each { |t| txn.grant('add_trait', 'trait' => t) }
          Array(char.pf2_special).each { |s| txn.grant('add_special', 'special' => s) }

          boosts.each_pair do |ability, count|
            count.times { txn.grant('boost_ability', 'ability' => ability) }
          end

          flaw_tally(char).each_pair do |ability, count|
            count.times { txn.grant('flaw_ability', 'ability' => ability) }
          end

          # A score the boosts and flaws do not account for is recorded as itself. Staff
          # corrections and characters imported from before the ledger both produce scores no
          # count of boosts from 10 can reach, and deriving would quietly move them.
          flaws = flaw_tally(char)

          char.abilities.each do |ability|
            derived = Pf2eAbilities.derived_score(flaws[ability.name].to_i, boosts[ability.name].to_i)

            next if ability.base_val.to_i == derived

            txn.grant('set_ability_score', 'ability' => ability.name, 'to' => ability.base_val.to_i)
          end
        end

        # `pf2_boosts` is the running count the next level-up diffs against, and seeding does not
        # materialise, so it is written here. Left empty, the first level-up would read every boost
        # chargen recorded as one that had gone away and revoke it.
        char.update(:pf2_boosts => boosts) unless boosts.empty?
      end

      # Every boost the character has taken, counted per ability, for the one moment a ledger is
      # seeded and there is nothing but the sheet to read.
      #
      # Chargen stages its picks in `pf2_boosts_working`, a list per category: the ancestry's fixed
      # and chosen boosts, the background's, the class's key ability, and four free ones. A character
      # seeded mid-career also has `pf2_boosts`, so both are counted. Afterwards the fold owns the
      # total and writes it back to `pf2_boosts`, so nothing else should add these together.
      def self.boost_tally(char)
        tally = Hash.new(0)

        (char.pf2_boosts_working || {}).each_value do |slots|
          Array(slots).each do |slot|
            # A slot still holding a marker, or a list of the options allowed in it, is unfilled.
            next unless slot.is_a?(String)
            next if slot.strip.empty? || slot.casecmp?('open')

            tally[slot] += 1
          end
        end

        (char.pf2_boosts || {}).each_pair { |ability, count| tally[ability] += count.to_i }

        tally
      end

      # The ancestry's flaw, read from the ancestry the character chose. Recorded as an outcome,
      # which ability is flawed, so editing an ancestry's config later leaves an existing character
      # alone.
      def self.flaw_tally(char)
        ancestry = (char.pf2_base_info || {})['ancestry']
        return {} if ancestry.blank?

        flaw = Global.read_config('pf2e_ancestry', ancestry, 'abl_flaw')
        return {} if flaw.blank?

        Array(flaw).each_with_object(Hash.new(0)) { |ability, tally| tally[ability] += 1 }
      end

    end
  end
end
