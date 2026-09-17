require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The vocabulary of the draft: which keys exist, which hash each belongs to, and what it holds.
    #
    # The keys were free-form strings invented wherever one was needed, which produced 25 spellings
    # including `feat choice` alongside `feat_choices` for two different things. A registry gives them
    # one definition, and `Slots.apply` refuses a key that is not in it, so a new spelling fails the
    # first time it is written rather than joining the list.
    describe DraftKeys do

      describe :registered? do
        it "should know a key the draft uses" do
          expect(DraftKeys.registered?('open languages')).to be true
          expect(DraftKeys.registered?('feats')).to be true
        end

        it "should not know an invented one" do
          expect(DraftKeys.registered?('open langauges')).to be false
        end

        it "should match however it was capitalised" do
          expect(DraftKeys.registered?('Open Languages')).to be true
        end
      end

      describe :holder do
        # A space means the key lives in to_assign and an underscore means it lives in advancement.
        # Four keys break that and the registry is where a reader finds out which.
        it "should say which hash a key belongs to" do
          expect(DraftKeys.holder('open languages')).to eq 'to_assign'
          expect(DraftKeys.holder('magic_stats')).to eq 'advancement'
        end

        it "should say so for a key that breaks the naming convention" do
          expect(DraftKeys.holder('raise skill')).to eq 'advancement'
          expect(DraftKeys.holder('bg_lore')).to eq 'to_assign'
        end

        it "should say when a key is written to both" do
          expect(DraftKeys.holder('archetype deity')).to eq 'to_assign'
          expect(DraftKeys.holder('archetype_deity')).to eq 'advancement'
        end
      end

      # The registry is only as good as the promise that nothing outside it is in use, and the write
      # boundary is where that is kept.
      describe "the write boundary" do
        it "should apply a delta on a registered key" do
          pool = Slots.apply({}, [ Slots.open('open languages', :count => 2) ])

          expect(pool['open languages']).to eq [ 'open', 'open' ]
        end

        it "should refuse a delta on a key the registry does not know" do
          outcome = Slots.apply({}, [ Slots.open('open langauges', :count => 1) ])

          expect(outcome).to be_err
          expect(outcome.code).to eq :unknown_slot_key
        end

        it "should name the key it refused" do
          outcome = Slots.apply({}, [ Slots.open('invented thing') ])

          expect(outcome.args['key']).to eq 'invented thing'
        end

        it "should leave the pool alone when it refuses" do
          pool = { 'open languages' => [ 'open' ] }
          Slots.apply(pool, [ Slots.open('invented thing') ])

          expect(pool).to eq('open languages' => [ 'open' ])
        end

        it "should check only the root of a nested path" do
          pool = Slots.apply({}, [ Slots.open([ 'feats', 'skill' ], :count => 1) ])

          expect(pool['feats']['skill']).to eq [ 'open' ]
        end
      end

      describe "the registry itself" do
        it "should give every key a holder" do
          missing = DraftKeys.all.reject { |key| %w(to_assign advancement both scratch).include?(DraftKeys.holder(key)) }

          expect(missing).to eq []
        end

        it "should describe what every key holds" do
          undescribed = DraftKeys.all.reject { |key| DraftKeys.describe(key).to_s.length > 3 }

          expect(undescribed).to eq []
        end
      end
    end
  end
end
