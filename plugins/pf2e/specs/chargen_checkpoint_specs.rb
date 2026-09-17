require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Rewinding a chargen stage.
    #
    # A checkpoint is the character as they stood when a stage began, and `cg/restore` puts that
    # back. What the stage produced goes; everything the stages before it produced stays, whether
    # or not the restore path happens to rebuild it.
    describe "a chargen checkpoint", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Restore#{rand(1000000)}")
      end

      after(:each) { @char.delete if @char }

      # The builder takes the Acolyte background, which grants Student of the Canon while the
      # skills stage is locking.
      def built
        @builder = AutoBuilder.new(@char)
        @builder.build_level_one('Fighter')

        Character[@char.id]
      end

      def restore(checkpoint)
        @builder.clear
        char = @builder.run "cg/restore #{checkpoint}"

        expect(@builder.failures).to be_empty

        char
      end

      # The rewind itself: the feats chosen after the stage began are gone, and the slots they
      # spent are open again. Without this the rest of the file passes against a restore that
      # does nothing, since everything else it checks is true either way.
      it "should take back the picks made after the stage began" do
        char = built
        after_the_stage = DraftSheet.of(char).feats_by_bucket.values_at('ancestry', 'charclass').flatten.compact

        expect(after_the_stage).to_not be_empty

        char = restore('skills')
        held = DraftSheet.of(char).feat_names

        after_the_stage.each { |feat| expect(held).to_not include feat.upcase }

        # And the slots they spent: the open-pick bag is the one the stage started with.
        expect(char.pf2_to_assign).to eq Pf2e::Checkpoints.attrs_at(char, 'skills')['pf2_to_assign']
      end

      it "should keep a feat the background granted when the skills stage is rewound" do
        char = built

        expect(DraftSheet.of(char).feat_names).to include 'STUDENT OF THE CANON'

        expect(DraftSheet.of(restore('skills')).feat_names).to include 'STUDENT OF THE CANON'
      end

      it "should keep the languages the player picked when the skills stage is rewound" do
        char = built
        picked = Array(char.pf2_to_assign['open languages']).reject { |l| l.to_s.casecmp?('open') }

        expect(picked).to_not be_empty

        # Through DraftSheet: a picked language is the draft's, and the sheet's own list is what
        # the ancestry and background gave them.
        held = DraftSheet.of(restore('skills')).languages

        picked.each { |language| expect(held).to include language }
      end

      it "should leave the character standing at the stage before the one rewound to" do
        built

        expect(restore('skills').pf2_checkpoint).to eq 'abilities'
        expect(Character[@char.id].pf2_skills_locked).to be_falsey
      end

      # Rewinding a stage reopens that stage and nothing before it, so what base options built -
      # the ancestry's traits and size, the class's features - is still there.
      it "should keep the base options stage's work when the abilities stage is rewound" do
        built
        features = Character[@char.id].pf2_features

        char = restore('abilities')

        expect(char.pf2_traits).to include 'khazad'
        expect(char.pf2_movement['Size']).to_not be_blank
        expect(char.pf2_features).to eq features
        expect(char.pf2_baseinfo_locked).to be true
        expect(char.pf2_abilities_locked).to be_falsey
      end

      # The picks the stage needed were restored with it, so there is nothing left open and the
      # stage commits straight away.
      it "should let the rewound stage be committed again" do
        built
        restore('skills')

        @builder.clear
        @builder.run "commit skills"

        expect(@builder.failures).to be_empty
        expect(Character[@char.id].pf2_skills_locked).to be true
      end
    end
  end
end
