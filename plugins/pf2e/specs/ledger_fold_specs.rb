require "plugin_test_loader"

module AresMUSH
  module Pf2e
    describe Ledger do

      # The fold is deliberately pure: it takes grant rows as plain hashes so it can be
      # tested without Redis, and so "what did this sheet look like at level N" is a
      # question about data rather than about the live character object.
      def grant(seq, kind, payload, level: nil, txn: "t#{seq}", source: 'level_up', ref: nil, reverted: nil)
        {
          'seq' => seq,
          'txn' => txn,
          'kind' => kind,
          'payload' => payload,
          'source_type' => source,
          'source_ref' => ref,
          'effective_level' => level,
          'reverted_by' => reverted
        }
      end

      describe :fold do
        it "should return an empty sheet for an empty ledger" do
          sheet = Ledger.fold([], at_level: 1)

          expect(sheet['level']).to eq 1
          expect(sheet['xp']).to eq 0
          expect(sheet['skills']).to eq({})
          expect(sheet['feats']).to eq({})
        end

        it "should apply a grant at the level it takes effect" do
          sheet = Ledger.fold([ grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'expert' }, level: 2) ], at_level: 2)

          expect(sheet['skills']['Arcana']).to eq 'expert'
        end

        it "should ignore a grant that takes effect above the folded level" do
          sheet = Ledger.fold([ grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'expert' }, level: 5) ], at_level: 4)

          expect(sheet['skills']).to eq({})
        end

        it "should apply a grant with no effective level at any level" do
          sheet = Ledger.fold([ grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'trained' }, level: nil, source: 'boon') ], at_level: 1)

          expect(sheet['skills']['Arcana']).to eq 'trained'
        end

        it "should ignore a reverted grant" do
          grants = [ grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'expert' }, level: 2, reverted: 'rb-1') ]

          expect(Ledger.fold(grants, at_level: 20)['skills']).to eq({})
        end

        it "should let the later grant win when two touch the same skill" do
          grants = [
            grant(2, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'master' }, level: 7),
            grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'expert' }, level: 3)
          ]

          expect(Ledger.fold(grants, at_level: 20)['skills']['Arcana']).to eq 'master'
        end

        it "should fold in sequence order regardless of the order rows arrive in" do
          grants = [
            grant(2, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'expert' }, level: 7),
            grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'master' }, level: 3)
          ]

          expect(Ledger.fold(grants, at_level: 20)['skills']['Arcana']).to eq 'expert'
        end

        it "should count ability boosts rather than storing a score" do
          grants = [
            grant(1, 'boost_ability', { 'ability' => 'Strength' }, level: 1),
            grant(2, 'boost_ability', { 'ability' => 'Strength' }, level: 5),
            grant(3, 'boost_ability', { 'ability' => 'Wisdom' }, level: 5)
          ]

          sheet = Ledger.fold(grants, at_level: 5)

          expect(sheet['boosts']['Strength']).to eq 2
          expect(sheet['boosts']['Wisdom']).to eq 1
        end

        it "should file a granted feat under its bucket" do
          grants = [ grant(1, 'grant_feat', { 'bucket' => 'charclass', 'feat' => 'Counterspell' }, level: 2) ]

          expect(Ledger.fold(grants, at_level: 2)['feats']['charclass']).to eq [ 'Counterspell' ]
        end

        it "should record the option chosen for a feat" do
          grants = [ grant(1, 'grant_feat', { 'bucket' => 'skill', 'feat' => 'Assurance', 'choice' => 'Crafting' }, level: 2) ]

          expect(Ledger.fold(grants, at_level: 2)['feat_choices']['Assurance']).to eq [ 'Crafting' ]
        end

        it "should not list the same feat twice" do
          grants = [
            grant(1, 'grant_feat', { 'bucket' => 'general', 'feat' => 'Toughness' }, level: 3),
            grant(2, 'grant_feat', { 'bucket' => 'general', 'feat' => 'Toughness' }, level: 7)
          ]

          expect(Ledger.fold(grants, at_level: 7)['feats']['general']).to eq [ 'Toughness' ]
        end

        it "should collect class features" do
          grants = [ grant(1, 'grant_feature', { 'feature' => 'Arcane Bond', 'bucket' => 'charclass_features' }, level: 1) ]

          expect(Ledger.fold(grants, at_level: 1)['features']['charclass_features']).to eq [ 'Arcane Bond' ]
        end

        it "should add a lore with its proficiency" do
          grants = [ grant(1, 'add_lore', { 'lore' => 'Khazadi Lore', 'to' => 'trained' }, level: 1) ]

          expect(Ledger.fold(grants, at_level: 1)['lores']['Khazadi Lore']).to eq 'trained'
        end

        it "should add languages without duplicating them" do
          grants = [
            grant(1, 'add_language', { 'language' => 'Kamin' }, level: 1),
            grant(2, 'add_language', { 'language' => 'Kamin' }, level: 4)
          ]

          expect(Ledger.fold(grants, at_level: 4)['languages']).to eq [ 'Kamin' ]
        end

        it "should record spell access" do
          grants = [ grant(1, 'spell_access', { 'spell' => 'Fireball', 'tradition' => 'arcane', 'rank' => 3 }, level: 5, source: 'boon') ]

          access = Ledger.fold(grants, at_level: 5)['spell_access']

          expect(access.size).to eq 1
          expect(access.first['spell']).to eq 'Fireball'
          expect(access.first['tradition']).to eq 'arcane'
        end

        it "should set a nested proficiency" do
          grants = [ grant(1, 'set_prof', { 'group' => 'weapon_prof', 'key' => 'simple', 'to' => 'expert' }, level: 5) ]

          expect(Ledger.fold(grants, at_level: 5)['profs']['weapon_prof']['simple']).to eq 'expert'
        end

        it "should total XP awards and spends" do
          grants = [
            grant(1, 'xp_award', { 'amount' => 3000 }, level: nil, source: 'staff'),
            grant(2, 'xp_spend', { 'amount' => 1000 }, level: 2)
          ]

          expect(Ledger.fold(grants, at_level: 2)['xp']).to eq 2000
        end

        it "should park an unknown kind in unsupported instead of dropping or raising it" do
          grants = [ grant(1, 'summon_ancient_horror', { 'name' => 'Illotha' }, level: 3) ]

          sheet = Ledger.fold(grants, at_level: 3)

          expect(sheet['unsupported'].size).to eq 1
          expect(sheet['unsupported'].first['kind']).to eq 'summon_ancient_horror'
        end
      end

      describe :rollback_targets do
        it "should target a level_up transaction at the rolled-back level" do
          rows = [ grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'expert' }, level: 5, txn: 'lvl-5', source: 'level_up') ]

          expect(Ledger.rollback_targets(rows, 5)).to eq [ 'lvl-5' ]
        end

        it "should target level_up transactions above the rolled-back level" do
          rows = [ grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'master' }, level: 9, txn: 'lvl-9', source: 'level_up') ]

          expect(Ledger.rollback_targets(rows, 5)).to eq [ 'lvl-9' ]
        end

        it "should leave a boon alone even when it takes effect at the rolled-back level" do
          rows = [ grant(1, 'raise_skill', { 'skill' => 'Diplomacy', 'to' => 'expert' }, level: 5, txn: 'boon-9', source: 'boon') ]

          expect(Ledger.rollback_targets(rows, 5)).to eq []
        end

        it "should leave chargen alone" do
          rows = [ grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'trained' }, level: 1, txn: 'cg-1', source: 'chargen') ]

          expect(Ledger.rollback_targets(rows, 1)).to eq []
        end

        it "should not target a transaction that is already reverted" do
          rows = [ grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'expert' }, level: 5, txn: 'lvl-5', source: 'level_up', reverted: 'earlier') ]

          expect(Ledger.rollback_targets(rows, 5)).to eq []
        end

        it "should leave a global grant alone whatever level is rolled back to" do
          rows = [ grant(1, 'add_language', { 'language' => 'Kamin' }, level: nil, txn: 'staff-1', source: 'level_up') ]

          expect(Ledger.rollback_targets(rows, 2)).to eq []
        end
      end

      describe :explain do
        it "should name the grants that set a skill, newest first" do
          grants = [
            grant(1, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'trained' }, level: 1, source: 'chargen', ref: 'Wizard'),
            grant(2, 'raise_skill', { 'skill' => 'Arcana', 'to' => 'expert' }, level: 5, source: 'boon', ref: 'boon-9'),
            grant(3, 'raise_skill', { 'skill' => 'Stealth', 'to' => 'trained' }, level: 5)
          ]

          found = Ledger.explain(grants, at_level: 20, kind: 'raise_skill', key: 'Arcana')

          expect(found.map { |g| g['source_type'] }).to eq [ 'boon', 'chargen' ]
          expect(found.first['source_ref']).to eq 'boon-9'
        end
      end

    end
  end
end
