require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a character has, counting an open draft.
    #
    # The point of one reader is that callers stop asking whether a draft is open. An advancement
    # draft is empty except between `advance` and `advance/done`, so merging it is a no-op the rest
    # of the time, and a caller that merges unconditionally gets the right answer in both states.
    describe DraftSheet do

      def char(level: 5, feats: {}, skills: {}, advancement: {}, advancing: nil)
        double(:pf2_level => level,
               :advancing => advancing,
               :pf2_feats => feats,
               :pf2_advancement => advancement,
               :pf2_base_info => { 'charclass' => 'Wizard' },
               :magic => nil,
               :skills => skills.map { |name, prof| double(:name => name, :prof_level => prof, :name_upcase => name.upcase) })
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e', 'prof_progression')
          .and_return(%w(untrained trained expert master legendary))
      end

      # The commit boundary and the review screen need the buckets, not a flat list: a grant
      # records which heading a feat sits under.
      describe :feats_by_bucket do
        it "should keep the sheet's own buckets" do
          sheet = DraftSheet.of(char(:feats => { 'charclass' => [ 'Power Attack' ] }))

          expect(sheet.feats_by_bucket).to eq('charclass' => [ 'Power Attack' ])
        end

        it "should add a draft's picks to the bucket they were taken in" do
          sheet = DraftSheet.of(char(
            :advancing => true,
            :feats => { 'charclass' => [ 'Power Attack' ] },
            :advancement => { 'feats' => { 'charclass' => [ 'Sudden Charge' ], 'skill' => [ 'Assurance' ] } }))

          expect(sheet.feats_by_bucket).to eq('charclass' => [ 'Power Attack', 'Sudden Charge' ],
                                              'skill' => [ 'Assurance' ])
        end

        it "should leave out an unfilled slot" do
          sheet = DraftSheet.of(char(:advancing => true,
                                     :advancement => { 'feats' => { 'skill' => [ 'open', 'Assurance' ] } }))

          expect(sheet.feats_by_bucket).to eq('skill' => [ 'Assurance' ])
        end

        it "should keep a feat taken twice twice, since the rules allow some of them" do
          sheet = DraftSheet.of(char(:advancing => true,
                                     :feats => { 'skill' => [ 'Additional Lore' ] },
                                     :advancement => { 'feats' => { 'skill' => [ 'Additional Lore' ] } }))

          expect(sheet.feats_by_bucket).to eq('skill' => [ 'Additional Lore', 'Additional Lore' ])
        end
      end

      # feat_names is uniqued, so anything that counts takings has to use the buckets. The rules
      # let some feats be taken more than once, and a limit read from a uniqued list is always 1.
      describe "counting a feat taken twice" do
        it "should see both takings through the buckets" do
          sheet = DraftSheet.of(char(:feats => { 'skill' => [ 'Additional Lore', 'Additional Lore' ] }))

          expect(sheet.feats_by_bucket.values.flatten.size).to eq 2
          expect(sheet.feat_names.size).to eq 1
        end
      end

      describe :feat_names do
        it "should give the feats on the sheet" do
          sheet = DraftSheet.of(char(:feats => { 'charclass' => [ 'Power Attack' ] }))

          expect(sheet.feat_names).to eq [ 'POWER ATTACK' ]
        end

        it "should include a feat picked in an open draft" do
          sheet = DraftSheet.of(char(
            :advancing => true,
            :feats => { 'charclass' => [ 'Power Attack' ] },
            :advancement => { 'feats' => { 'skill' => [ 'Assurance' ] } }))

          expect(sheet.feat_names).to eq [ 'POWER ATTACK', 'ASSURANCE' ]
        end

        it "should ignore an unfilled slot marker" do
          sheet = DraftSheet.of(char(:advancing => true,
                                     :advancement => { 'feats' => { 'skill' => [ 'open' ] } }))

          expect(sheet.feat_names).to eq []
        end

        # The invariant that lets callers stop forking: with no draft open there is nothing to merge,
        # so the answer is the sheet's own.
        it "should read the same with no draft open as the sheet alone" do
          feats = { 'charclass' => [ 'Power Attack' ], 'skill' => [ 'Assurance' ] }

          expect(DraftSheet.of(char(:feats => feats)).feat_names)
            .to eq feats.values.flatten.map(&:upcase)
        end

        it "should not double-count a feat held and staged" do
          sheet = DraftSheet.of(char(
            :advancing => true,
            :feats => { 'charclass' => [ 'Power Attack' ] },
            :advancement => { 'feats' => { 'charclass' => [ 'Power Attack' ] } }))

          expect(sheet.feat_names).to eq [ 'POWER ATTACK' ]
        end
      end

      describe :skill_prof do
        it "should give the rank on the sheet" do
          sheet = DraftSheet.of(char(:skills => { 'Arcana' => 'expert' }))

          expect(sheet.skill_prof('Arcana')).to eq 'expert'
        end

        it "should step the rank up for an increase staged in the draft" do
          sheet = DraftSheet.of(char(:advancing => true,
                                     :skills => { 'Arcana' => 'trained' },
                                     :advancement => { 'raise skill' => [ 'Arcana' ] }))

          expect(sheet.skill_prof('Arcana')).to eq 'expert'
        end

        it "should count a raise from a restricted slot too" do
          sheet = DraftSheet.of(char(:advancing => true,
                                     :skills => { 'Arcana' => 'trained' },
                                     :advancement => { 'raise skill choice' => [ 'Arcana' ] }))

          expect(sheet.skill_prof('Arcana')).to eq 'expert'
        end

        it "should stop at the top of the progression" do
          sheet = DraftSheet.of(char(:advancing => true,
                                     :skills => { 'Arcana' => 'legendary' },
                                     :advancement => { 'raise skill' => [ 'Arcana' ] }))

          expect(sheet.skill_prof('Arcana')).to eq 'legendary'
        end

        it "should ignore an unfilled increase" do
          sheet = DraftSheet.of(char(:advancing => true,
                                     :skills => { 'Arcana' => 'trained' },
                                     :advancement => { 'raise skill' => [ 'open' ] }))

          expect(sheet.skill_prof('Arcana')).to eq 'trained'
        end

        it "should give untrained for a skill the character does not have" do
          expect(DraftSheet.of(char).skill_prof('Arcana')).to eq 'untrained'
        end
      end

      describe :spellbook do
        def caster(spellbook: {}, advancement: {})
          magic = double(:spellbook => spellbook, :repertoire => {}, :spells_per_day => {}, :tradition => {})

          double(:pf2_level => 5, :advancing => true, :pf2_feats => {}, :skills => [],
                 :pf2_advancement => advancement, :magic => magic,
                 :pf2_base_info => { 'charclass' => 'Wizard' })
        end

        it "should merge a pick staged at its own rank" do
          char = caster(:spellbook => { 'Wizard' => { '1' => [ 'Magic Missile' ] } },
                        :advancement => { 'spellbook' => { '2' => [ 'Invisibility' ] } })

          expect(DraftSheet.of(char).spellbook['Wizard']['2']).to eq [ 'Invisibility' ]
          expect(DraftSheet.of(char).spellbook['Wizard']['1']).to eq [ 'Magic Missile' ]
        end

        # A spellbook draft is sometimes written as a flat list rather than by rank. Those picks are
        # filed by the spell's own rank.
        it "should file a flat list by each spell's own rank" do
          allow(Pf2emagic).to receive(:get_spell_details).with('Invisibility')
            .and_return([ 'Invisibility', { 'base_level' => 2 } ])

          char = caster(:advancement => { 'spellbook' => [ 'Invisibility' ] })

          expect(DraftSheet.of(char).spellbook['Wizard']).to eq('2' => [ 'Invisibility' ])
        end

        it "should ignore an unfilled pick in a flat list" do
          char = caster(:advancement => { 'spellbook' => [ 'open' ] })

          expect(DraftSheet.of(char).spellbook['Wizard']).to eq({})
        end

        it "should index a draft keyed by class before rank" do
          char = caster(:advancement => { 'spellbook' => { 'Wizard' => { '3' => [ 'Fireball' ] } } })

          expect(DraftSheet.of(char).spellbook['Wizard']['3']).to eq [ 'Fireball' ]
        end
      end

      describe :level do
        it "should be the character's level when nothing is open" do
          expect(DraftSheet.of(char(:level => 5)).level).to eq 5
        end

        # A prerequisite during an advancement is measured against the level being gained.
        it "should be the level being gained while a draft is open" do
          expect(DraftSheet.of(char(:level => 5, :advancing => true)).level).to eq 6
        end
      end

      describe :drafting? do
        it "should say whether a draft is open" do
          expect(DraftSheet.of(char).drafting?).to be false
          expect(DraftSheet.of(char(:advancing => true)).drafting?).to be true
        end
      end
    end
  end
end
