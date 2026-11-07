require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Untamed Form: the druid names a shape on their list as they cast it, and takes that shape for as long
    # as the spell gives it.
    describe "casting untamed form", :dbtest => true do
      include FightBench

      UNTAMED = 'Spell Effect: Untamed Form'.freeze
      BEAR = 'Spell Effect: Animal Form (Bear)'.freeze

      before(:each) do
        bench!(level: 10)
        add('goblin warrior')
        turn_to(@hero.name)
        @spent = 0
        allow_any_instance_of(PF2EncounterCastCmd).to receive(:spend_the_spell) do
          @spent += 1
          { 'spell name' => 'Untamed Form', 'spell level' => Pf2emagic.get_auto_heighten_level(hero).to_s,
            'tradition' => 'primal' }
        end
      end

      after(:each) { clear_bench! }

      def feats(*names)
        @hero.update(:pf2_feats => { 'charclass' => [ 'Untamed Form' ] + names })
      end

      def casts(words)
        hero_types("e/cast untamed form/focus/#{words}")
      end

      def under
        ActiveEffects.on(hero).map(&:name)
      end

      def goblin_number
        Combatants.all(encounter).find { |one| one.label != @hero.name }.number
      end

      def row_of(name)
        ActiveEffects.on(hero).find { |one| one.name == name }
      end

      def shapes(rank = 5, *names)
        feats(*names)
        UntamedForm.available(hero, rank).map { |one| one['label'] }
      end

      describe "the shapes a druid can take" do
        it "should begin with the pests" do
          expect(shapes(1)).to eq [ 'Pest Form' ]
        end

        it "should add the animals from 2nd rank" do
          expect(shapes(2)).to include 'Pest Form', 'Bear', 'Shark'
        end

        it "should add what a feat adds, once the rank reaches it" do
          expect(shapes(5, 'Insect Shape')).to include 'Ant', 'Spider'
          expect(shapes(2, 'Insect Shape')).to_not include 'Ant'
        end

        it "should not offer what no feat gives them" do
          expect(shapes(10)).to_not include 'Ant', 'Forest Dragon', 'Air', 'Tyrannosaurus'
        end

        it "should give a shape behind two feats only to one with both" do
          expect(shapes(5, 'Soaring Shape')).to include 'Bat', 'Bird'
          expect(shapes(5, 'Soaring Shape')).to_not include 'Wasp', 'Pterosaur'
          expect(shapes(5, 'Soaring Shape', 'Insect Shape')).to include 'Wasp'
          expect(shapes(5, 'Soaring Shape', 'Ferocious Shape')).to include 'Pterosaur'
        end

        it "should give Monstrosity Shape the phoenix only with Soaring Shape" do
          expect(shapes(8, 'Monstrosity Shape')).to include 'Cave Worm', 'Sea Serpent'
          expect(shapes(8, 'Monstrosity Shape')).to_not include 'Phoenix'
          expect(shapes(8, 'Monstrosity Shape', 'Soaring Shape')).to include 'Phoenix'
        end

        it "should name only real effects in its table" do
          UntamedForm.table.each do |row|
            expect(ActiveEffects.catalogue.keys.any? { |one| one.start_with?("Spell Effect: #{row['spell']}") })
              .to be(true), row['spell']
          end
        end
      end

      describe "choosing as it is cast" do
        before(:each) { feats }

        it "should refuse a cast with no shape, spending nothing, and say what they can take" do
          casts('')

          expect(refused.join).to include 'Pest Form', 'Bear'
          expect(@spent).to eq 0
          expect(under).to eq []
        end

        it "should refuse a shape they don't have, spending nothing" do
          casts('tyrannosaurus')

          expect(refused.join).to include 'tyrannosaurus'
          expect(@spent).to eq 0
        end

        it "should refuse a word that could be several shapes, spending nothing" do
          @hero.update(:pf2_level => 16)
          feats('Monstrosity Shape', 'Dragon Shape')
          casts('dragon/poison')

          expect(refused.join).to include 'Forest Dragon', 'Terra Dragon'
          expect(@spent).to eq 0
        end

        it "should refuse someone else as the target" do
          hero_types("e/cast untamed form=#{goblin_number}/focus/bear")

          expect(refused.join).to include 'caster'
          expect(@spent).to eq 0
        end

        it "should take themselves as the target" do
          hero_types("e/cast untamed form=#{@hero.name}/focus/bear")

          expect(refused).to eq []
          expect(under).to include BEAR
        end

        def goblin_number
          Combatants.all(encounter).find { |one| one.label != @hero.name }.number
        end
      end

      describe "taking the shape" do
        before(:each) { feats('Insect Shape', 'Elemental Shape') }

        it "should put them in the form, at the spell's rank, with what the spell gives" do
          casts('bear')

          expect(refused).to eq []
          expect(@spent).to eq 1
          expect(under).to include UNTAMED, BEAR
          expect(row_of(BEAR).level).to eq 5
          expect(BattleForms.active(hero)['effect'].name).to eq BEAR
          expect(heard).to include 'Bear'
        end

        it "should take a shape picked by an answer" do
          casts('beetle')

          expect(Stat.total(hero, 'speed', 'land')).to eq 25
        end

        it "should give the feat's bonus for being in another form" do
          casts('bear')

          expect(IWR.of(hero)['resistance'].map { |one| one['type'] }).to include 'fire'
        end

        it "should give a pest ten minutes and anything else one" do
          casts('pest')
          expect([ row_of(UNTAMED).unit, row_of(UNTAMED).duration ]).to eq [ 'minutes', 10 ]

          ActiveEffects.remove_named(hero, UNTAMED)
          casts('bear')
          expect([ row_of(UNTAMED).unit, row_of(UNTAMED).duration ]).to eq [ 'minutes', 1 ]
        end

        # Nobody casts in a battle form, so a druid in a shape ends it first.
        it "should refuse to be cast again until they dismiss the shape they're in" do
          casts('bear')
          casts('pest')

          expect(refused.join).to include 'battle form', 'dismiss'
          expect(@spent).to eq 1
          expect(BattleForms.active(hero)['effect'].name).to eq BEAR

          hero_types('e/act dismiss/untamed form')
          casts('pest')

          expect(refused).to eq []
          expect(@spent).to eq 2
          expect(under).to contain_exactly UNTAMED, 'Spell Effect: Pest Form'
        end

        it "should replace the shape they're in where the GM has them cast it anyway" do
          casts('bear')

          typed(PF2EncounterAsCmd, "e/as #{@hero.name}=cast untamed form/focus/pest/force", @gm, FightBench::HITS)

          expect(refused).to eq []
          expect(under).to contain_exactly UNTAMED, 'Spell Effect: Pest Form'
        end

        it "should end the shape when the spell runs out" do
          casts('bear')
          row_of(UNTAMED).update(:started_round => encounter.round.to_i - 10)

          next_turn
          turn_to(@hero.name)

          expect(under).to eq []
          expect(BattleForms.active?(hero)).to be false
        end

        it "should end the shape when they dismiss the spell" do
          casts('bear')
          hero_types('e/act dismiss/untamed form')

          expect(under).to eq []
        end

        it "should come back out of the form with e/undo" do
          casts('bear')
          run(Pf2e.get_cmd_handler(@client, Command.new('e/undo'), Character[@gm.id]), 'e/undo')

          expect(under).to eq []
          expect(BattleForms.active?(hero)).to be false
        end
      end

      describe "a form from something else" do
        before(:each) do
          feats
          ActiveEffects.apply(hero, 'Spirit Guide Form', :options => [ 'claw' ], :encounter => encounter)
        end

        it "should refuse the cast, name the form, and spend nothing" do
          casts('bear')

          expect(refused.join).to include 'Spirit Guide Form'
          expect(@spent).to eq 0
          expect(under).to_not include BEAR
        end
      end

      describe "Dragon Shape" do
        before(:each) { feats('Dragon Shape') }

        it "should ask which resistance for another shape, spending nothing" do
          casts('bear')

          expect(refused.join).to include 'bludgeoning', 'poison'
          expect(@spent).to eq 0
        end

        it "should give the resistance it was told" do
          casts('bear/poison')

          expect(refused).to eq []
          expect(IWR.of(hero)['resistance'].find { |one| one['type'] == 'poison' }['value']).to eq 5
        end

        it "should ask nothing for a dragon, which is primal in a druid's hands" do
          @hero.update(:pf2_level => 12)
          casts('forest dragon')

          expect(refused).to eq []
          expect(IWR.of(hero)['resistance'].map { |one| one['type'] }).to include 'piercing', 'physical'
        end
      end

      describe "a creature" do
        it "should be able to take any shape its GM names" do
          goblin = Combatants.all(encounter).find { |one| one.label != @hero.name }

          expect(UntamedForm.available(goblin.holder, 5).map { |one| one['label'] }).to include 'Air', 'Bear'
        end
      end

      describe "the bonus for using your own attack modifier" do
        before(:each) { feats }

        def claw
          BattleForms.strikes(hero).find { |one| one['slug'] == 'claw' }
        end

        def in_bear(rank, untamed)
          ActiveEffects.on(hero).each { |one| ActiveEffects.remove(hero, one) }
          ActiveEffects.apply(hero, 'Untamed Form', :options => [ "rank #{rank}" ], :encounter => encounter) if untamed
          ActiveEffects.apply(hero, 'Animal Form (Bear)', :options => [ "rank #{rank}" ], :encounter => encounter)
          Stat.total(hero, 'attack', claw)
        end

        it "should add +2 where the character's own modifier is used" do
          without = in_bear(2, false)

          expect(in_bear(2, true)).to eq without + 2
        end

        it "should add nothing where the form's own modifier is used" do
          expect(in_bear(5, true)).to eq 18
        end

        it "should count toward which of the two is better" do
          # At rank 3 the form's +14 is level 10's own +14 before the bonus, and the bonus decides it.
          without = in_bear(3, false)

          expect(in_bear(3, true)).to be > without
        end

        it "should leave a form cast some other way alone" do
          expect(in_bear(5, false)).to eq 18
        end

        it "should reach a Strike made with the real command" do
          bonus = in_bear(2, false) + 2
          in_bear(2, true)

          hero_types("e/strike ##{goblin_number}=claw")

          expect(refused).to eq []
          expect(heard).to include "(12 +#{bonus})"
        end
      end

      describe "striking in the shape" do
        before(:each) do
          feats
          casts('bear')
        end

        def strikes(words)
          hero_types("e/strike ##{goblin_number}#{words}")
        end

        it "should Strike with the shape's attack, at its modifier" do
          strikes('=jaws')

          expect(refused).to eq []
          expect(heard).to include 'with Jaws', '(12 +18)'
        end

        it "should use the shape's attack when they name none" do
          strikes('')

          expect(refused).to eq []
          expect(heard).to include 'with Claw', '(12 +18)'
        end

        it "should refuse their own attacks" do
          strikes('=fist')

          expect(refused.join).to include 'fist'
        end

        it "should give their own attacks back when the spell ends" do
          ActiveEffects.remove_named(hero, UNTAMED)
          strikes('=fist')

          expect(refused).to eq []
          expect(heard).to include 'with Fist'
        end
      end
    end
  end
end
