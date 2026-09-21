require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement
      describe Archetypes do

        def config
          ConfigView.fixture(
            'pf2e_feats' => {
              'Wizard Dedication' => { 'feat_type' => [ 'Dedication' ], 'assoc_archetype' => [ 'Wizard Archetype' ] },
              'Basic Arcana' => { 'feat_type' => [ 'Archetype' ], 'assoc_archetype' => [ 'Wizard Archetype' ] },
              'Toughness' => { 'feat_type' => [ 'General' ] }
            }
          )
        end

        def state(archetypes: {}, picked: {}, to_assign: {})
          CharState.build(
            {
              'archetypes' => archetypes,
              'advancement' => { 'feats' => picked },
              'to_assign' => to_assign
            },
            :config => config
          )
        end

        describe :clear do
          it "should clear the highest-numbered slot holding the value" do
            held = { 'archetype1' => 'Wizard Archetype', 'archetype2' => 'Wizard Archetype' }

            expect(Archetypes.clear(held, 'archetype', 'Wizard Archetype')).to eq('archetype1' => 'Wizard Archetype', 'archetype2' => "")
          end

          it "should leave the hash alone when nothing holds the value" do
            held = { 'archetype1' => 'Bard Archetype' }

            expect(Archetypes.clear(held, 'archetype', 'Wizard Archetype')).to eq held
          end

          it "should ignore a blank value rather than clearing an empty slot" do
            held = { 'archetype1' => "" }

            expect(Archetypes.clear(held, 'archetype', "")).to eq held
          end
        end

        describe :dedications do
          it "should find the archetype a dedication belongs to" do
            expect(Archetypes.dedications(state, [ 'Wizard Dedication' ])).to eq [ 'Wizard Archetype' ]
          end

          it "should ignore an archetype feat that is not a dedication" do
            expect(Archetypes.dedications(state, [ 'Basic Arcana' ])).to eq []
          end

          it "should ignore an ordinary feat" do
            expect(Archetypes.dedications(state, [ 'Toughness' ])).to eq []
          end

          it "should ignore a feat the game does not have" do
            expect(Archetypes.dedications(state, [ 'Nonsense Feat' ])).to eq []
          end
        end

        describe :undo_advancement do
          it "should give back a slot a dedication taken this level filled" do
            current = state(
              :archetypes => { 'archetype1' => 'Wizard Archetype' },
              :picked => { 'archetype' => [ 'Wizard Dedication' ] }
            )

            expect(Archetypes.undo_advancement(current)['archetype1']).to eq ""
          end

          it "should leave an archetype held from an earlier level alone" do
            current = state(
              :archetypes => { 'archetype1' => 'Bard Archetype', 'archetype2' => 'Wizard Archetype' },
              :picked => { 'archetype' => [ 'Wizard Dedication' ] }
            )

            result = Archetypes.undo_advancement(current)

            expect(result['archetype1']).to eq 'Bard Archetype'
            expect(result['archetype2']).to eq ""
          end

          it "should give back the specialty that came with it" do
            current = state(
              :archetypes => { 'archetype1' => 'Wizard Archetype', 'archetype_specialty1' => 'Battle Magic' },
              :picked => { 'archetype' => [ 'Wizard Dedication' ] },
              :to_assign => { 'archetype_specialty' => 'Battle Magic' }
            )

            expect(Archetypes.undo_advancement(current)['archetype_specialty1']).to eq ""
          end

          # The choice slot is keyed by which archetype sits at that index, so it has to be
          # found before the archetype slot itself is cleared.
          it "should give back the specialty choice of an archetype taken this level" do
            current = state(
              :archetypes => { 'archetype1' => 'Wizard Archetype', 'archetype_specialty_choice1' => 'Evocation' },
              :picked => { 'archetype' => [ 'Wizard Dedication' ] },
              :to_assign => { 'archetype specialty choice' => { 'Wizard Archetype' => {} } }
            )

            result = Archetypes.undo_advancement(current)

            expect(result['archetype_specialty_choice1']).to eq ""
            expect(result['archetype1']).to eq ""
          end

          it "should do nothing when no dedication was taken" do
            current = state(
              :archetypes => { 'archetype1' => 'Wizard Archetype' },
              :picked => { 'general' => [ 'Toughness' ] }
            )

            expect(Archetypes.undo_advancement(current)).to eq('archetype1' => 'Wizard Archetype')
          end

          it "should do nothing on an empty draft" do
            expect(Archetypes.undo_advancement(state(:archetypes => { 'archetype1' => 'Wizard Archetype' }))).to eq('archetype1' => 'Wizard Archetype')
          end
        end
      end

      describe Lifecycle do
        it "should throw the whole draft away" do
          current = CharState.build(
            {
              'to_assign' => { 'feats' => { 'general' => [ 'open' ] } },
              'advancement' => { 'raise skill' => [ 'Arcana' ] }
            },
            :config => ConfigView.fixture({})
          )

          result = Lifecycle.reset(current)

          expect(result.ok?).to be true
          expect(result.state['to_assign']).to eq({})
          expect(result.state['advancement']).to eq({})
        end

        it "should write no grants, because a draft never reached the ledger" do
          current = CharState.build({ 'advancement' => { 'raise skill' => [ 'Arcana' ] } }, :config => ConfigView.fixture({}))

          expect(Lifecycle.reset(current).grants).to be_empty
        end
      end
    end
  end
end
