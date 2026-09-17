require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Taking back the last step of a draft.
    #
    # A draft step is recorded as the two deltas between the character before it and the character
    # after: what to write to undo it, and what to write to redo it. So the journal knows nothing
    # about draft keys, grant kinds or which hash holds what, and a step that touches something new
    # is recorded without the journal being taught about it.
    #
    # Undo takes the last step only. That is what makes it safe: a step cannot have dependents that
    # were recorded before it, so restoring the values it changed can never orphan an earlier one.
    describe DraftJournal, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Journal#{rand(1000000)}")
        @client = AutoBuilder::CaptureClient.new
      end

      after(:each) { @char.delete if @char }

      def reread
        Character[@char.id]
      end

      def run(text)
        @client.clear
        cmd = Command.new(text)
        handler = [ 'Pf2e', 'Pf2emagic', 'Pf2egear', 'Pf2noms' ].lazy
          .map { |name| (AresMUSH.const_get(name).get_cmd_handler(@client, cmd, reread) rescue nil) }.find { |h| h }

        raise "no handler for #{text}" unless handler

        handler.new(@client, cmd, reread).on_command
        @char = reread
      end

      describe "what a snapshot holds" do
        it "should take the attributes a draft can change" do
          shot = DraftSnapshot.of(@char)

          expect(shot['attrs']).to include 'pf2_to_assign', 'pf2_feats', 'pf2_base_info'
        end

        it "should leave out what a draft does not own" do
          expect(DraftSnapshot.of(@char)['attrs'].keys).to_not include 'pf2_xp', 'pf2_money'
        end

        it "should hold the skill ranks and the ability scores" do
          shot = DraftSnapshot.of(@char)

          expect(shot).to have_key 'skills'
          expect(shot).to have_key 'abilities'
        end

        it "should report only what changed between two of them" do
          before = DraftSnapshot.of(@char)
          @char.update(:pf2_lang => [ 'Kamin' ])
          after = DraftSnapshot.of(reread)

          delta = DraftSnapshot.diff(before, after)

          expect(delta['attrs'].keys).to eq [ 'pf2_lang' ]
          expect(delta['attrs']['pf2_lang']).to eq []
        end

        it "should be nothing when nothing changed" do
          before = DraftSnapshot.of(@char)

          expect(DraftSnapshot.diff(before, DraftSnapshot.of(reread))).to be_empty
        end

        it "should put a skill the step trained back to untrained" do
          Pf2eSkills.factory_default(@char)
          @char = reread

          DraftJournal.step!(@char, 'skill/set') do
            Pf2eSkills.update_skill_for_char('Arcana', Character[@char.id], 'trained', false)
          end

          DraftJournal.undo!(reread)

          expect(Pf2eSkills.find_skill('Arcana', reread).prof_level).to eq 'untrained'
        end

        it "should write a delta back" do
          before = DraftSnapshot.of(@char)
          @char.update(:pf2_lang => [ 'Kamin' ])

          DraftSnapshot.restore!(reread, DraftSnapshot.diff(before, DraftSnapshot.of(reread)))

          expect(Array(reread.pf2_lang)).to eq []
        end
      end

      describe "recording a step" do
        it "should record nothing when the step changed nothing" do
          expect { DraftJournal.step!(@char, 'nothing') { nil } }.to_not change { DraftJournal.steps(reread).size }
        end

        it "should record a step that changed something" do
          DraftJournal.step!(@char, 'lang/set') { Character[@char.id].update(:pf2_lang => [ 'Kamin' ]) }

          expect(DraftJournal.steps(reread).size).to eq 1
          expect(DraftJournal.steps(reread).last.action).to eq 'lang/set'
        end

        it "should keep the steps in the order they happened" do
          DraftJournal.step!(@char, 'first') { Character[@char.id].update(:pf2_lang => [ 'Kamin' ]) }
          DraftJournal.step!(@char, 'second') { Character[@char.id].update(:pf2_lang => [ 'Kamin', 'Myrrish' ]) }

          expect(DraftJournal.steps(reread).map(&:action)).to eq [ 'first', 'second' ]
        end
      end

      describe "undo and redo" do
        before(:each) do
          DraftJournal.step!(@char, 'first') { Character[@char.id].update(:pf2_lang => [ 'Kamin' ]) }
          DraftJournal.step!(@char, 'second') { Character[@char.id].update(:pf2_traits => [ 'khazad' ]) }
        end

        it "should take the last step back" do
          expect(DraftJournal.undo!(reread)).to eq 'second'
          expect(Array(reread.pf2_traits)).to eq []
          expect(Array(reread.pf2_lang)).to eq [ 'Kamin' ]
        end

        it "should take them back one at a time, newest first" do
          DraftJournal.undo!(reread)
          expect(DraftJournal.undo!(reread)).to eq 'first'

          expect(Array(reread.pf2_lang)).to eq []
        end

        it "should put a step back" do
          DraftJournal.undo!(reread)

          expect(DraftJournal.redo!(reread)).to eq 'second'
          expect(Array(reread.pf2_traits)).to eq [ 'khazad' ]
        end

        it "should have nothing to undo once every step is undone" do
          DraftJournal.undo!(reread)
          DraftJournal.undo!(reread)

          expect(DraftJournal.undo!(reread)).to be_nil
        end

        it "should have nothing to redo once every step is back" do
          DraftJournal.undo!(reread)
          DraftJournal.redo!(reread)

          expect(DraftJournal.redo!(reread)).to be_nil
        end

        # A new step after an undo is a new branch, and the step that was taken back is not
        # coming back: keeping it would let redo write over the new one.
        it "should drop the undone steps once a new one is taken" do
          DraftJournal.undo!(reread)
          DraftJournal.step!(reread, 'third') { Character[@char.id].update(:pf2_special => [ 'Something' ]) }

          expect(DraftJournal.redo!(reread)).to be_nil
          expect(DraftJournal.steps(reread).map(&:action)).to eq [ 'first', 'third' ]
        end
      end

      # The journal knows what the character looked like when it last recorded a step. A change
      # made by something that does not record one leaves the two disagreeing, and undoing then
      # would restore values from before a change nobody journaled - so it refuses instead.
      describe "a change nothing recorded" do
        before(:each) do
          DraftJournal.step!(@char, 'first') { Character[@char.id].update(:pf2_lang => [ 'Kamin' ]) }
        end

        it "should know the journal is behind the character" do
          expect(DraftJournal.stale?(reread)).to be false

          reread.update(:pf2_traits => [ 'sneaky' ])

          expect(DraftJournal.stale?(reread)).to be true
        end

        it "should refuse to undo while it is behind" do
          reread.update(:pf2_traits => [ 'sneaky' ])

          expect { DraftJournal.undo!(reread) }.to_not change { Array(reread.pf2_lang) }
        end
      end

      describe "the draft boundaries" do
        it "should drop the journal when the draft commits" do
          builder = AutoBuilder.new(@char)
          builder.build_level_one('Fighter')
          @char = reread

          expect(DraftJournal.steps(@char)).to_not be_empty

          Roles.add_role(@char, 'approved')
          @char = reread
          Pf2e::Ledger.commit_chargen!(@char)

          expect(DraftJournal.steps(reread)).to be_empty
        end

        it "should drop the journal when the draft is thrown away" do
          DraftJournal.step!(@char, 'first') { Character[@char.id].update(:pf2_lang => [ 'Kamin' ]) }

          Pf2e.reset_character(reread)

          expect(DraftJournal.steps(reread)).to be_empty
        end
      end

      describe "through the commands" do
        before(:each) do
          @char.update(:chargen_stage => 4)
          Pf2eAbilities.factory_default(@char)
          Pf2eSkills.factory_default(@char)
          @char = reread

          run "cg/set ancestry=Khazad"
          run "cg/set heritage=Forge"
          run "cg/set background=Acolyte"
          run "cg/set charclass=Fighter"
        end

        it "should record a step for each pick" do
          expect(DraftJournal.steps(reread).map(&:action)).to eq [ 'cg/set ancestry', 'cg/set heritage',
                                                                  'cg/set background', 'cg/set charclass' ]
        end

        it "should take the last pick back" do
          run "cg/undo"

          expect(reread.pf2_base_info['charclass']).to be_blank
          expect(reread.pf2_base_info['background']).to eq 'Acolyte'
        end

        it "should put it back" do
          run "cg/undo"
          run "cg/redo"

          expect(reread.pf2_base_info['charclass']).to eq 'Fighter'
        end

        it "should record a staff correction against the character, not the staff member" do
          staff = Character.create(:name => "Boss#{rand(1000000)}")
          Roles.add_role(staff, 'admin')

          @client.clear
          cmd = Command.new("admin/set #{@char.name}/feature=add Shield Block")
          PF2AdminSetCmd.new(@client, cmd, Character[staff.id]).on_command

          expect(DraftJournal.steps(reread).last.action).to eq "admin/set #{@char.name}/feature"
          expect(DraftJournal.steps(Character[staff.id])).to be_empty

          DraftJournal.undo!(reread)

          expect(reread.pf2_features.values.flatten).to_not include 'Shield Block'

          staff.delete
        end

        it "should take every pick back, and then say there is nothing left" do
          4.times { run "cg/undo" }

          expect(reread.pf2_base_info['ancestry']).to be_blank

          run "cg/undo"

          expect(@client.failures.last).to_not be_nil
        end
      end
    end
  end
end
