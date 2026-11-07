require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `+e/how <name>`: the commands that do what a player names - an action, a Strike, a spell, an item
    # they carry, or something the game does, like spending a Hero Point - as they would type them.
    describe HowTo do

      def known(more = {})
        { 'strikes' => [ { 'names' => [ 'Longsword', 'Old Faithful' ] }, { 'names' => [ 'Fist' ] }, { 'names' => [ 'Shortbow' ] } ],
          'actions' => [ { 'name' => 'Trip', 'cost' => 'one action', 'target' => true },
                         { 'name' => 'Raise a Shield', 'cost' => 'one action' },
                         { 'name' => 'Opportune Riposte', 'cost' => 'reaction', 'target' => true, 'strike' => true },
                         { 'name' => 'Treat Wounds', 'cost' => 'activity', 'target' => true } ],
          'spells' => [ { 'name' => 'Fear', 'from' => 'Bard' }, { 'name' => 'Fear', 'from' => 'Sorcerer' },
                        { 'name' => 'Courageous Anthem', 'from' => 'focus' }, { 'name' => 'Daze', 'from' => 'innate' } ],
          'items' => [ { 'category' => 'consumables', 'number' => 0, 'name' => 'Healing Potion (Minor)' },
                       { 'category' => 'consumables', 'number' => 1, 'name' => "Alchemist's Fire (Lesser)", 'thrown' => true },
                       { 'category' => 'consumables', 'number' => 2, 'name' => 'Silver Arrows', 'ammunition' => 'silver' },
                       { 'category' => 'weapons', 'number' => 0, 'name' => 'Longsword', 'equipped' => true },
                       { 'category' => 'weapons', 'number' => 1, 'name' => 'Dagger' },
                       { 'category' => 'magicitem', 'number' => 0, 'name' => 'Wand of Heal', 'uses' => [ 'heal' ] } ] }.merge(more)
      end

      def commands(term, held = known)
        found = HowTo.answers(term, held)

        found.ok? ? found.state.map(&:first) : found.code
      end

      it "should give every Strike for a Strike" do
        expect(commands('strike')).to eq [ '+e/strike <target>=Longsword', '+e/strike <target>=Fist', '+e/strike <target>=Shortbow' ]
      end

      it "should give the Strike a weapon makes, and how to draw one not drawn" do
        expect(commands('dagger')).to eq [ '+e/equip weapons=1' ]
        expect(commands('old faithful')).to eq [ '+e/strike <target>=Longsword' ]
      end

      it "should give an action with what it is used at, and a Strike's weapon" do
        expect(commands('trip')).to eq [ '+e/act trip=<target>' ]
        expect(commands('raise a shield')).to eq [ '+e/act raise a shield' ]
        expect(commands('opportune riposte')).to eq [ '+e/act opportune riposte=<target>/<weapon>' ]
      end

      it "should say what an action costs" do
        expect(HowTo.answers('riposte', known).state.first.last).to include('reaction')
      end

      it "should give each way a spell is cast" do
        expect(commands('fear')).to eq [ '+e/cast fear=<target>/class Bard', '+e/cast fear=<target>/class Sorcerer' ]
        expect(commands('courageous anthem')).to eq [ '+e/cast courageous anthem=<target>/focus' ]
        expect(commands('daze')).to eq [ '+e/cast daze=<target>/innate' ]
      end

      it "should give one way for a spell cast only one way" do
        held = known('spells' => [ { 'name' => 'Fear', 'from' => 'Bard' } ])

        expect(commands('fear', held)).to eq [ '+e/cast fear=<target>' ]
      end

      it "should give how each item is used" do
        expect(commands('healing potion')).to eq [ '+e/use consumables=0', '+e/use consumables=0/<who>' ]
        expect(commands("alchemist's fire")).to eq [ "+e/strike <target>=Alchemist's Fire (Lesser)" ]
        expect(commands('silver arrows')).to eq [ '+e/strike <target>=<weapon>/silver' ]
        expect(commands('wand of heal')).to eq [ '+e/use magicitem=0/heal' ]
      end

      it "should give what spends a Hero Point, by any of its words" do
        expected = [ 'hero', 'hero/reroll', 'hero/boost', 'hero/survive' ]

        expect([ commands('hero point'), commands('hero points'), commands('reroll') ]).to eq [ expected ] * 3
      end

      it "should give the game's own commands for what it does" do
        expect(commands('reload')).to eq [ '+e/reload [<weapon>]' ]
        expect(commands('cover')).to include('+e/cover <target>=<none|lesser|standard|greater>')
      end

      it "should give everything a name could mean" do
        expect(commands('longsword')).to eq [ '+e/strike <target>=Longsword' ]
        expect(commands('heal')).to eq [ '+e/use consumables=0', '+e/use consumables=0/<who>', '+e/use magicitem=0/heal' ]
      end

      it "should say when nothing it knows is called that" do
        expect(commands('fly')).to eq :how_nothing
        expect(commands('')).to eq :how_nothing
      end
    end
  end
end
