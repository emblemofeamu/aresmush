require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Reading one source's spells and slots.
    #
    # A reader that reaches for magic.repertoire or magic.spells_per_day sees only what a
    # class-keyed hash can hold, so a source that exists only as an entry - an item, a ritual, an
    # archetype recorded as a row - is invisible to it. These accessors answer for any source.
    describe "reading a source's spells and slots", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Reader#{rand(1000000)}")
        @magic = PF2Magic.get_create_magic_obj(@char)
        @char.update(:magic => @magic)
      end

      after(:each) do
        @char.delete if @char
      end

      def magic
        PF2Magic[@magic.id]
      end

      it "should read a class's repertoire and slots from the hashes it still keeps them in" do
        @magic.update(:tradition => { 'Bard' => [ 'occult', 'trained' ] })
        @magic.update(:repertoire => { 'Bard' => { 'cantrip' => [ 'Daze' ], '1' => [ 'Soothe' ] } })
        @magic.update(:spells_per_day => { 'Bard' => { 'cantrip' => 5, '1' => 2 } })

        expect(Entries.known(magic, 'Bard')).to eq('cantrip' => [ 'Daze' ], '1' => [ 'Soothe' ])
        expect(Entries.slots(magic, 'Bard')).to eq('cantrip' => 5, '1' => 2)
      end

      it "should read a source that only exists as a row" do
        Entries.store!(@char,
          'name' => 'Staff of Fire', 'source_type' => 'item', 'category' => 'item',
          'known' => { '3' => [ 'Fireball' ] }, 'slots' => { '3' => 1 })

        expect(Entries.known(magic, 'Staff of Fire')).to eq('3' => [ 'Fireball' ])
        expect(Entries.slots(magic, 'Staff of Fire')).to eq('3' => 1)
      end

      it "should answer with nothing for a source the character does not cast from" do
        expect(Entries.known(magic, 'Wizard')).to eq({})
        expect(Entries.slots(magic, 'Wizard')).to eq({})
      end

      it "should count what a source knows at a rank, ignoring the open markers" do
        @magic.update(:tradition => { 'Wizard' => [ 'arcane', 'trained' ] })
        @magic.update(:spellbook => { 'Wizard' => { '1' => [ 'Magic Missile', 'open' ] } })

        expect(Entries.known_at(magic, 'Wizard', '1')).to eq [ 'Magic Missile' ]
        expect(Entries.open_at(magic, 'Wizard', '1')).to eq 1
      end
    end
  end
end
