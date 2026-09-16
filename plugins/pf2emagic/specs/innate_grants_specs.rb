require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Innate spells against a real magic object.
    #
    # They are a list rather than a map keyed by spell name, because a map holds one grant where two
    # sources granted the same spell - and this game has three such pairs.
    describe "innate spell grants", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Inn#{rand(1000000)}")
        @magic = PF2Magic.get_create_magic_obj(@char)
      end

      after(:each) do
        @char.delete if @char
      end

      def grant(name, rank, tradition, ability = 'Charisma')
        PF2Magic.update_magic(@char, 'Sorcerer',
          { 'innate_spell' => { 'name' => name, 'level' => rank, 'tradition' => tradition, 'cast_stat' => ability } },
          nil)

        @magic = PF2Magic[@magic.id]
      end

      it "should record a grant" do
        grant('Detect Magic', 'cantrip', 'arcane')

        expect(Entries.innate_grants(@magic).size).to eq 1
        expect(Entries.knows_innate?(@magic, 'Detect Magic')).to be true
      end

      it "should match the spell however it was capitalised" do
        grant('Detect Magic', 'cantrip', 'arcane')

        expect(Entries.knows_innate?(@magic, 'detect magic')).to be true
      end

      # Charm is granted by Enthralling Allure at rank 4 divine and by Supernatural Charm at
      # rank 1 arcane. Keyed by spell name, taking both kept only one.
      it "should keep both grants of a spell two sources give" do
        grant('Charm', 4, 'divine')
        grant('Charm', 1, 'arcane')

        grants = Entries.innate_for(@magic, 'Charm')

        expect(grants.size).to eq 2
        expect(grants.map { |g| g['tradition'] }.sort).to eq [ 'arcane', 'divine' ]
        expect(grants.map { |g| g['level'] }.sort_by(&:to_s)).to eq [ 1, 4 ]
      end

      # Six sources grant an unchosen spell, and they disagree about the ability.
      it "should keep two unchosen grants apart" do
        grant('open', 'cantrip', 'arcane', 'Intelligence')
        grant('open', 'cantrip', 'arcane', 'Charisma')

        pending = Entries.pending_innate(@magic)

        expect(pending.size).to eq 2
        expect(pending.map { |g| g['cast_stat'] }.sort).to eq [ 'Charisma', 'Intelligence' ]
      end

      it "should report the traditions represented" do
        grant('Charm', 4, 'divine')
        grant('Detect Magic', 'cantrip', 'arcane')

        expect(Entries.innate_traditions(@magic).sort).to eq [ 'arcane', 'divine' ]
      end

      # Cantrips are cast at will, so only the ranked ones take a daily use.
      it "should count only the ranked grants as taking a slot" do
        grant('Detect Magic', 'cantrip', 'arcane')
        grant('Charm', 4, 'divine')

        expect(Entries.innate_ranked(@magic).map { |g| g['name'] }).to eq [ 'Charm' ]
      end

      it "should report nothing for a character with none" do
        expect(Entries.innate?(@magic)).to be false
        expect(Entries.innate_grants(@magic)).to eq []
        expect(Entries.pending_innate(@magic)).to eq []
      end

      describe "choosing a pending spell" do
        it "should name the grant rather than replace it, keeping its rank and tradition" do
          grant('open', 'cantrip', 'arcane', 'Intelligence')

          result = Pf2emagic.select_innate_spell(@char, 'cantrip', nil, 'Detect Magic')
          @magic = PF2Magic[@magic.id]

          expect(result).to be_nil

          chosen = Entries.innate_for(@magic, 'Detect Magic').first

          expect(chosen).to_not be_nil
          expect(chosen['tradition']).to eq 'arcane'
          expect(chosen['cast_stat']).to eq 'Intelligence'
          expect(Entries.pending_innate(@magic)).to be_empty
        end

        # With two pending grants, filling one must leave the other alone.
        it "should fill one pending grant and leave the other" do
          grant('open', 'cantrip', 'arcane', 'Intelligence')
          grant('open', 'cantrip', 'arcane', 'Charisma')

          Pf2emagic.select_innate_spell(@char, 'cantrip', nil, 'Detect Magic')
          @magic = PF2Magic[@magic.id]

          expect(Entries.pending_innate(@magic).size).to eq 1
          expect(Entries.knows_innate?(@magic, 'Detect Magic')).to be true
        end
      end
    end
  end
end
