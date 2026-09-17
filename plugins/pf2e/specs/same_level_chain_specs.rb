require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # A level that hands out more than one feat slot, where what is picked in the first slot decides
    # what may be picked in the second.
    #
    # A Fighter reaching 2nd level gets a class feat and a skill feat. Picking a class feat that is
    # the prerequisite for a skill feat has to make that skill feat available in the same level, and
    # the reverse order has to be refused. The picks are in the advancement draft rather than on the
    # sheet at that point, so the prerequisite check has to read the draft.
    describe "two feat slots at one level", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Chain#{rand(1000000)}")
        AutoBuilder.new(@char).build_level_one('Fighter')

        Roles.add_role(Character[@char.id], 'approved')
        @char = Character[@char.id]
        Pf2e::Ledger.commit_chargen!(@char)
        Pf2e.award_xp(@char, 5000, 'Spec', 'chain')

        # A fresh builder over a re-read character: the XP award and the approval both write, and
        # a builder holding the instance from before them sees neither.
        @builder = AutoBuilder.new(Character[@char.id])
      end

      after(:each) { @char.delete if @char }

      # A chain laid over the real data, so the class table's slots stay real. The character's own
      # chargen feats are absent from this fixture, which only means the dedication counter cannot
      # see them.
      def chain_feats
        {
          'Gate' => { 'feat_type' => [ 'Charclass' ], 'assoc_charclass' => [ 'Fighter' ],
                      'shortdesc' => 'x' },
          'Unlocked' => { 'feat_type' => [ 'Skill' ], 'prereq' => { 'feat' => [ 'Gate' ] },
                          'shortdesc' => 'x' },
          'NeedsSociety' => { 'feat_type' => [ 'Skill' ], 'prereq' => { 'skill' => [ 'Society/trained' ] },
                              'shortdesc' => 'x' },
          'GivesSociety' => { 'feat_type' => [ 'Charclass' ], 'assoc_charclass' => [ 'Fighter' ],
                              'grants' => { 'skill' => [ 'Society' ] }, 'shortdesc' => 'x' },
          'AtSecond' => { 'feat_type' => [ 'Skill' ], 'prereq' => { 'level' => 2 }, 'shortdesc' => 'x' },
          'AtThird' => { 'feat_type' => [ 'Skill' ], 'prereq' => { 'level' => 3 }, 'shortdesc' => 'x' },
          'Joiner Dedication' => { 'feat_type' => [ 'Charclass', 'Dedication' ],
                                   'assoc_archetype' => [ 'Joiner Archetype' ],
                                   'assoc_class' => [ 'Fighter' ], 'shortdesc' => 'x' },
          'Joiner Study' => { 'feat_type' => [ 'Skill' ], 'assoc_archetype' => [ 'Joiner Archetype' ],
                              'prereq' => { 'feat' => [ 'Joiner Dedication' ] }, 'shortdesc' => 'x' }
        }
      end

      def use_chain_feats
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(chain_feats)
      end

      # Starts the advancement to 2, which hands a Fighter a class feat slot and a skill feat slot.
      def start_advancing
        @builder.clear
        @builder.run 'advance'

        raise "advance refused: #{@builder.failures.first}" unless @builder.failures.empty?
      end

      def take(type, feat)
        @builder.clear
        @builder.run "advance/feat #{type}=#{feat}"

        @builder.failures.empty?
      end

      def held
        (Character[@char.id].pf2_advancement['feats'] || {}).values.flatten.compact
      end

      describe "one pick unlocking another" do
        it "should refuse the dependent feat before its prerequisite is picked" do
          use_chain_feats
          start_advancing

          expect(take('skill', 'Unlocked')).to be false
        end

        it "should allow the dependent feat once the prerequisite is picked at the same level" do
          use_chain_feats
          start_advancing

          expect(take('charclass', 'Gate')).to be true
          expect(take('skill', 'Unlocked')).to be true
          expect(held).to include('Gate', 'Unlocked')
        end

        it "should keep both when the level is committed" do
          use_chain_feats
          start_advancing
          take('charclass', 'Gate')
          take('skill', 'Unlocked')

          @builder.clear
          @builder.run 'advance/done'

          expect(@builder.failures).to be_empty

          char = Character[@char.id]
          all = (char.pf2_feats || {}).values.flatten.compact

          expect(char.pf2_level).to eq 2
          expect(all).to include('Gate', 'Unlocked')
        end
      end

      # A prerequisite met by something the first pick *grants*, rather than by the pick itself.
      describe "a pick whose grant unlocks another" do
        it "should refuse the dependent feat first" do
          use_chain_feats
          start_advancing

          expect(take('skill', 'NeedsSociety')).to be false
        end

        it "should allow it once the granting feat is picked" do
          use_chain_feats
          start_advancing

          expect(take('charclass', 'GivesSociety')).to be true
          expect(take('skill', 'NeedsSociety')).to be true
        end
      end

      # A dedication in the class slot and one of its archetype's feats in the skill slot, both at
      # the same level.
      describe "a dedication and its archetype feat at one level" do
        it "should refuse the archetype feat before the dedication" do
          use_chain_feats
          start_advancing

          expect(take('skill', 'Joiner Study')).to be false
        end

        it "should allow the archetype feat after the dedication" do
          use_chain_feats
          start_advancing

          expect(take('charclass', 'Joiner Dedication')).to be true
          expect(take('skill', 'Joiner Study')).to be true
        end
      end

      # The level a prerequisite is measured against during an advancement is the level being
      # gained, not the one being left.
      describe "a level prerequisite" do
        it "should allow a feat requiring the level being gained" do
          use_chain_feats
          start_advancing

          expect(take('skill', 'AtSecond')).to be true
        end

        it "should refuse a feat requiring the level after that" do
          use_chain_feats
          start_advancing

          expect(take('skill', 'AtThird')).to be false
        end
      end

      # Each slot takes one feat, so a chain cannot consume a slot type twice.
      describe "slot accounting" do
        it "should refuse a second feat of a type whose only slot is spent" do
          use_chain_feats
          start_advancing

          expect(take('charclass', 'Gate')).to be true
          expect(take('charclass', 'GivesSociety')).to be false
        end

        it "should not let the dependent feat take the slot its prerequisite needs" do
          use_chain_feats
          start_advancing

          # Unlocked is a skill feat, so it cannot be spent from the class slot even once Gate is
          # held.
          expect(take('charclass', 'Gate')).to be true
          expect(take('charclass', 'Unlocked')).to be false
        end
      end

      # Abandoning the advancement has to take the whole chain, so a dependent feat cannot outlive
      # the pick that unlocked it.
      describe "resetting the level" do
        it "should drop both picks" do
          use_chain_feats
          start_advancing
          take('charclass', 'Gate')
          take('skill', 'Unlocked')

          @builder.clear
          @builder.run 'advance/reset'

          char = Character[@char.id]
          staged = (char.pf2_advancement['feats'] || {}).values.flatten.compact

          expect(staged).to_not include 'Gate'
          expect(staged).to_not include 'Unlocked'
        end
      end
    end
  end
end
