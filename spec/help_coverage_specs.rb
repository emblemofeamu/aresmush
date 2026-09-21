require "aresmush"

module AresMUSH

  # Every command the PF2e dispatcher answers to, held against the help files.
  #
  # A command nobody has written down is a command players do not find. Two shipped that way -
  # advance/feats and spell/eligible existed before anything in game pointed at them - and the
  # playtest that produced them was full of players guessing at commands that were there all along.
  describe "the PF2e help" do

    HELP_ROOT = File.expand_path('..', __dir__)

    # Commands deliberately left out of player help, and why.
    UNDOCUMENTED_ON_PURPOSE = {
      'selfaward/xp' => 'a playtest-only self-service command; on a live game staff award XP'
    }.freeze

    def self.dispatch_source
      @dispatch_source ||= Dir[File.join(HELP_ROOT, 'plugins', 'pf2e*', '*.rb')].map { |path| File.read(path) }.join("\n")
    end

    def self.help_text
      @help_text ||= Dir[File.join(HELP_ROOT, 'plugins', '**', 'help', '**', '*.md')]
                     .map { |path| File.read(path) }.join("\n").downcase
    end

    # `when "advance"` wrapping a `case cmd.switch` of `when "feat"` is the command advance/feat.
    def self.switch_commands
      found = dispatch_source.scan(/when "([a-z0-9_]+)"\s*\n\s*case cmd\.switch\n((?:.|\n)*?)\n\s*end/)

      found.flat_map do |root, body|
        body.scan(/when ((?:"[a-z0-9_]+"(?:,\s*)?)+)/).flatten
            .flat_map { |group| group.scan(/"([a-z0-9_]+)"/).flatten }
            .map { |switch| "#{root}/#{switch}" }
      end.uniq.sort
    end

    it "should find the dispatcher's commands at all, so this spec cannot pass by reading nothing" do
      expect(self.class.switch_commands.size).to be > 25
    end

    it "should document every command the dispatcher answers to" do
      undocumented = self.class.switch_commands.reject do |command|
        UNDOCUMENTED_ON_PURPOSE.key?(command) || self.class.help_text.include?(command)
      end

      expect(undocumented).to eq []
    end

    # A gap that gets documented should come off the list, or the list stops meaning anything.
    it "should not excuse a command that is in fact documented" do
      excused_but_present = UNDOCUMENTED_ON_PURPOSE.keys.select { |command| self.class.help_text.include?(command) }

      expect(excused_but_present).to eq []
    end
  end
end
