require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # The class features a character has at level 1.
    #
    # Chargen gathered actions and reactions from the class, the specialty, the heritage and the
    # background - and never gathered `charclass_feature` from any of them. Only advancement wrote
    # features, so every character began play without their class's defining ones: a Barbarian
    # with no Rage, a Monk with no Flurry of Blows, a Fighter with no Reactive Strike. Thirty-nine
    # features across the shipped tables, 27 from classes and 12 from specialties.
    describe "class features at level 1", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Feat#{rand(1000000)}")
      end

      after(:each) do
        @char.delete if @char
      end

      def features_of(charclass)
        AutoBuilder.new(@char).build_level_one(charclass)

        (Character[@char.id].pf2_features || {}).values.flatten.compact.map(&:to_s)
      end

      it "should give a Barbarian their Rage" do
        expect(features_of('Barbarian')).to include 'Rage'
      end

      it "should give a Fighter their Reactive Strike" do
        expect(features_of('Fighter')).to include 'Reactive Strike'
      end

      it "should give a Monk both of theirs" do
        expect(features_of('Monk')).to include('Flurry of Blows', 'Powerful Fist')
      end

      it "should give a Swashbuckler all four of theirs" do
        expect(features_of('Swashbuckler')).to include('Stylish Combatant', 'Panache', 'Precise Strike', 'Confident Finisher')
      end

      it "should give a class with none nothing" do
        # Barbarian's specialty adds none at level 1, so the list is exactly the class's.
        expect(features_of('Barbarian')).to eq [ 'Rage' ]
      end

      # A specialty names features of its own, and those were lost the same way.
      it "should give a Cloistered Cleric their First Doctrine" do
        builder = AutoBuilder.new(@char)
        builder.build_level_one('Cleric')

        features = (Character[@char.id].pf2_features || {}).values.flatten.compact.map(&:to_s)

        expect(features).to include('Divine Font', 'Sanctification')
        expect(features.any? { |f| f.start_with?('First Doctrine') }).to be true
      end

      # Features are sheet state, so they have to be in the ledger like everything else -
      # otherwise a rollback to level 1 would lose them. The ledger is written at approval, not
      # when the draft is finished, so nothing is recorded until then.
      it "should not be in the ledger while chargen is still a draft" do
        AutoBuilder.new(@char).build_level_one('Barbarian')

        expect(Character[@char.id].grants.count).to eq 0
      end

      it "should record them in the ledger when the character is approved" do
        AutoBuilder.new(@char).build_level_one('Barbarian')

        Pf2e::Ledger.commit_chargen!(Character[@char.id])

        granted = Character[@char.id].grants.to_a
                                     .select { |g| g.kind == 'grant_feature' }
                                     .map { |g| g.payload['feature'] }

        expect(granted).to include 'Rage'
      end
    end
  end
end
