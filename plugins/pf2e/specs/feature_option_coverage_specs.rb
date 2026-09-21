require "aresmush"
require "yaml"

module AresMUSH

  # Every class feature that asks the player to choose something, held against the table that
  # applies the choice.
  #
  # A feature with no row is not silently ignored - the player is told "your choice is recorded, but
  # nothing else it should change has been applied, please let code staff know". That is the right
  # message for a feature nobody has considered, and the wrong one for a known state: every Champion
  # in the game saw it at level 3, for a choice the sheet does record.
  describe "the class features that take a choice" do

    # plugins/pf2e/specs -> the game root, three levels up.
    OPTION_ROOT = File.expand_path('../../..', __dir__)

    def self.choice_names
      table = YAML.load_file(File.join(OPTION_ROOT, 'game', 'config', 'pf2e_class.yml'))['pf2e_class']
      found = []

      walk = lambda do |node|
        if node.is_a?(Hash)
          found << node['choice_name'] if node.key?('choice_name')
          node.each_value { |value| walk.call(value) }
        elsif node.is_a?(Array)
          node.each { |value| walk.call(value) }
        end
      end

      walk.call(table)

      found.compact.uniq.sort
    end

    def self.applied
      source = File.read(File.join(OPTION_ROOT, 'plugins', 'pf2e', 'advancement', 'apply.rb'))
      block = source[/FEATURE_OPTIONS = \{.*?\n        \}\.freeze/m].to_s

      block.scan(/^\s{10}'([^']+)' => \{/).flatten
    end

    it "should find the config's choices at all, so this cannot pass by reading nothing" do
      expect(self.class.choice_names.size).to be >= 5
    end

    it "should find the applying table at all" do
      expect(self.class.applied.size).to be >= 5
    end

    # A row that applies nothing is a decision on the record. No row at all is an oversight, and the
    # player is the one who finds out.
    it "should have a row for every choice a class feature offers" do
      expect(self.class.choice_names - self.class.applied).to eq []
    end

    it "should not carry a row for a choice no class offers any more" do
      expect(self.class.applied - self.class.choice_names).to eq [ 'Divine Ally' ]
    end
  end
end
