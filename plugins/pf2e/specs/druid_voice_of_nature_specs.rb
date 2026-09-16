require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # The Druid's Voice of Nature, which PF2e states as "You gain your choice of the Animal
    # Empathy or Plant Empathy druid feat" (Player Core, via Archives of Nethys).
    #
    # The table used to put those two names in `choose_feat`, which holds slot *types*. Chargen
    # acts only on 'charclass' and 'skill' entries there, so both were inert: no Druid received
    # either feat, and none was offered a choice. See finding 29.
    describe "the Druid's Voice of Nature", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Druid#{rand(1000000)}")
      end

      after(:each) do
        @char.delete if @char
      end

      # `build_level_one` resolves whatever chargen asks for, so a Druid who finishes chargen has
      # made the choice.
      def built
        AutoBuilder.new(@char).build_level_one('Druid')

        Character[@char.id]
      end

      it "should leave the druid holding one of the two feats" do
        held = (built.pf2_feats || {}).values.flatten.compact.map(&:to_s)

        expect(held.count { |f| [ 'Animal Empathy', 'Plant Empathy' ].include?(f) }).to eq 1
      end

      it "should file it as a class feat, which is what the game calls it" do
        feats = built.pf2_feats

        expect(Array(feats['charclass']).any? { |f| f.to_s.end_with?('Empathy') }).to be true
      end

      # `pending_feat_choices` lists every choice on the sheet, resolved or not - `cg/info` reads
      # it to describe one - so what matters is that no slot is still 'open'.
      it "should leave no slot of the choice still open" do
        slots = Pf2e.pending_feat_choices(built)['Voice of Nature']

        expect(slots).to_not include 'open'
      end

      it "should offer exactly the two feats and nothing else" do
        # Before any pick is made, the options are the pair the feature names.
        @char.update(:pf2_base_info => { 'charclass' => 'Druid' })
        block = Global.read_config('pf2e_class', 'Druid', 'chargen')['feat_choice']['Voice of Nature']

        expect(Pf2e.choice_options(Character[@char.id], 'Voice of Nature', block).sort)
          .to eq [ 'Animal Empathy', 'Plant Empathy' ]
      end

      # The druid's first *class feat* is at 2nd level, so chargen must not hand out a class feat
      # slot as well as the Voice of Nature choice.
      it "should not also open a level 1 class feat slot" do
        expect(Global.read_config('pf2e_class', 'Druid', 'chargen')['choose_feat']).to be_nil
      end
    end
  end
end
