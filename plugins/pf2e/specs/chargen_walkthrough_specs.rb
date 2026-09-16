require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Type 1: drive the real command classes, with the real config and a real character, from
    # a blank sheet to a built one. Tagged :dbtest because it needs Redis/Valkey, so
    # `rake spec:unit` skips it and `rake spec:db` runs it.
    describe "chargen walkthrough", :dbtest => true do

      # Stands in for a connected player: records what the command said instead of writing to
      # a socket, so a spec can assert on failures without parsing text.
      class CaptureClient
        attr_reader :successes, :failures, :oocs

        def initialize
          @successes = []
          @failures = []
          @oocs = []
        end

        def logged_in?
          true
        end

        def emit_success(msg)
          @successes << msg.to_s
        end

        def emit_failure(msg)
          @failures << msg.to_s
        end

        def emit_ooc(msg)
          @oocs << msg.to_s
        end

        def emit(msg)
          @successes << msg.to_s
        end

        def to_s
          "CaptureClient"
        end
      end

      # Config and the database are (re)loaded per example: other spec files stub
      # Global.read_config, and a leftover stub leaves the database url empty.
      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = CaptureClient.new
        @char = Character.create(:name => "Walkthrough#{rand(100000)}")
        @char.update(:chargen_stage => 4)
        Pf2eAbilities.factory_default(@char)
        Pf2eSkills.factory_default(@char)
      end

      after(:each) do
        @char.delete if @char
      end

      # Runs a command the way the dispatcher does: parse, check, handle.
      def run(cmd_class, text)
        handler = cmd_class.new(@client, Command.new(text), @char)
        handler.on_command
        @char = Character[@char.id]
        handler
      end

      def expect_no_failures
        expect(@client.failures).to eq []
      end

      it "should take a blank character through base info with the real commands" do
        run PF2SetChargenCmd, "cg/set ancestry=Khazad"
        run PF2SetChargenCmd, "cg/set heritage=Forge"
        run PF2SetChargenCmd, "cg/set background=Acolyte"
        run PF2SetChargenCmd, "cg/set charclass=Wizard"
        run PF2SetChargenCmd, "cg/set specialize=Mana Syntaxia"
        run PF2SetChargenCmd, "cg/set specialize_info=Spell Substitution"
        run PF2SetChargenCmd, "cg/set alignment=BL"
        run PF2SetChargenCmd, "cg/set deity=Althea"

        expect_no_failures
        expect(@char.pf2_base_info['ancestry']).to eq 'Khazad'
        expect(@char.pf2_base_info['heritage']).to eq 'Forge'
        expect(@char.pf2_base_info['background']).to eq 'Acolyte'
        expect(@char.pf2_base_info['charclass']).to eq 'Wizard'
        expect(@char.pf2_base_info['specialize']).to eq 'Department of Mana Syntaxia'
        expect(@char.pf2_base_info['specialize_info']).to eq 'Spell Substitution'
        expect(@char.pf2_faith['alignment']).to eq 'BL'
        expect(@char.pf2_faith['deity']).to eq 'Althea'
      end

      it "should tell the player what to pick next as they go" do
        run PF2SetChargenCmd, "cg/set ancestry=Khazad"

        expect(@client.oocs.join(" ")).to include 'Forge'
      end

      it "should refuse a heritage that belongs to another ancestry" do
        run PF2SetChargenCmd, "cg/set ancestry=Khazad"
        run PF2SetChargenCmd, "cg/set heritage=Cavern"

        expect(@client.failures.size).to eq 1
        expect(@char.pf2_base_info['heritage']).to eq ''
      end

      it "should clear the heritage when the ancestry is changed again" do
        run PF2SetChargenCmd, "cg/set ancestry=Khazad"
        run PF2SetChargenCmd, "cg/set heritage=Forge"
        run PF2SetChargenCmd, "cg/set ancestry=Sildanyar"

        expect_no_failures
        expect(@char.pf2_base_info['heritage']).to eq ''
      end

      it "should commit base info and then accept ability boosts" do
        run PF2SetChargenCmd, "cg/set ancestry=Khazad"
        run PF2SetChargenCmd, "cg/set heritage=Forge"
        run PF2SetChargenCmd, "cg/set background=Acolyte"
        run PF2SetChargenCmd, "cg/set charclass=Wizard"
        run PF2SetChargenCmd, "cg/set specialize=Mana Syntaxia"
        run PF2SetChargenCmd, "cg/set specialize_info=Spell Substitution"
        run PF2SetChargenCmd, "cg/set alignment=BL"
        run PF2SetChargenCmd, "cg/set deity=Althea"

        run PF2CommitCmd, "cg/commit info"

        expect_no_failures
        expect(@char.pf2_baseinfo_locked).to be true
        expect(@char.pf2_checkpoint).to eq 'info'

        free_slots = @char.pf2_boosts_working['free']
        expect(free_slots).to_not be_nil

        run PF2BoostSetCmd, "boost/set free=Constitution"

        expect_no_failures
        expect(@char.pf2_boosts_working['free']).to include 'Constitution'
      end

      it "should keep a chargen language pick in the draft, out of the ledger" do
        # The skills stage hands out these slots; set them directly so this example stays
        # about the language command rather than replaying all of chargen.
        @char.update(:pf2_abilities_locked => true, :pf2_to_assign => { 'open languages' => [ 'open', 'open' ] })

        run PF2LanguageSetCmd, "lang/set Silya"

        expect_no_failures
        expect(@char.pf2_to_assign['open languages']).to include 'Silya'
        expect(@char.pf2_lang).to include 'Silya'

        # Nothing is history yet: a character in chargen is a draft.
        expect(@char.grants.count).to eq 0
      end

      it "should take a chargen language pick back out of the draft" do
        @char.update(:pf2_abilities_locked => true, :pf2_to_assign => { 'open languages' => [ 'open', 'open' ] })

        run PF2LanguageSetCmd, "lang/set Silya"
        run PF2LanguageUnSetCmd, "lang/unset Silya"

        expect_no_failures
        expect(@char.pf2_lang).to_not include 'Silya'
        expect(@char.pf2_to_assign['open languages']).to eq [ 'open', 'open' ]
        expect(@char.grants.count).to eq 0
      end

      it "should write the whole chargen draft to the ledger when the character is approved" do
        @char.update(:pf2_abilities_locked => true, :pf2_to_assign => { 'open languages' => [ 'open', 'open' ] })

        run PF2LanguageSetCmd, "lang/set Silya"

        Pf2e::Ledger.commit_chargen!(@char)
        @char = Character[@char.id]

        languages = Pf2e::Ledger.rows(@char).select { |g| g['kind'] == 'add_language' }

        expect(languages.map { |g| g['payload']['language'] }).to include 'Silya'
        expect(languages.first['source_type']).to eq 'chargen'
        expect(languages.first['effective_level']).to eq 1

        # And committing twice does not double the history.
        expect { Pf2e::Ledger.commit_chargen!(@char) }.to_not change { Character[@char.id].grants.count }
      end

      it "should refuse a rare language through the command" do
        @char.update(:pf2_abilities_locked => true, :pf2_to_assign => { 'open languages' => [ 'open' ] })

        run PF2LanguageSetCmd, "lang/set Mynsandraal"

        expect(@client.failures).to_not be_empty
        expect(@char.pf2_lang).to_not include 'Mynsandraal'
      end

      it "should refuse a boost before base info is locked" do
        run PF2SetChargenCmd, "cg/set ancestry=Khazad"
        run PF2BoostSetCmd, "boost/set free=Constitution"

        expect(@client.failures).to_not be_empty
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # A full climb, driven by the same commands a player would type. Slow (a couple of minutes
    # per class), so it lives behind the :dbtest tag with the rest.
    describe "level 20 builds", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Climb#{rand(100000)}")
      end

      after(:each) do
        @char.delete if @char
      end

      # Every class, from a blank character to level 20, through the commands a player types.
      #
      # What each climb is measured against is the class's *own* advance table: across levels
      # 2-20 the table promises so many feats of each type, and the finished character must
      # hold exactly that many more than they finished chargen with. Whether the table itself
      # matches PF2e is a separate question, asserted against the Player Core schedule in
      # class_table_specs.rb - so a config that drifts from the rules fails there, and an
      # engine that drifts from the config fails here.
      def self.class_names
        (Global.read_config('pf2e_class') || {}).keys.sort
      end

      # Feats the advance table hands out between level 2 and level 20, by type.
      #
      # Two sources, both in config. `choose_feat` is the ordinary slot the player fills.
      # `grant_choice` names a class feature that hands over a feat of its own from a pool -
      # the Investigator's Skillful Lessons at every odd level, the Swashbuckler's Stylish
      # Tricks at 3, 7 and 15 - and those are feats the character ends up holding too.
      def table_feats(charclass)
        table = Global.read_config('pf2e_class', charclass, 'advance') || {}
        blocks = Global.read_config('pf2e_class', charclass, 'feat_choice') || {}

        table.each_with_object(Hash.new(0)) do |(_level, data), counts|
          next unless data.is_a?(Hash)

          Array(data['choose_feat']).each { |type| counts[type.to_s.downcase] += 1 }

          Array(data['grant_choice']).each do |name|
            pool = (blocks[name] || {})['from_feats']
            next unless pool

            counts[pool['feat_type'].to_s.downcase] += 1
          end
        end
      end

      class_names.each do |charclass|
        it "should carry a #{charclass} from nothing to level 20" do
          builder = AutoBuilder.new(@char)

          builder.build_level_one(charclass)
          at_one = builder.summary['feats']

          builder.advance_to(20)
          summary = builder.summary

          # Print why it stalled before asserting, so a failure names the level and reason.
          puts "  #{charclass} stalled: #{builder.notes.last(2).join(' | ')}" if summary['level'] != 20

          expect(summary['level']).to eq 20

          table_feats(charclass).each_pair do |type, expected|
            gained = summary['feats'][type].to_i - at_one[type].to_i

            expect(gained).to eq(expected), "#{charclass} gained #{gained} #{type} feats between 2 and 20; its table promises #{expected}"
          end

          # Every one of those choices is in the ledger, and the sheet is a fold of it.
          expect(summary['grants']).to be > 50
        end
      end

      it "should leave a level 20 character's sheet reproducible from the ledger alone" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 20)

        expect(builder.summary['level']).to eq 20

        # Refolding and re-materialising must not move anything: the sheet is already exactly
        # what the ledger says it is.
        Pf2e::Ledger.invalidate!(char)
        ops = Pf2e::Ledger.materialize!(char)

        expect(ops).to eq 0
      end

      it "should roll a level 20 character back to 19 and forward again without losing history" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Fighter', 20)

        expect(builder.summary['level']).to eq 20

        rows_at_20 = Pf2e::Ledger.rows(char).size
        skills_at_20 = char.skills.to_a.count { |s| s.prof_level != 'untrained' }

        marker = Pf2e::Ledger.rollback_to_level!(char, 20)
        char = Character[char.id]

        expect(char.pf2_level).to eq 19

        # Nothing is deleted by an undo - that is what makes the redo below possible.
        expect(Pf2e::Ledger.rows(char).size).to eq rows_at_20
        expect(Pf2e::Ledger.rows(char).count { |r| !r['reverted_by'].blank? }).to be > 0

        Pf2e::Ledger.redo_rollback!(char, marker)
        char = Character[char.id]

        expect(char.pf2_level).to eq 20
        expect(Pf2e::Ledger.rows(char).count { |r| !r['reverted_by'].blank? }).to eq 0
        expect(char.skills.to_a.count { |s| s.prof_level != 'untrained' }).to eq skills_at_20
      end
    end
  end
end
