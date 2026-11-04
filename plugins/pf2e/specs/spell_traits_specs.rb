require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The Remaster took alignment out of the game: a spell that was good or evil is holy or unholy, and
    # lawful and chaotic are gone. Foundry still carries the old traits on spells from books the Remaster
    # never reprinted, so an import brings them back unless this catches it.
    describe "the traits the spell data holds" do
      before(:all) do
        @mechanics = YAML.load_file('game/config/pf2e_spell_mechanics.yml')['pf2e_spell_mechanics']
      end

      it "should name no alignment trait" do
        aligned = @mechanics.select { |_name, one| (Array(one['traits']) & %w{good evil lawful chaotic}).any? }

        expect(aligned.keys).to eq []
      end
    end
  end
end
