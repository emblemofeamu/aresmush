require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Feats that hand over other things: another feat, a skill, a lore, a feat with its choice
    # already decided.
    #
    # The matrix walks the shapes `grants` uses in the shipped data, and then the shapes that
    # terminate a chain: a feat that grants itself, a pair that grant each other, and a grant the
    # character does not qualify for.
    describe :do_feat_grants, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Chain#{rand(1000000)}")
        @char.update(:pf2_level => 5,
                     :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human', 'heritage' => 'Versatile Human' },
                     :pf2_feats => { 'charclass' => [], 'skill' => [], 'general' => [], 'ancestry' => [] })

        @client = double(:emit_ooc => nil, :emit_success => nil, :emit_failure => nil, :emit => nil)
      end

      after(:each) { @char.delete if @char }

      def feats
        {
          'Giver' => { 'feat_type' => [ 'General' ], 'grants' => { 'feat' => [ 'Gift' ] } },
          'Gift' => { 'feat_type' => [ 'Skill' ] },
          'SkillGiver' => { 'feat_type' => [ 'General' ], 'grants' => { 'skill' => [ 'Society' ] } },
          'TwoStep' => { 'feat_type' => [ 'General' ], 'grants' => { 'feat' => [ 'Middle' ] } },
          'Middle' => { 'feat_type' => [ 'General' ], 'grants' => { 'skill' => [ 'Arcana' ] } },
          'Demanding' => { 'feat_type' => [ 'General' ], 'grants' => { 'feat' => [ 'Gated' ] } },
          'Gated' => { 'feat_type' => [ 'General' ], 'prereq' => { 'level' => 20 } },

          # A feat that grants itself, which is a shape the shipped data contains.
          'Ouroboros' => { 'feat_type' => [ 'General' ], 'grants' => { 'feat' => [ 'Ouroboros' ] } },

          # A pair that grant each other.
          'Ping' => { 'feat_type' => [ 'General' ], 'grants' => { 'feat' => [ 'Pong' ] } },
          'Pong' => { 'feat_type' => [ 'General' ], 'grants' => { 'feat' => [ 'Ping' ] } },

          # Repeatable, so a second grant of it is legal and a third is not.
          'Twice' => { 'feat_type' => [ 'General' ], 'repeatable' => 2 }
        }
      end

      def grant(from, held: [])
        char = Character[@char.id]
        char.update(:pf2_feats => { 'general' => [ from ] + held })

        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(feats)

        Pf2e.do_feat_grants(Character[@char.id], feats[from]['grants'], 'Fighter', @client)

        Character[@char.id]
      end

      # An unapproved character is a draft, so a granted feat is held in the draft rather than on
      # the sheet. DraftSheet is what the rules read, and what a commit boundary records from.
      def held_feats(char)
        DraftSheet.of(char).feats_by_bucket.values.flatten.compact
      end

      describe "a feat that grants a feat" do
        it "should hand the feat over" do
          expect(held_feats(grant('Giver'))).to include 'Gift'
        end

        it "should file it under the heading its own type names" do
          char = grant('Giver')

          expect(Array(DraftSheet.of(char).feats_by_bucket['skill'])).to include 'Gift'
        end
      end

      describe "a feat that grants a skill" do
        it "should train the skill" do
          char = grant('SkillGiver')

          expect(Pf2eSkills.get_skill_prof(char, 'Society')).to_not eq 'untrained'
        end
      end

      describe "a two-step chain" do
        it "should follow the grant of the granted feat" do
          char = grant('TwoStep')

          expect(held_feats(char)).to include 'Middle'
          expect(Pf2eSkills.get_skill_prof(char, 'Arcana')).to_not eq 'untrained'
        end
      end

      describe "a grant the character does not qualify for" do
        it "should not hand it over" do
          expect(held_feats(grant('Demanding'))).to_not include 'Gated'
        end
      end

      # The shapes that have to terminate. Without a repeat check on the grant, each of these
      # recurses until the stack gives out, which takes the command down with it.
      describe "a chain that closes on itself" do
        it "should grant a self-granting feat no more than its repeat limit allows" do
          char = grant('Ouroboros')

          expect(held_feats(char).count { |f| f == 'Ouroboros' }).to eq 1
        end

        it "should terminate a pair that grant each other" do
          char = grant('Ping')

          expect(held_feats(char).count { |f| f == 'Ping' }).to eq 1
          expect(held_feats(char).count { |f| f == 'Pong' }).to eq 1
        end

        it "should still grant a repeatable feat a second time" do
          # Held once already, and its limit is two, so the grant is legal.
          char = grant('Giver', :held => [ 'Twice' ])

          allow(Global).to receive(:read_config).with('pf2e_feats')
            .and_return(feats.merge('Giver' => { 'feat_type' => [ 'General' ], 'grants' => { 'feat' => [ 'Twice' ] } }))

          Pf2e.do_feat_grants(Character[@char.id], { 'feat' => [ 'Twice' ] }, 'Fighter', @client)

          expect(held_feats(Character[@char.id]).count { |f| f == 'Twice' }).to eq 2
        end
      end

      # The shipped data, checked for the shapes the engine has to handle.
      describe "the shipped feat data" do
        def all_feats
          @all_feats ||= Global.read_config('pf2e_feats') || {}
        end

        def granted_name(entry)
          entry.is_a?(Hash) ? entry['name'] : entry
        end

        it "should name only feats that exist" do
          dangling = all_feats.flat_map do |name, info|
            next [] unless info.is_a?(Hash) && info['grants'].is_a?(Hash)

            Array(info['grants']['feat']).filter_map do |entry|
              granted = granted_name(entry)
              "#{name} grants #{granted.inspect}" unless all_feats.key?(granted)
            end
          end

          expect(dangling).to eq []
        end

        # 'open' is the marker for a skill the player chooses, so it is a legal entry here and not
        # the name of anything.
        it "should name only skills that exist, or an open pick" do
          skills = (Global.read_config('pf2e_skills') || {}).keys + [ 'open' ]

          unknown = all_feats.flat_map do |name, info|
            next [] unless info.is_a?(Hash) && info['grants'].is_a?(Hash)

            Array(info['grants']['skill']).filter_map do |skill|
              "#{name} grants skill #{skill.inspect}" unless skills.include?(skill.to_s)
            end
          end

          expect(unknown).to eq []
        end

        # A feat naming itself under `grants` recurses through add_granted_feat. The repeat check
        # ends it, and no shipped feat does it any more.
        it "should have no feat that grants itself" do
          selfish = all_feats.select do |name, info|
            info.is_a?(Hash) && info['grants'].is_a?(Hash) &&
              Array(info['grants']['feat']).any? { |e| granted_name(e).to_s == name.to_s }
          end

          expect(selfish.keys).to eq []
        end
      end
    end
  end
end
