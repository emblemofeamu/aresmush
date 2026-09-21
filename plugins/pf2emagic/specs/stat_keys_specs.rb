require "plugin_test_loader"

module AresMUSH

  # The vocabulary of a magic_stats block.
  #
  # A caller handed one of these blocks has to tell a block of stats from a block keyed by class,
  # and the only thing that separates them is whether the keys are stats. So the list has to be
  # complete: a key missing from it makes a block of stats look class-keyed, and each stat is then
  # dispatched as though it named a class.
  describe PF2Magic do

    describe :STAT_KEYS do
      it "should name every key update_magic handles" do
        source = File.read(File.join(Pf2emagic.plugin_dir, 'models', 'magic.rb'))
        body = source[source.index('def self.update_magic')..source.index('def self.get_max_focus_pool')]
        handled = body.scan(/^\s*when ((?:["'][a-z_]+["'](?:,\s*)?)+)$/).flatten
                      .flat_map { |line| line.scan(/[a-z_]+/) }.uniq

        expect(handled - PF2Magic::STAT_KEYS).to eq []
      end
    end

    describe :stats_block? do
      it "should recognise a block of stats" do
        expect(PF2Magic.stats_block?('spells_per_day' => { '1' => 2 })).to be true
      end

      it "should recognise a block keyed by class" do
        expect(PF2Magic.stats_block?('Wizard' => { 'spells_per_day' => { '1' => 2 } })).to be false
      end

      it "should not mistake an empty block for one keyed by class" do
        expect(PF2Magic.stats_block?({})).to be true
      end
    end
  end
end
