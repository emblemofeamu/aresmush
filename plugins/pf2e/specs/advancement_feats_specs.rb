require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement

      describe Feats do

        def state(feats)
          CharState.build({ 'to_assign' => { 'feats' => feats } }, :config => ConfigView.fixture({}))
        end

        def skill_feat
          { 'feat_type' => [ 'Skill' ] }
        end

        describe :check_slot do
          it "should accept a feat of the right type in an open slot" do
            expect(Feats.check_slot(state('skill' => [ 'open' ]), 'skill', 'assurance', skill_feat)).to be_nil
          end

          # "class" is what a player types; the slot is called "charclass". Saying so is more use
          # than "not an option".
          it "should tell a player who typed class to use charclass" do
            result = Feats.check_slot(state('charclass' => [ 'open' ]), 'class', 'power attack', { 'feat_type' => [ 'Charclass' ] })

            expect(result.code).to eq :use_charclass
            expect(result.args['feat']).to eq 'power attack'
          end

          it "should refuse a type this level did not grant" do
            expect(Feats.check_slot(state('skill' => [ 'open' ]), 'general', 'toughness', { 'feat_type' => [ 'General' ] }).code).to eq :not_an_option
          end

          it "should refuse when every slot of that type is spent" do
            result = Feats.check_slot(state('skill' => [ 'Assurance' ]), 'skill', 'intimidating glare', skill_feat)

            expect(result.code).to eq :no_free
            expect(result.args['element']).to eq 'skill feat'
          end

          it "should refuse a feat of the wrong type for the slot" do
            result = Feats.check_slot(state('skill' => [ 'open' ]), 'skill', 'toughness', { 'feat_type' => [ 'General' ] })

            expect(result.code).to eq :bad_feat_type
            expect(result.args['keys']).to eq 'general'
          end

          # The order is deliberate: the most specific complaint should win.
          it "should complain about class before anything else" do
            expect(Feats.check_slot(state({}), 'class', 'x', {}).code).to eq :use_charclass
          end
        end

        describe :spend_slot do
          it "should put the feat in the first open slot and leave the rest" do
            result = Feats.spend_slot(state('skill' => [ 'Assurance', 'open', 'open' ]), 'skill', 'Intimidating Glare')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['feats']['skill']).to eq [ 'Assurance', 'Intimidating Glare', 'open' ]
          end

          it "should not touch the other buckets" do
            result = Feats.spend_slot(state('skill' => [ 'open' ], 'general' => [ 'open' ]), 'skill', 'Assurance')

            expect(result.state['to_assign']['feats']['general']).to eq [ 'open' ]
          end

          it "should refuse when nothing is open" do
            expect(Feats.spend_slot(state('skill' => [ 'Assurance' ]), 'skill', 'X').code).to eq :no_free
          end
        end
      end

      describe Onboarding do
        describe :claim_slot do
          it "should take the first free slot" do
            held = { 'archetype1' => 'Bard Archetype', 'archetype2' => "", 'archetype3' => "" }

            expect(Onboarding.claim_slot(held, 'Wizard Archetype')['archetype2']).to eq 'Wizard Archetype'
          end

          it "should take the first slot on a character with no archetypes at all" do
            expect(Onboarding.claim_slot({}, 'Wizard Archetype')['archetype1']).to eq 'Wizard Archetype'
          end

          it "should leave a full set alone rather than overwriting one" do
            full = (1..4).each_with_object({}) { |i, h| h["archetype#{i}"] = "Held #{i}" }

            expect(Onboarding.claim_slot(full, 'Wizard Archetype')).to eq full
          end
        end

        describe :names do
          it "should trim, drop blanks and de-duplicate" do
            expect(Onboarding.names([ ' Arcana ', 'Arcana', "", nil, 'Stealth' ])).to eq [ 'Arcana', 'Stealth' ]
          end

          it "should cope with a single value rather than a list" do
            expect(Onboarding.names('Arcana')).to eq [ 'Arcana' ]
          end
        end
      end
    end
  end
end
