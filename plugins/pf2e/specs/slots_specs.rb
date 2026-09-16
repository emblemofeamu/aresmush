require "plugin_test_loader"

module AresMUSH
  module Pf2e
    describe Slots do

      describe :apply do
        it "should return the pool unchanged for no deltas" do
          expect(Slots.apply({ 'open languages' => [ 'open' ] }, [])).to eq('open languages' => [ 'open' ])
        end

        it "should not mutate the pool it was given" do
          pool = { 'open languages' => [ 'open' ] }
          Slots.apply(pool, [ Slots.fill('open languages', 'Kamin') ])

          expect(pool).to eq('open languages' => [ 'open' ])
        end
      end

      describe 'open' do
        it "should add a pickable marker" do
          result = Slots.apply({}, [ Slots.open('open languages') ])

          expect(result['open languages']).to eq [ 'open' ]
        end

        it "should add several at once" do
          result = Slots.apply({}, [ Slots.open('open languages', :count => 3) ])

          expect(result['open languages']).to eq %w(open open open)
        end

        it "should keep what is already there" do
          result = Slots.apply({ 'open languages' => [ 'Kamin' ] }, [ Slots.open('open languages') ])

          expect(result['open languages']).to eq [ 'Kamin', 'open' ]
        end

        # A skill slot can be restricted to a lore, or to something the character is untrained
        # in. The marker carries that, which is how Raises knows what may spend it.
        it "should add a restricted marker when one is named" do
          result = Slots.apply({}, [ Slots.open('raise skill', :token => 'open untrained') ])

          expect(result['raise skill']).to eq [ 'open untrained' ]
        end

        it "should open a nested slot addressed by path" do
          result = Slots.apply({}, [ Slots.open([ 'feats', 'skill' ]) ])

          expect(result['feats']).to eq('skill' => [ 'open' ])
        end

        it "should open a nested slot without disturbing its siblings" do
          pool = { 'feats' => { 'general' => [ 'Toughness' ] } }
          result = Slots.apply(pool, [ Slots.open([ 'feats', 'skill' ]) ])

          expect(result['feats']['general']).to eq [ 'Toughness' ]
          expect(result['feats']['skill']).to eq [ 'open' ]
        end
      end

      describe 'fill' do
        it "should spend the first open marker" do
          result = Slots.apply({ 'feats' => { 'skill' => [ 'Assurance', 'open', 'open' ] } },
            [ Slots.fill([ 'feats', 'skill' ], 'Intimidating Glare') ])

          expect(result['feats']['skill']).to eq [ 'Assurance', 'Intimidating Glare', 'open' ]
        end

        it "should refuse when nothing is open" do
          result = Slots.apply({ 'feats' => { 'skill' => [ 'Assurance' ] } },
            [ Slots.fill([ 'feats', 'skill' ], 'X') ])

          expect(result).to be_a Err
          expect(result.code).to eq :no_free
        end

        it "should refuse when the slot does not exist at all" do
          expect(Slots.apply({}, [ Slots.fill('open languages', 'Kamin') ]).code).to eq :no_free
        end

        # A restricted marker is only spendable by something allowed to spend it, and the
        # caller says which markers those are - so the rule lives with the pick, not here.
        it "should prefer the markers the caller listed, in the order listed" do
          pool = { 'raise skill' => [ 'open', 'open lore' ] }
          result = Slots.apply(pool, [ Slots.fill('raise skill', 'Khazadi Lore', :tokens => [ 'open lore', 'open' ]) ])

          expect(result['raise skill']).to eq [ 'open', 'Khazadi Lore' ]
        end

        it "should refuse when none of the allowed markers is open" do
          pool = { 'raise skill' => [ 'open lore' ] }
          result = Slots.apply(pool, [ Slots.fill('raise skill', 'Arcana', :tokens => [ 'open' ]) ])

          expect(result.code).to eq :no_free
        end
      end

      describe 'release' do
        it "should hand a filled slot back" do
          result = Slots.apply({ 'open languages' => [ 'Kamin', 'open' ] }, [ Slots.release('open languages', 'Kamin') ])

          expect(result['open languages']).to eq [ 'open', 'open' ]
        end

        it "should refuse to release something that is not there" do
          expect(Slots.apply({ 'open languages' => [ 'open' ] }, [ Slots.release('open languages', 'Kamin') ]).code).to eq :not_in_list
        end
      end

      describe 'set and add' do
        it "should set a scalar slot" do
          expect(Slots.apply({}, [ Slots.set('archetype', 'Bard Archetype') ])['archetype']).to eq 'Bard Archetype'
        end

        # Values that were never pickable - already decided, just recorded.
        it "should add decided values to a list" do
          result = Slots.apply({ 'raise skill choice' => [ 'Arcana' ] },
            [ Slots.add('raise skill choice', [ 'Stealth', 'Arcana' ]) ])

          expect(result['raise skill choice']).to eq [ 'Arcana', 'Stealth' ]
        end
      end

      describe "a sequence" do
        # The thing this exists for: what a feat does to the pool is a list, and taking the
        # feat and what it opens up are the same kind of step.
        it "should apply deltas in order, so a slot opened can be filled by a later one" do
          deltas = [
            Slots.open([ 'feats', 'skill' ], :count => 2),
            Slots.fill([ 'feats', 'skill' ], 'Assurance'),
            Slots.open('open languages', :count => 2)
          ]

          result = Slots.apply({}, deltas)

          expect(result['feats']['skill']).to eq [ 'Assurance', 'open' ]
          expect(result['open languages']).to eq %w(open open)
        end

        it "should stop at the first failure and say which delta failed" do
          deltas = [ Slots.fill('open languages', 'Kamin'), Slots.open('raise skill') ]
          result = Slots.apply({}, deltas)

          expect(result).to be_a Err
          expect(result.args['element']).to eq 'open languages'
        end
      end

      describe :openings do
        # "What did that open up?" - the question the old code could not answer, because
        # opening a slot was an inline array append at each call site.
        it "should describe what a list of deltas opens" do
          deltas = [
            Slots.open([ 'feats', 'skill' ], :count => 2),
            Slots.fill([ 'feats', 'skill' ], 'Assurance'),
            Slots.open('open languages')
          ]

          expect(Slots.openings(deltas)).to eq('feats/skill' => 2, 'open languages' => 1)
        end

        it "should report nothing for deltas that only spend" do
          expect(Slots.openings([ Slots.fill('open languages', 'Kamin') ])).to eq({})
        end
      end
    end
  end
end
