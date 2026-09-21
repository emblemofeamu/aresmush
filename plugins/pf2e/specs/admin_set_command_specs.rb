require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # admin/set through the real command class.
    #
    # Everything it corrects has to survive the next fold, which is what makes this a db spec
    # rather than another AdminSet unit one: the core's grants only matter if the materialiser
    # then agrees with them.
    describe "a staff correction", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Staff#{rand(1000000)}")
        @staff = Character.create(:name => "Boss#{rand(1000000)}")
        Roles.add_role(@staff, 'admin')
        @staff = Character[@staff.id]
        @client = AutoBuilder::CaptureClient.new

        builder = AutoBuilder.new(@char)
        builder.build_level_one('Fighter')
        Roles.add_role(@char, 'approved')
        @char = Character[@char.id]
        Pf2e::Ledger.commit_chargen!(@char)
      end

      after(:each) do
        @char.delete if @char
        @staff.delete if @staff
      end

      def set(item, value)
        @client.clear
        cmd = Command.new("admin/set #{@char.name}/#{item}=#{value}")
        PF2AdminSetCmd.new(@client, cmd, Character[@staff.id]).on_command

        @char = Character[@char.id]
      end

      def score(name)
        Character[@char.id].abilities.to_a.find { |a| a.name == name }.base_val
      end

      it "should keep a score staff set through the next fold" do
        set('ability', 'strength 15')

        expect(score('Strength')).to eq 15

        Pf2e::Ledger.invalidate!(@char)
        Pf2e::Ledger.materialize!(Character[@char.id])

        expect(score('Strength')).to eq 15
      end

      it "should record the correction as staff history rather than a level's" do
        set('ability', 'strength 15')

        row = Character[@char.id].grants.to_a.find { |g| g.kind == 'set_ability_score' }

        expect(row.source_type).to eq 'staff'
        expect(row.granted_by).to eq @staff.name
        # Zero and nil both mean global to the fold, and the row stores what it was handed.
        expect(row.effective_level.to_i).to eq 0
      end

      it "should leave a rollback alone, since a correction is not something a level gave" do
        set('ability', 'strength 15')
        Pf2e.award_xp(Character[@char.id], 5000, 'spec', 'levels')

        Pf2e::Ledger.write(Character[@char.id], :source_type => 'level_up',
                           :source_ref => 'spec', :effective_level => 2) do |txn|
          txn.grant('raise_skill', 'skill' => 'Arcana', 'to' => 'trained')
        end

        Character[@char.id].update(:pf2_level => 2)
        Pf2e.rollback_to_level(Character[@char.id], 2, @staff)

        expect(score('Strength')).to eq 15
      end

      it "should raise a skill through the ledger" do
        set('skill', 'arcana master')

        expect(Pf2eSkills.find_skill('Arcana', Character[@char.id]).prof_level).to eq 'master'
        expect(Pf2e::Ledger.derived(Character[@char.id])['skills']['Arcana']).to eq 'master'
      end

      it "should take a feature back out of the fold" do
        held = Array((Character[@char.id].pf2_features || {})['charclass_features']).first

        set('feature', "delete #{held}")

        expect(Array((Character[@char.id].pf2_features || {})['charclass_features'])).to_not include held
      end

      # Staff correct unapproved characters too, and a draft is not folded from the ledger - so a
      # grant made against one has to be written into the working copy instead.
      describe "on a character still in chargen" do
        before(:each) do
          @draft = Character.create(:name => "Draft#{rand(1000000)}")
          AutoBuilder.new(@draft).build_level_one('Wizard')
          @draft = Character[@draft.id]
        end

        after(:each) { @draft.delete if @draft }

        def set_draft(item, value)
          @client.clear
          cmd = Command.new("admin/set #{@draft.name}/#{item}=#{value}")
          PF2AdminSetCmd.new(@client, cmd, Character[@staff.id]).on_command

          @draft = Character[@draft.id]
        end

        it "should be drafting, so nothing is folded" do
          expect(Pf2e::Ledger.drafting?(@draft)).to be true
        end

        it "should set an ability score" do
          set_draft('ability', 'strength 15')

          expect(Character[@draft.id].abilities.to_a.find { |a| a.name == 'Strength' }.base_val).to eq 15
        end

        it "should add a feature" do
          set_draft('feature', 'add Shield Block')

          expect(Character[@draft.id].pf2_features.values.flatten).to include 'Shield Block'
        end

        it "should keep a corrected score when the character is approved" do
          set_draft('ability', 'strength 15')

          Roles.add_role(@draft, 'approved')
          @draft = Character[@draft.id]
          Pf2e::Ledger.commit_chargen!(@draft)
          Pf2e::Ledger.materialize!(Character[@draft.id])

          expect(Character[@draft.id].abilities.to_a.find { |a| a.name == 'Strength' }.base_val).to eq 15
        end

        it "should take a feature away" do
          held = Array((Character[@draft.id].pf2_features || {})['charclass_features']).first

          set_draft('feature', "delete #{held}")

          expect(Array((Character[@draft.id].pf2_features || {})['charclass_features'])).to_not include held
        end

        it "should add a spell to the spellbook" do
          set_draft('spellbook', 'Wizard add Fireball 3')

          known = Pf2emagic::Entries.known(Character[@draft.id].magic, 'Wizard')

          expect(Array(known['3'])).to include 'Fireball'
        end
      end

      it "should say nothing happened when the value makes no sense" do
        set('ability', 'strength 0')

        expect(score('Strength')).to_not eq 0
        expect(Character[@char.id].grants.to_a.any? { |g| g.kind == 'set_ability_score' }).to be false
      end
    end
  end
end
