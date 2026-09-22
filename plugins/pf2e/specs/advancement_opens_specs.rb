require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement

      # What a level offers.
      #
      # One row per key of a class table's level block, which makes this the readable half of the
      # pair: Opens turns the table into a draft, Apply turns the finished draft into the sheet.
      describe Opens do

        def opened(info, char = double(:pf2_level => 4))
          pool, draft, messages = Opens.all(char, info)

          { :pool => pool, :draft => draft, :messages => messages }
        end

        describe "feat slots" do
          it "should open one pool keyed by slot type" do
            result = opened('choose_feat' => [ 'charclass', 'skill' ])

            expect(result[:pool]['feats']).to eq('charclass' => [ 'open' ], 'skill' => [ 'open' ])
          end

          it "should say what is open" do
            expect(opened('choose_feat' => [ 'skill' ])[:messages]).to eq [ [ 'pf2e.adv_item_feat', { :value => 'skill' } ] ]
          end
        end

        describe "increases" do
          it "should open one slot for a skill increase" do
            expect(opened('raise' => [ 'skill' ])[:pool]['raise skill']).to eq [ 'open' ]
          end

          # PF2e gives four attribute boosts at once, at 5th, 10th, 15th and 20th.
          it "should open four for attributes" do
            expect(opened('raise' => [ 'ability' ])[:pool]['raise ability']).to eq %w(open open open open)
          end
        end

        describe "a class feature with options" do
          it "should open the choice with its options listed" do
            result = opened('charclass_choice' => { 'choice_name' => 'Path to Perfection',
                                                    'options' => [ 'fortitude', 'reflex' ] })

            expect(result[:pool]['class option']).to eq('Path to Perfection' => [ 'fortitude', 'reflex' ])
            expect(result[:messages].first[1][:options]).to eq 'fortitude, reflex'
          end

          it "should keep options that carry what they grant" do
            options = { 'Sword' => { 'combat_stats' => {} } }
            result = opened('choose' => { 'choice_name' => 'Weapon Legend', 'options' => options })

            expect(result[:pool]['class option']).to eq('Weapon Legend' => options)
          end
        end

        # A choice a feat or feature carries is read off the whole level block at once, so a level
        # naming both keys does not open every slot twice.
        it "should leave the choice keys to the one pass that reads them together" do
          result = opened('feat_choice' => [ 'Stylish Tricks' ], 'grant_choice' => [ 'Stylish Tricks' ])

          expect(result[:pool]).to eq({})
          expect(result[:draft]).to eq({})
        end

        # This is what carries a tradition raise, an action, a reaction and a class feature through
        # to Apply, which writes them when the level commits.
        it "should give the draft a key it does not open itself" do
          result = opened('charclass_feature' => [ 'Expert Spellcaster' ], 'tradition' => { 'occult' => 'expert' })

          expect(result[:draft]).to eq('charclass_feature' => [ 'Expert Spellcaster' ],
                                       'tradition' => { 'occult' => 'expert' })
        end

        # The two tables are the two halves of a level. Anything this hands to the draft has to be
        # something Apply writes, or the level would offer what nothing applies.
        it "should hand the draft only keys Apply knows" do
          handled_here = Opens.keys

          keys = [ 'pf2e_class', 'pf2e_archetype', 'pf2e_specialty' ].flat_map do |section|
            level_block_keys(Global.read_config(section))
          end.uniq - handled_here

          expect(keys - Apply.keys).to eq []
        end

        def level_block_keys(node)
          return [] unless node.is_a?(Hash)

          node.flat_map do |key, value|
            own = key.to_s.match?(/\A\d+\z/) && value.is_a?(Hash) ? value.keys.map(&:to_s) : []

            own + level_block_keys(value)
          end
        end
      end
    end
  end
end
