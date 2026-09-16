require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement
      describe Plan do

        def config(extra = {})
          ConfigView.fixture({
            'pf2e' => { 'max_level' => 20 },
            'pf2e_class' => {
              'Wizard' => { 'advance' => { 7 => { 'choose_feat' => [ 'general' ], 'raise' => [ 'skill' ] } } }
            },
            'pf2e_specialty' => {
              'Wizard' => { 'School of Battle Magic' => { 'advance' => { 7 => { 'charclass_feature' => [ 'Battle Magic' ] } } } }
            }
          }.merge(extra))
        end

        def state(level: 6, xp: 5000, advancing: false, charclass: 'Wizard', specialize: '', cfg: nil)
          CharState.build(
            {
              'level' => level,
              'xp' => xp,
              'advancing' => advancing,
              'base_info' => { 'charclass' => charclass, 'specialize' => specialize }
            },
            :config => cfg || config
          )
        end

        describe :can_advance do
          it "should allow an eligible character" do
            expect(Plan.can_advance(state)).to be_nil
          end

          it "should refuse one already advancing" do
            expect(Plan.can_advance(state(:advancing => true)).key).to eq 'pf2e.already_advancing'
          end

          it "should refuse one short of the xp" do
            expect(Plan.can_advance(state(:xp => 999)).key).to eq 'pf2e.not_enough_xp'
          end

          it "should refuse one in an active encounter" do
            expect(Plan.can_advance(state, 'in_encounter' => true).key).to eq 'pf2e.already_in_encounter'
          end

          it "should refuse one already at the ceiling" do
            expect(Plan.can_advance(state(:level => 20)).key).to eq 'pf2e.already_max_level'
          end

          # Checked in order, so the most specific complaint wins.
          it "should complain about advancing before anything else" do
            expect(Plan.can_advance(state(:advancing => true, :xp => 0), 'in_encounter' => true).key).to eq 'pf2e.already_advancing'
          end
        end

        describe :for_level do
          it "should return the class entry when there is no specialty" do
            expect(Plan.for_level(state, 7)).to eq('choose_feat' => [ 'general' ], 'raise' => [ 'skill' ])
          end

          it "should merge the specialty entry over the class one" do
            plan = Plan.for_level(state(:specialize => 'School of Battle Magic'), 7)

            expect(plan['choose_feat']).to eq [ 'general' ]
            expect(plan['charclass_feature']).to eq [ 'Battle Magic' ]
          end

          it "should return nothing for a level the table does not describe" do
            expect(Plan.for_level(state, 8)).to be_nil
          end

          it "should return nothing when no class is set" do
            expect(Plan.for_level(state(:charclass => ''), 7)).to be_nil
          end
        end

        # A specialty adds to what the class gives rather than replacing it, or a subclass
        # would silently take away feats the class table promised.
        describe :merge do
          it "should combine lists instead of replacing them" do
            expect(Plan.merge({ 'raise' => [ 'skill' ] }, { 'raise' => [ 'ability' ] })).to eq('raise' => [ 'skill', 'ability' ])
          end

          it "should not repeat an entry both sides give" do
            expect(Plan.merge({ 'raise' => [ 'skill' ] }, { 'raise' => [ 'skill' ] })).to eq('raise' => [ 'skill' ])
          end

          it "should recurse into nested hashes" do
            merged = Plan.merge({ 'magic_stats' => { 'focus_pool' => 1 } }, { 'magic_stats' => { 'tradition' => 'arcane' } })

            expect(merged['magic_stats']).to eq('focus_pool' => 1, 'tradition' => 'arcane')
          end

          it "should let the specialty win on a plain value" do
            expect(Plan.merge({ 'hp' => 6 }, { 'hp' => 8 })).to eq('hp' => 8)
          end

          it "should cope with either side being absent" do
            expect(Plan.merge(nil, { 'hp' => 8 })).to eq('hp' => 8)
            expect(Plan.merge({ 'hp' => 6 }, nil)).to eq('hp' => 6)
          end
        end
      end
    end
  end
end
