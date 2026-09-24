require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # The spells a player may pick by name in chargen and at a level-up. A spell with any rarity
    # trait is left out, except where the class has access to it on its own terms. Granted spells
    # reach the sheet without passing through these lists at all.
    describe "picking a spell by name" do

      let(:spells) do
        {
          'Fireball' => { 'traits' => [ 'concentrate', 'fire' ] },
          'Talking Corpse' => { 'traits' => [ 'concentrate', 'uncommon' ] },
          'Detonate Magic' => { 'traits' => [ 'concentrate', 'uncommon' ] },
          'Wish' => { 'traits' => [ 'rare' ] },
          'Unique Thing' => { 'traits' => [ 'unique' ] },
          'Traitless' => {}
        }
      end

      before(:each) do
        allow(Global).to receive(:read_config).with('pf2e_spells').and_return(spells)
      end

      describe "Pf2emagic.find_common_spells" do
        it "should keep a spell with no rarity trait" do
          expect(Pf2emagic.find_common_spells.keys).to include 'Fireball'
        end

        it "should leave out uncommon, rare and unique spells" do
          expect(Pf2emagic.find_common_spells.keys).to_not include('Talking Corpse', 'Wish', 'Unique Thing')
        end

        it "should treat a spell with no traits as common" do
          expect(Pf2emagic.find_common_spells.keys).to include 'Traitless'
        end
      end

      # A Wizard's school teaches its curriculum, uncommon spells included, so those are the
      # Wizard's to pick at their rank whatever their rarity.
      describe "Pf2emagic.pickable_spells" do

        def wizard(school)
          double(:pf2_base_info => { 'charclass' => 'Wizard', 'specialize' => school })
        end

        def pickable(school, rank)
          Pf2emagic.pickable_spells(wizard(school), 'Wizard', rank).keys
        end

        before(:each) do
          allow(Global).to receive(:read_config).with('pf2e_specialty', 'Wizard', 'Department of Mana Syntaxia')
            .and_return('curriculum' => { 9 => [ 'Detonate Magic' ] })
          allow(Global).to receive(:read_config).with('pf2e_specialty', 'Wizard', 'Department of Urban Thaumaturgy')
            .and_return('curriculum' => { 9 => [ 'Fireball' ] })
        end

        it "should offer an uncommon spell from the school's curriculum at that rank" do
          expect(pickable('Department of Mana Syntaxia', '9')).to include 'Detonate Magic'
        end

        it "should not offer it to a Wizard of another school" do
          expect(pickable('Department of Urban Thaumaturgy', '9')).to_not include 'Detonate Magic'
        end

        it "should not offer it at a rank the curriculum does not list it at" do
          expect(pickable('Department of Mana Syntaxia', '8')).to_not include 'Detonate Magic'
        end

        it "should still leave out other uncommon spells" do
          expect(pickable('Department of Mana Syntaxia', '9')).to_not include 'Talking Corpse'
        end

        it "should offer every common spell" do
          expect(pickable('Department of Mana Syntaxia', '9')).to include('Fireball', 'Traitless')
        end
      end
    end
  end
end
