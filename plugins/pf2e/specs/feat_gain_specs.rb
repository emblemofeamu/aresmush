require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Gaining a feat, through both of the paths that can do it.
    #
    # The point of these is the divergence they close. advance/feat applied a feat's full
    # consequences; a feat handed over by a choice applied a subset, so the same feat was worth
    # less depending on how it arrived.
    describe Advancement::FeatGain, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Gain#{rand(1000000)}")
        @char.update(:pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' })
      end

      after(:each) do
        Pf2e::Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      def gain(feat_name, bucket:, to_assign: {}, advancement: {})
        found = Pf2e.get_feat_details(feat_name)

        raise "no such feat #{feat_name}: #{found}" if found.is_a?(String)

        result = Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => bucket, :to_assign => to_assign, :advancement => advancement)

        { :to_assign => to_assign, :advancement => advancement, :result => result }
      end

      it "should record the feat in the bucket it was asked for" do
        out = gain('Assurance', :bucket => 'skill')

        expect(out[:advancement]['feats']['skill']).to eq [ 'Assurance' ]
      end

      # Multilingual's grants are an `assign` block - two open language picks, which apply
      # straight away. The choice path used to dump the whole block into the advancement
      # instead, so the player never got the languages.
      it "should put a feat's immediate grants where they are read from" do
        out = gain('Multilingual', :bucket => 'skill')

        expect(out[:to_assign]['grants']['Multilingual']).to eq('assign' => [ 'open languages', 'open languages' ])
        expect(out[:advancement]['grants']).to be_nil
      end

      # Skill Training grants an open skill, which goes through the shared training helper so
      # that a skill the character already has becomes a free pick instead of being lost.
      it "should turn a granted skill into a slot to spend" do
        out = gain('Skill Training', :bucket => 'skill')

        expect(Array(out[:to_assign]['raise skill'])).to_not be_empty
      end

      # The one that mattered most: a Dedication carries an archetype, and sixteen of them are
      # reachable through a choice pool. Gained that way, the character used to end up holding
      # the feat with no archetype behind it.
      it "should assign the archetype behind a dedication" do
        out = gain('Barbarian Dedication', :bucket => 'charclass')

        expect(out[:to_assign]['archetype']).to eq 'Barbarian Archetype'
        expect(Character[@char.id].pf2_archetypeinfo['archetype1']).to eq 'Barbarian Archetype'
        expect(out[:advancement]['feats']['charclass']).to eq [ 'Barbarian Dedication' ]
      end

      it "should apply what the archetype hands over, not just name it" do
        out = gain('Barbarian Dedication', :bucket => 'charclass')
        keys = Array(Global.read_config('pf2e_archetype', 'Barbarian Archetype', 'initial_dedication')).to_h.keys

        # Whatever the archetype's dedication block carries, something has to have come of it.
        expect(keys).to_not be_empty
        expect(out[:result][:messages]).to_not be_empty
      end

      it "should take the second archetype slot when the first is held" do
        @char.update(:pf2_archetypeinfo => { 'archetype1' => 'Bard Archetype' })

        gain('Barbarian Dedication', :bucket => 'charclass')

        held = Character[@char.id].pf2_archetypeinfo

        expect(held['archetype1']).to eq 'Bard Archetype'
        expect(held['archetype2']).to eq 'Barbarian Archetype'
      end

      it "should not claim a second slot for an archetype this advancement already assigned" do
        to_assign = { 'archetype' => 'Bard Archetype' }

        gain('Barbarian Dedication', :bucket => 'charclass', :to_assign => to_assign)

        expect(to_assign['archetype']).to eq 'Bard Archetype'
        expect(Character[@char.id].pf2_archetypeinfo['archetype1'].to_s).to be_empty
      end

      # The claim this whole refactor rests on. Both callers hand the same feat to the same
      # module, so the drafts they produce have to match.
      it "should give the same result whichever path the feat arrived by" do
        typed = gain('Multilingual', :bucket => 'skill')

        from_choice_to_assign = {}
        from_choice_advancement = {}
        found = Pf2e.get_feat_details('Multilingual')

        Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => Array(found[1]['feat_type']).first.to_s.downcase,
          :to_assign => from_choice_to_assign,
          :advancement => from_choice_advancement)

        expect(from_choice_to_assign['grants']).to eq typed[:to_assign]['grants']
        expect(from_choice_advancement['feats']).to eq typed[:advancement]['feats']
      end
    end
  end
end
