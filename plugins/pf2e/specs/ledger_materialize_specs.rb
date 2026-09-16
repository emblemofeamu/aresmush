require "plugin_test_loader"

module AresMUSH
  module Pf2e
    describe Ledger do

      # Materialising is split in two so the interesting half is testable without Redis:
      # `plan` diffs the derived sheet against what the live objects currently hold and
      # returns operations; the applier that runs them is deliberately dumb.
      describe :plan do
        def sheet(overrides = {})
          Ledger.empty_sheet(5).merge(overrides)
        end

        def current(overrides = {})
          { 'level' => 5, 'xp' => 0, 'skills' => {}, 'feats' => {} }.merge(overrides)
        end

        it "should train a skill the sheet has and the character does not" do
          ops = Ledger.plan(sheet('skills' => { 'Arcana' => 'trained' }), current)

          expect(ops).to include({ 'op' => 'set_skill', 'skill' => 'Arcana', 'to' => 'trained' })
        end

        it "should raise a skill whose rank has changed" do
          ops = Ledger.plan(sheet('skills' => { 'Arcana' => 'master' }), current('skills' => { 'Arcana' => 'expert' }))

          expect(ops).to include({ 'op' => 'set_skill', 'skill' => 'Arcana', 'to' => 'master' })
        end

        it "should untrain a skill the character has and the sheet does not" do
          ops = Ledger.plan(sheet, current('skills' => { 'Stealth' => 'trained' }))

          expect(ops).to include({ 'op' => 'set_skill', 'skill' => 'Stealth', 'to' => 'untrained' })
        end

        it "should plan nothing when the character already matches the sheet" do
          matched = current('skills' => { 'Arcana' => 'expert' }, 'xp' => 3000)
          ops = Ledger.plan(sheet('skills' => { 'Arcana' => 'expert' }, 'xp' => 3000), matched)

          expect(ops).to eq []
        end

        it "should train a lore as a skill row" do
          ops = Ledger.plan(sheet('lores' => { 'Khazadi Lore' => 'trained' }), current)

          expect(ops).to include({ 'op' => 'set_skill', 'skill' => 'Khazadi Lore', 'to' => 'trained' })
        end

        # The materialiser must not touch the XP total any more: Pf2e::Audit owns it, and a
        # fold writing over it would undo awards the ledger never knew about.
        it "should leave the XP total alone" do
          ops = Ledger.plan(sheet('xp' => 2000), current('xp' => 0))

          expect(ops.map { |op| op['attr'] }).to_not include 'pf2_xp'
        end

        it "should write the feat buckets when they differ" do
          ops = Ledger.plan(sheet('feats' => { 'charclass' => [ 'Counterspell' ] }), current)

          expect(ops).to include({ 'op' => 'set_attr', 'attr' => 'pf2_feats', 'value' => { 'charclass' => [ 'Counterspell' ] } })
        end
      end

      # Legacy code computes whole lists (all of a character's feats, say) and used to assign
      # them straight onto the character - which the next fold then erased. sync_plan turns
      # such an assignment into ledger entries: grants for what appeared, revocations for what
      # went away.
      describe :sync_plan do
        def sheet(overrides = {})
          Ledger.empty_sheet(3).merge(overrides)
        end

        it "should grant a feat that the new list has and the sheet does not" do
          plan = Ledger.sync_plan(sheet, 'feats' => { 'charclass' => [ 'Sudden Charge' ] })

          expect(plan['grants']).to eq [ { 'kind' => 'grant_feat', 'payload' => { 'bucket' => 'charclass', 'feat' => 'Sudden Charge' } } ]
          expect(plan['revocations']).to eq []
        end

        it "should revoke a feat the new list dropped" do
          current = sheet('feats' => { 'charclass' => [ 'Sudden Charge' ] })
          plan = Ledger.sync_plan(current, 'feats' => { 'charclass' => [] })

          expect(plan['grants']).to eq []
          expect(plan['revocations']).to eq [ { 'kind' => 'grant_feat', 'match' => { 'feat' => 'Sudden Charge' }, 'limit' => 1 } ]
        end

        # Feats are diffed by count, not by name, so a second taking of a repeatable feat is
        # a new grant and giving one of two back revokes exactly one.
        it "should grant a second taking of a feat already held once" do
          current = sheet('feats' => { 'charclass' => [ 'Domain Acumen' ] })
          plan = Ledger.sync_plan(current, 'feats' => { 'charclass' => [ 'Domain Acumen', 'Domain Acumen' ] })

          expect(plan['grants']).to eq [ { 'kind' => 'grant_feat', 'payload' => { 'bucket' => 'charclass', 'feat' => 'Domain Acumen' } } ]
          expect(plan['revocations']).to eq []
        end

        it "should revoke only one taking when two are held and one is wanted" do
          current = sheet('feats' => { 'charclass' => [ 'Domain Acumen', 'Domain Acumen' ] })
          plan = Ledger.sync_plan(current, 'feats' => { 'charclass' => [ 'Domain Acumen' ] })

          expect(plan['grants']).to eq []
          expect(plan['revocations']).to eq [ { 'kind' => 'grant_feat', 'match' => { 'feat' => 'Domain Acumen' }, 'limit' => 1 } ]
        end

        it "should plan nothing when the list already matches" do
          current = sheet('feats' => { 'charclass' => [ 'Sudden Charge' ] })
          plan = Ledger.sync_plan(current, 'feats' => { 'charclass' => [ 'Sudden Charge' ] })

          expect(plan['grants']).to eq []
          expect(plan['revocations']).to eq []
        end

        it "should handle features, traits, specials and languages the same way" do
          plan = Ledger.sync_plan(sheet,
            'features' => { 'charclass_features' => [ 'Bravery' ] },
            'traits' => [ 'khazad' ],
            'specials' => [ 'Darkvision' ],
            'languages' => [ 'Kamin' ]
          )

          kinds = plan['grants'].map { |g| g['kind'] }
          expect(kinds).to eq [ 'grant_feature', 'add_trait', 'add_special', 'add_language' ]
        end

        it "should grant a skill rank that the new map has and the sheet does not" do
          plan = Ledger.sync_plan(sheet, 'skills' => { 'Arcana' => 'expert' })

          expect(plan['grants']).to eq [ { 'kind' => 'raise_skill', 'payload' => { 'skill' => 'Arcana', 'to' => 'expert' } } ]
        end

        it "should grant the new rank when a skill was raised" do
          current = sheet('skills' => { 'Arcana' => 'trained' })
          plan = Ledger.sync_plan(current, 'skills' => { 'Arcana' => 'master' })

          expect(plan['grants']).to eq [ { 'kind' => 'raise_skill', 'payload' => { 'skill' => 'Arcana', 'to' => 'master' } } ]
          expect(plan['revocations']).to eq []
        end

        it "should revoke training for a skill dropped from the map" do
          current = sheet('skills' => { 'Arcana' => 'trained' })
          plan = Ledger.sync_plan(current, 'skills' => {})

          expect(plan['revocations']).to eq [ { 'kind' => 'raise_skill', 'match' => { 'skill' => 'Arcana' } } ]
        end

        it "should plan nothing for a skill whose rank did not move" do
          current = sheet('skills' => { 'Arcana' => 'expert' })
          plan = Ledger.sync_plan(current, 'skills' => { 'Arcana' => 'expert' })

          expect(plan['grants']).to eq []
          expect(plan['revocations']).to eq []
        end

        it "should ignore a section the caller did not mention" do
          current = sheet('traits' => [ 'khazad' ])
          plan = Ledger.sync_plan(current, 'feats' => { 'charclass' => [] })

          expect(plan['revocations']).to eq []
        end
      end

      describe :cache_stale? do
        it "should be stale when the ledger has moved on" do
          expect(Ledger.cache_stale?({ 'head_seq' => 4, 'level' => 5 }, head_seq: 5, level: 5)).to be true
        end

        it "should be stale when a different level is asked for" do
          expect(Ledger.cache_stale?({ 'head_seq' => 4, 'level' => 5 }, head_seq: 4, level: 6)).to be true
        end

        it "should be fresh when head and level both match" do
          expect(Ledger.cache_stale?({ 'head_seq' => 4, 'level' => 5 }, head_seq: 4, level: 5)).to be false
        end

        it "should be stale when there is no cache at all" do
          expect(Ledger.cache_stale?(nil, head_seq: 1, level: 1)).to be true
        end
      end

    end
  end
end
