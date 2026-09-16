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

        it "should set XP when the total has moved" do
          ops = Ledger.plan(sheet('xp' => 2000), current('xp' => 0))

          expect(ops).to include({ 'op' => 'set_attr', 'attr' => 'pf2_xp', 'value' => 2000 })
        end

        it "should write the feat buckets when they differ" do
          ops = Ledger.plan(sheet('feats' => { 'charclass' => [ 'Counterspell' ] }), current)

          expect(ops).to include({ 'op' => 'set_attr', 'attr' => 'pf2_feats', 'value' => { 'charclass' => [ 'Counterspell' ] } })
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
