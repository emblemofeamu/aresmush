require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement

      # Where a spell pick lands in the pool.
      #
      # Three shapes: a spellbook may be flat or per rank, a repertoire and a signature list are
      # always per rank, and a character casting from more than one source has all of them keyed by
      # source first. Which applies is the path, and the path is what this works out.
      describe SpellSlots do

        def state(pool)
          CharState.build({ 'to_assign' => pool }, :config => ConfigView.fixture({}))
        end

        def resolve(pool, type: 'repertoire', rank: '1', magic_class: nil, charclass: 'Bard')
          SpellSlots.resolve(state(pool), :type => type, :rank => rank,
                             :magic_class => magic_class, :charclass => charclass)
        end

        describe "a pool keyed by rank" do
          it "should find the entries at that rank" do
            result = resolve({ 'repertoire' => { '1' => [ 'open', 'open' ] } })

            expect(result.state['list']).to eq [ 'open', 'open' ]
            expect(result.state['list_key']).to eq '1'
            expect(result.state['class_key']).to be_nil
          end

          it "should refuse a rank the level did not open" do
            expect(resolve({ 'repertoire' => { '2' => [ 'open' ] } }).code).to eq :no_slots_at_rank
          end
        end

        describe "a flat spellbook list" do
          # A spellbook can be one list with no ranks, in which case the rank is not part of the path.
          it "should take the list as it is and leave the rank out of the path" do
            result = resolve({ 'spellbook' => %w(open open) }, :type => 'spellbook')

            expect(result.state['list']).to eq %w(open open)
            expect(result.state['list_key']).to be_nil
          end
        end

        describe "a pool keyed by source" do
          def two_sources
            { 'repertoire' => { 'Bard' => { '1' => [ 'open' ] }, 'Sorcerer Archetype' => { '1' => [ 'open', 'open' ] } } }
          end

          it "should take the source the player named" do
            result = resolve(two_sources, :magic_class => 'sorcerer archetype')

            expect(result.state['class_key']).to eq 'Sorcerer Archetype'
            expect(result.state['list']).to eq [ 'open', 'open' ]
          end

          it "should fall back to the character's own class" do
            expect(resolve(two_sources).state['class_key']).to eq 'Bard'
          end

          it "should refuse a source they do not have" do
            expect(resolve(two_sources, :magic_class => 'Wizard').code).to eq :not_an_option
          end

          # With one source and no prefix there is nothing to be ambiguous about.
          it "should take the only source there is" do
            pool = { 'repertoire' => { 'Sorcerer Archetype' => { '1' => [ 'open' ] } } }

            expect(resolve(pool).state['class_key']).to eq 'Sorcerer Archetype'
          end

          it "should refuse to guess between two sources that are not theirs" do
            pool = { 'repertoire' => { 'Wizard Archetype' => { '1' => [ 'open' ] },
                                       'Sorcerer Archetype' => { '1' => [ 'open' ] } } }

            expect(resolve(pool).code).to eq :not_an_option
          end
        end

        describe "a type the level did not open" do
          it "should say so" do
            expect(resolve({ 'spellbook' => { '1' => [ 'open' ] } }).code).to eq :not_an_option
          end

          # Typing your own class where a list type belongs is common enough to answer specifically.
          it "should name the mistake when the type is their class" do
            result = resolve({}, :type => 'bard', :charclass => 'Bard')

            expect(result.code).to eq :wrong_type
            expect(result.args['class']).to eq 'Bard'
          end
        end

        # A prepared caster's level often gives slots that are not tied to a rank: the pool is
        # keyed `any` and nothing else, and a pick at any rank spends one. Refusing because the rank
        # has no list of its own is what stalled every Wizard and Witch at level 2.
        describe "a pool that is only any-rank" do
          def any_only
            { 'spellbook' => { Pf2emagic::ANY_RANK => %w(open open) } }
          end

          it "should spend the any-rank slot for a pick at a rank" do
            result = resolve(any_only, :type => 'spellbook', :rank => '1')

            expect(result.ok?).to be true
            expect(result.state['list']).to eq %w(open open)
            expect(result.state['list_key']).to eq Pf2emagic::ANY_RANK
            expect(result.state['from_pool']).to be true
          end

          it "should refuse once the any-rank slots are spent" do
            pool = { 'spellbook' => { Pf2emagic::ANY_RANK => [ 'Magic Missile' ] } }

            expect(resolve(pool, :type => 'spellbook', :rank => '1').code).to eq :no_slots_at_rank
          end

          it "should still prefer the rank's own list when it has one" do
            pool = { 'spellbook' => { '1' => [ 'open' ], Pf2emagic::ANY_RANK => [ 'open' ] } }
            result = resolve(pool, :type => 'spellbook', :rank => '1')

            expect(result.state['list_key']).to eq '1'
            expect(result.state['from_pool']).to be false
          end
        end

        describe "an any-rank slot" do
          it "should be found when one is open" do
            entries = { '1' => [ 'Magic Missile' ], Pf2emagic::ANY_RANK => [ 'open' ] }

            expect(SpellSlots.any_rank_key(entries)).to eq Pf2emagic::ANY_RANK
          end

          it "should not be found when it is already spent" do
            entries = { Pf2emagic::ANY_RANK => [ 'Magic Missile' ] }

            expect(SpellSlots.any_rank_key(entries)).to be_nil
          end

          it "should not be found in a flat list" do
            expect(SpellSlots.any_rank_key([ 'open' ])).to be_nil
          end
        end

        # An open entry at a rank is not open to every spell. A Wizard's curriculum reserves one
        # entry per rank for a school spell, so a rank with one open entry left is full for a spell
        # that cannot sit in it, and open for one that can.
        describe "whether a rank's own entries can still take a spell" do
          def full?(picks, spell, reserved: 1, eligible: [ 'Fireball', 'Burning Hands' ])
            SpellSlots.rank_full?(picks, spell, reserved, eligible)
          end

          it "should be full when nothing is open" do
            expect(full?([ 'Magic Missile', 'Fireball' ], 'Shield')).to be true
          end

          it "should be open when the rank reserves nothing" do
            expect(full?([ 'open' ], 'Shield', :reserved => 0, :eligible => [])).to be false
          end

          it "should be full for a spell that cannot sit in the one reserved entry" do
            expect(full?([ 'Magic Missile', 'open' ], 'Shield')).to be true
          end

          it "should be open for a spell that can sit in the reserved entry" do
            expect(full?([ 'Magic Missile', 'open' ], 'Fireball')).to be false
          end

          # The reservation is already satisfied, so the open entry is nobody's in particular.
          it "should be open when an eligible spell is already held" do
            expect(full?([ 'Burning Hands', 'open' ], 'Shield')).to be false
          end

          it "should be full when two entries are reserved and only one is spoken for" do
            expect(full?([ 'Burning Hands', 'open' ], 'Shield', :reserved => 2)).to be true
          end
        end

        describe "falling back to an any-rank slot" do
          def found(entries, from_pool: false)
            { 'class_key' => nil, 'entries' => entries, 'list' => entries['1'],
              'list_key' => '1', 'from_pool' => from_pool }
          end

          def pool
            { '1' => [ 'Magic Missile' ], Pf2emagic::ANY_RANK => [ 'open' ] }
          end

          it "should leave a rank that is not full alone" do
            result = SpellSlots.spend_from_pool(found(pool), :full => false, :rank => '1', :max_rank => 3)

            expect(result.state['list_key']).to eq '1'
            expect(result.state['from_pool']).to be false
          end

          it "should move the pick onto the any-rank slot when the rank is full" do
            result = SpellSlots.spend_from_pool(found(pool), :full => true, :rank => '1', :max_rank => 3)

            expect(result.state['list_key']).to eq Pf2emagic::ANY_RANK
            expect(result.state['list']).to eq [ 'open' ]
            expect(result.state['from_pool']).to be true
          end

          # Nothing left to fall back to, so the answer stays the rank's own list and the caller
          # finds it has no open entry.
          it "should leave the resolution alone when the any-rank slot is spent" do
            entries = { '1' => [ 'Magic Missile' ], Pf2emagic::ANY_RANK => [ 'Shield' ] }
            result = SpellSlots.spend_from_pool(found(entries), :full => true, :rank => '1', :max_rank => 3)

            expect(result.state['list_key']).to eq '1'
            expect(result.state['from_pool']).to be false
          end

          it "should not spend a slot on a cantrip, which no slot casts" do
            expect(SpellSlots.spend_from_pool(found(pool), :full => true, :rank => 'cantrip', :max_rank => 3).code)
              .to eq :any_rank_cantrip
          end

          it "should not reach past the rank the character can cast" do
            result = SpellSlots.spend_from_pool(found(pool), :full => true, :rank => '5', :max_rank => 3)

            expect(result.code).to eq :any_rank_no_slots
            expect(result.args['level']).to eq '5th-rank'
          end

          it "should not spend a second slot for one pick" do
            result = SpellSlots.spend_from_pool(found(pool, :from_pool => true), :full => true, :rank => '1', :max_rank => 3)

            expect(result.state['list_key']).to eq '1'
          end
        end

        describe "which entry a pick fills" do
          it "should take the first open one" do
            result = SpellSlots.entry_to_fill([ 'Magic Missile', 'open' ], nil, 'repertoire')

            expect(result.state['token']).to eq 'open'
          end

          it "should take the spell being replaced when nothing is open" do
            result = SpellSlots.entry_to_fill([ 'Magic Missile', 'Shield' ], 'magic missile', 'repertoire')

            expect(result.state['token']).to eq 'Magic Missile'
          end

          it "should refuse when nothing is open and nothing was named to replace" do
            result = SpellSlots.entry_to_fill([ 'Magic Missile' ], nil, 'repertoire')

            expect(result.code).to eq :no_free
            expect(result.args['element']).to eq 'repertoire slot'
          end

          it "should refuse to replace a spell the list does not hold" do
            result = SpellSlots.entry_to_fill([ 'Magic Missile' ], 'Shield', 'repertoire')

            expect(result.code).to eq :not_in_list
            expect(result.args['option']).to eq 'Shield'
          end

          # A name the player typed is a name, not a pattern: a spell with a bracket in it used to
          # reach Regexp and raise.
          it "should match a name holding a regular expression character" do
            result = SpellSlots.entry_to_fill([ 'Summon Elemental (Fire)' ], 'elemental (fire)', 'repertoire')

            expect(result.state['token']).to eq 'Summon Elemental (Fire)'
          end
        end
      end
    end
  end
end
