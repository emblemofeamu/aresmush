require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # The shape a signature spell is stored in. There were two writers with two shapes, and
    # only one matched what the readers looked for - so a spell designated a signature by
    # Arcane Evolution was never treated as one when cast, and never shown.
    describe "recording a signature spell", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Sig#{rand(1000000)}")
        @magic = PF2Magic.get_create_magic_obj(@char)
      end

      after(:each) do
        @char.delete if @char
      end

      it "should store it under the caster class at the spell's rank" do
        Pf2emagic.record_signature_spell(@magic, 'Sorcerer', '3', 'Fireball')

        expect(@magic.signature_spells).to eq('Sorcerer' => { '3' => [ 'Fireball' ] })
      end

      it "should keep a cantrip under its own rank key" do
        Pf2emagic.record_signature_spell(@magic, 'Sorcerer', 'cantrip', 'Ignition')

        expect(@magic.signature_spells['Sorcerer']['cantrip']).to eq [ 'Ignition' ]
      end

      it "should add to a rank that already has one rather than replacing it" do
        Pf2emagic.record_signature_spell(@magic, 'Sorcerer', '3', 'Fireball')
        Pf2emagic.record_signature_spell(@magic, 'Sorcerer', '3', 'Haste')

        expect(@magic.signature_spells['Sorcerer']['3']).to eq [ 'Fireball', 'Haste' ]
      end

      it "should not record the same spell twice" do
        2.times { Pf2emagic.record_signature_spell(@magic, 'Sorcerer', '3', 'Fireball') }

        expect(@magic.signature_spells['Sorcerer']['3']).to eq [ 'Fireball' ]
      end

      it "should keep two casting classes apart" do
        Pf2emagic.record_signature_spell(@magic, 'Sorcerer', '3', 'Fireball')
        Pf2emagic.record_signature_spell(@magic, 'Bard', '3', 'Dirge of Doom')

        expect(@magic.signature_spells.keys.sort).to eq [ 'Bard', 'Sorcerer' ]
      end

      # The readers' contract. The magic display only counts an entry whose value is a hash of
      # ranks, which is exactly why the flat list the old writer produced was invisible.
      it "should be in the shape the readers look for" do
        Pf2emagic.record_signature_spell(@magic, 'Sorcerer', '3', 'Fireball')

        @magic.signature_spells.each_pair do |charclass, ranks|
          expect(charclass).to be_a String
          expect(ranks).to be_a Hash
          ranks.each_value { |spells| expect(spells).to be_a Array }
        end
      end
    end
  end
end
