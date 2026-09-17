require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A level that grants a new spellcasting source does not grant it until `advance/done`, so a
    # spell picked for it during the level is measured against a preview of the tradition the level
    # will give. The player types the source's name, and every other name in the game is matched
    # case-insensitively - so this one must be too, or the preview is missed, the source has no
    # tradition to measure against, and every spell is refused as one the class cannot cast.
    describe PF2AdvanceSpellCmd do

      def command(previews, held = {})
        magic = double(:tradition => held)
        allow(magic).to receive(:tradition=) { |value| allow(magic).to receive(:tradition).and_return(value) }

        enactor = double(:magic => magic, :name => 'Someone')
        handler = PF2AdvanceSpellCmd.new(double, double(:args => nil), double)
        allow(handler).to receive(:enactor).and_return(enactor)
        allow(Pf2e).to receive(:preview_magic_tradition).and_return(previews)

        [ handler, magic ]
      end

      it "should preview the tradition a new source will grant" do
        handler, magic = command({ 'Oracle Archetype' => [ 'divine', 'trained' ] })
        seen = nil

        handler.with_previewed_tradition('Oracle Archetype') { seen = magic.tradition.dup }

        expect(seen['Oracle Archetype']).to eq [ 'divine', 'trained' ]
      end

      it "should preview it whatever case the player typed the source in" do
        handler, magic = command({ 'Oracle Archetype' => [ 'divine', 'trained' ] })
        seen = nil

        handler.with_previewed_tradition('oracle archetype') { seen = magic.tradition.dup }

        expect(seen.values).to include [ 'divine', 'trained' ]
      end

      it "should put the magic object back afterwards" do
        handler, magic = command({ 'Oracle Archetype' => [ 'divine', 'trained' ] })

        handler.with_previewed_tradition('oracle archetype') { nil }

        expect(magic.tradition).to eq({})
      end

      it "should put it back even when the block raises" do
        handler, magic = command({ 'Oracle Archetype' => [ 'divine', 'trained' ] })

        expect { handler.with_previewed_tradition('oracle archetype') { raise 'boom' } }.to raise_error('boom')
        expect(magic.tradition).to eq({})
      end

      # A source the character already holds needs no preview, and overwriting it would hide
      # whatever proficiency they have actually earned in it.
      it "should leave a source the character already has alone" do
        handler, magic = command({ 'Oracle Archetype' => [ 'divine', 'expert' ] },
                                 { 'Oracle Archetype' => [ 'divine', 'trained' ] })
        seen = nil

        handler.with_previewed_tradition('oracle archetype') { seen = magic.tradition.dup }

        expect(seen['Oracle Archetype']).to eq [ 'divine', 'trained' ]
      end

      it "should do nothing for a source no preview knows about" do
        handler, magic = command({})
        seen = nil

        handler.with_previewed_tradition('Bard Archetype') { seen = magic.tradition.dup }

        expect(seen).to eq({})
      end
    end
  end
end
