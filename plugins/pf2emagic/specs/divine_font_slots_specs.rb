require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # A Cleric's divine font, all the way through to the slot count the game enforces.
    #
    # The unit specs prove Pf2emagic::Restrictions produces the row. This proves the row reaches
    # `max_spells_per_day` and `prepared_set_fits?`, which is where it was missing: the font was
    # asked for, stored, printed on the sheet and used as a feat prerequisite, and appeared in no
    # slot count anywhere, so every Cleric was one slot short at every rank they could cast.
    describe "the divine font's slots", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Cleric#{rand(1000000)}")
        @char.update(:pf2_level => 3, :pf2_base_info => { 'charclass' => 'Cleric' })

        @magic = PF2Magic.create(:character => @char)
        @magic.update(
          :tradition => { 'Cleric' => [ 'divine', 'trained' ] },
          :spells_per_day => { 'Cleric' => { 'cantrip' => 5, '1' => 3, '2' => 3 } }
        )
        # `char.magic` is a reference, so the character has to point back at it.
        @char.update(:magic => @magic)
      end

      after(:each) do
        @magic.delete if @magic
        @char.delete if @char
      end

      # Re-read, so a change to the magic object is visible through the character's reference.
      def subject
        Character[@char.id]
      end

      it "should give no extra slot before a font is chosen" do
        expect(Pf2emagic.max_spells_per_day(subject, 'Cleric', '1')).to eq 3
      end

      it "should give one extra slot at each rank once a font is chosen" do
        @magic.update(:divine_font => 'heal')

        expect(Pf2emagic.max_spells_per_day(subject, 'Cleric', '1')).to eq 4
        expect(Pf2emagic.max_spells_per_day(subject, 'Cleric', '2')).to eq 4
      end

      it "should give no extra cantrip slot" do
        @magic.update(:divine_font => 'heal')

        expect(Pf2emagic.max_spells_per_day(subject, 'Cleric', 'cantrip')).to eq 5
      end

      it "should give no extra slot at a rank the cleric cannot cast at" do
        @magic.update(:divine_font => 'heal')

        expect(Pf2emagic.max_spells_per_day(subject, 'Cleric', '5')).to eq 0
      end

      # The font slot is not a free slot: it holds the font spell and nothing else.
      it "should only let the font spell use the extra slot" do
        @magic.update(:divine_font => 'heal')

        # Three ordinary slots plus the font's. Four arbitrary spells do not fit; three plus Heal
        # does.
        expect(Pf2emagic.prepared_set_fits?(subject, 'Cleric', '1', %w(Bless Shield Sanctuary Command))).to be false
        expect(Pf2emagic.prepared_set_fits?(subject, 'Cleric', '1', %w(Bless Shield Sanctuary Heal))).to be true
      end

      it "should take harm instead for a cleric whose font is harm" do
        @magic.update(:divine_font => 'harm')

        expect(Pf2emagic.prepared_set_fits?(subject, 'Cleric', '1', %w(Bless Shield Sanctuary Harm))).to be true
        expect(Pf2emagic.prepared_set_fits?(subject, 'Cleric', '1', %w(Bless Shield Sanctuary Heal))).to be false
      end
    end
  end
end
