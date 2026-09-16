require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Undo, redo and revocation against a real character, driven the way the game drives them.
    #
    # The boundary these specs defend: a *draft* (chargen before approval, an advancement
    # before advance/done) lives on the character's own attributes and writes nothing to the
    # ledger, so abandoning one costs nothing and leaves no trace. A *finalized* change is a
    # ledger transaction, and undoing it marks rows rather than deleting them - which is the
    # only reason a redo can exist at all.
    #
    # Builds stop at low levels deliberately: each one is a full command-driven climb, and
    # nothing here needs level 20 to be true.
    describe "undo, redo and revocation", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Undo#{rand(100000)}")
      end

      after(:each) do
        @char.delete if @char
      end

      def trained_count(char)
        char.skills.to_a.count { |s| s.prof_level != 'untrained' }
      end

      # --------------------------------------------------------------------------------
      # Drafts: nothing reaches the ledger until the commit boundary
      # --------------------------------------------------------------------------------

      it "should keep the whole of chargen in the draft until approval" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 1)

        # A finished, unapproved chargen: a full sheet and an empty ledger.
        expect(trained_count(char)).to be > 0
        expect(char.grants.count).to eq 0
        expect(Pf2e::Ledger.finalized?(char)).to be false
      end

      it "should rewind a chargen checkpoint without writing to the ledger" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 1)

        trained_before = trained_count(char)

        builder.clear
        char = builder.run "cg/restore info"

        expect(builder.failures).to be_empty

        # The sheet is genuinely rewound - and the ledger, which was never written, stays empty.
        expect(char.pf2_baseinfo_locked).to be_falsey
        expect(trained_count(char)).to be < trained_before
        expect(char.grants.count).to eq 0
      end

      it "should discard an abandoned advancement without touching the ledger" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 4)

        expect(builder.summary['level']).to eq 4

        rows_before = Pf2e::Ledger.rows(char).size
        feats_before = Array(char.pf2_feats['charclass']).size

        builder.clear
        builder.run "advance"
        6.times { break if builder.resolve_outstanding(:advance).zero? }
        builder.run "advance/reset"
        char = Character[builder.char.id]

        expect(char.advancing).to be_falsey
        expect(char.pf2_advancement).to be_blank
        expect(char.pf2_level).to eq 4
        expect(Array(char.pf2_feats['charclass']).size).to eq feats_before
        expect(Pf2e::Ledger.rows(char).size).to eq rows_before
      end

      # --------------------------------------------------------------------------------
      # Finalized: undo marks, redo unmarks
      # --------------------------------------------------------------------------------

      it "should undo and redo a single level, feats included" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 6)

        expect(builder.summary['level']).to eq 6

        class_feats = Array(char.pf2_feats['charclass']).size
        skill_feats = Array(char.pf2_feats['skill']).size
        trained = trained_count(char)

        expect(Pf2e.rollback_to_level(char, 6)).to be_nil
        char = Character[char.id]

        # Level 6 is an even level: one class feat and one skill feat arrived with it, and
        # both go back when it does.
        expect(char.pf2_level).to eq 5
        expect(Array(char.pf2_feats['charclass']).size).to eq(class_feats - 1)
        expect(Array(char.pf2_feats['skill']).size).to eq(skill_feats - 1)

        expect(Pf2e.redo_rollback(char)).to be_nil
        char = Character[char.id]

        expect(char.pf2_level).to eq 6
        expect(Array(char.pf2_feats['charclass']).size).to eq class_feats
        expect(Array(char.pf2_feats['skill']).size).to eq skill_feats
        expect(trained_count(char)).to eq trained
      end

      it "should undo several levels at once and redo them together" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 6)

        expect(builder.summary['level']).to eq 6

        class_feats = Array(char.pf2_feats['charclass']).size
        rows = Pf2e::Ledger.rows(char).size

        expect(Pf2e.rollback_to_level(char, 4)).to be_nil
        char = Character[char.id]

        expect(char.pf2_level).to eq 3
        expect(Array(char.pf2_feats['charclass']).size).to be < class_feats

        # An undo deletes nothing; it is the marking that a redo reads back, and the marker
        # is kept on the character so staff can reach the redo without the log.
        expect(Pf2e::Ledger.rows(char).size).to eq rows
        expect(Pf2e::Ledger.rows(char).count { |r| !r['reverted_by'].blank? }).to be > 0
        expect(char.pf2_rollback_marker).to_not be_blank

        expect(Pf2e.redo_rollback(char)).to be_nil
        char = Character[char.id]

        expect(char.pf2_level).to eq 6
        expect(Array(char.pf2_feats['charclass']).size).to eq class_feats
        expect(Pf2e::Ledger.rows(char).count { |r| !r['reverted_by'].blank? }).to eq 0
        expect(char.pf2_rollback_marker).to be_blank
      end

      # --------------------------------------------------------------------------------
      # Boons: dormant on the way down, back by themselves on the way up
      # --------------------------------------------------------------------------------

      it "should leave a levelled boon dormant rather than reverted when it is rolled back past" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 6)

        Pf2e::Ledger.write(char, :source_type => 'boon', :source_ref => 'job-1', :effective_level => 6, :granted_by => 'Vardama') do |txn|
          txn.grant('add_language', 'language' => 'Sylhart')
        end
        char = Character[char.id]

        expect(char.pf2_lang).to include 'Sylhart'

        expect(Pf2e.rollback_to_level(char, 6)).to be_nil
        char = Character[char.id]

        expect(char.pf2_level).to eq 5
        expect(char.pf2_lang).to_not include 'Sylhart'

        # Dormant, not undone: a rollback only reaches level_up rows, and the boon is still
        # live at the level it was written for.
        boon = Pf2e::Ledger.rows(char).find { |g| g['source_type'] == 'boon' }

        expect(boon['reverted_by']).to be_blank
        expect(Pf2e::Ledger.derived(char, :at_level => 6)['languages']).to include 'Sylhart'
      end

      it "should keep a global boon through a rollback" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 6)

        Pf2e::Ledger.write(char, :source_type => 'boon', :source_ref => 'job-2', :effective_level => nil) do |txn|
          txn.grant('add_language', 'language' => 'Sylhart')
        end
        char = Character[char.id]

        expect(Pf2e.rollback_to_level(char, 4)).to be_nil
        char = Character[char.id]

        expect(char.pf2_level).to eq 3
        expect(char.pf2_lang).to include 'Sylhart'
      end

      it "should revoke one boon without disturbing the rest of the sheet" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 3)

        Pf2e::Ledger.write(char, :source_type => 'boon', :source_ref => 'job-3', :effective_level => nil) do |txn|
          txn.grant('add_language', 'language' => 'Sylhart')
        end
        char = Character[char.id]

        languages = Array(char.pf2_lang).size
        trained = trained_count(char)
        feats = Array(char.pf2_feats['charclass']).size

        Pf2e::Ledger.revert_matching!(char, 'add_language', { 'language' => 'Sylhart' }, :by => 'staff-revoke')
        char = Character[char.id]

        expect(Array(char.pf2_lang).size).to eq(languages - 1)
        expect(char.pf2_lang).to_not include 'Sylhart'

        # Everything the boon did not grant is untouched.
        expect(trained_count(char)).to eq trained
        expect(Array(char.pf2_feats['charclass']).size).to eq feats
      end

      # --------------------------------------------------------------------------------
      # XP is a fold too, so undo has to move it
      # --------------------------------------------------------------------------------

      it "should hand back the xp a rolled-back level spent" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 4)

        xp_at_4 = char.pf2_xp

        expect(Pf2e.rollback_to_level(char, 4)).to be_nil
        char = Character[char.id]

        expect(char.pf2_xp).to eq(xp_at_4 + Pf2e::ADVANCEMENT_XP_COST)

        expect(Pf2e.redo_rollback(char)).to be_nil
        char = Character[char.id]

        expect(char.pf2_xp).to eq xp_at_4
      end
    end
  end
end
