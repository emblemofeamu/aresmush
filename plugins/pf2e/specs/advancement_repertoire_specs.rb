require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement
      describe Repertoire do

        def held
          [ 'Bless', 'Heal', 'Shield' ]
        end

        describe :swap do
          it "should put the new spell where the old one was" do
            expect(Repertoire.swap(held, 'Heal', 'Bane')).to eq [ 'Bless', 'Bane', 'Shield' ]
          end

          it "should match the spells however they were capitalised" do
            expect(Repertoire.swap(held, 'heal', 'Bane')).to eq [ 'Bless', 'Bane', 'Shield' ]
          end

          it "should refuse a second swap in one advancement" do
            expect(Repertoire.swap(held, 'Heal', 'Bane', :already_swapped => true).code).to eq :swap_limit
          end

          it "should refuse to trade a spell they do not know" do
            expect(Repertoire.swap(held, 'Fireball', 'Bane').code).to eq :not_in_list
          end

          # A spell a specialty put in the repertoire is not the player's to choose, so it is not
          # theirs to give up.
          it "should refuse to trade away a granted spell" do
            expect(Repertoire.swap(held, 'Heal', 'Bane', :locked => [ 'Heal' ]).code).to eq :locked
          end

          it "should refuse a swap that changes nothing" do
            expect(Repertoire.swap(held, 'Heal', 'heal').code).to eq :same_spell
          end

          it "should refuse a new spell they already know" do
            expect(Repertoire.swap(held, 'Heal', 'Bless').code).to eq :already_has
          end

          # In order, so the most relevant complaint wins.
          it "should complain about the limit before anything else" do
            expect(Repertoire.swap(held, 'Fireball', 'Fireball', :already_swapped => true).code).to eq :swap_limit
          end
        end

        describe :granted do
          it "should collect what chargen put in the repertoire" do
            info = { 'chargen' => { 'magic_stats' => { 'addrepertoire' => { '1' => [ 'Heal' ] } } } }

            expect(Repertoire.granted(info, 5)).to eq [ 'Heal' ]
          end

          it "should collect what levels already reached put there" do
            info = {
              'chargen' => { 'magic_stats' => { 'addrepertoire' => { '1' => [ 'Heal' ] } } },
              'advance' => {
                3 => { 'magic_stats' => { 'addrepertoire' => { '2' => [ 'Bless' ] } } },
                9 => { 'magic_stats' => { 'addrepertoire' => { '5' => [ 'Flame Strike' ] } } }
              }
            }

            expect(Repertoire.granted(info, 5)).to eq [ 'Heal', 'Bless' ]
          end

          it "should return nothing for a specialty that grants none" do
            expect(Repertoire.granted({ 'advance' => { 3 => {} } }, 5)).to eq []
          end

          it "should cope with no specialty at all" do
            expect(Repertoire.granted(nil, 5)).to eq []
          end
        end
      end
    end
  end
end
