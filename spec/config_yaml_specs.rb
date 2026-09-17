require "aresmush"
require "yaml"

module AresMUSH

  # The game's data is a hundred YAML files nobody parses until the server boots, and two of the
  # ways they go wrong are silent: a duplicate key keeps the last value and says nothing, and a
  # spell defined in two of the five spell files quietly overrides itself when they are merged.
  # A tab in the indentation is the loud one, and it takes the whole file with it.
  describe "the game's YAML" do

    ROOT = File.expand_path('..', __dir__)

    def self.data_files
      @data_files ||= (Dir[File.join(ROOT, 'game', 'config', '*.yml')] +
                       Dir[File.join(ROOT, '{engine,plugins}', '**', 'locales', '*.yml')]).sort
    end

    def short(path)
      path.sub(ROOT + '/', '')
    end

    # Every duplicated mapping key in a document, as "a > b > key".
    def duplicate_keys(node, trail = [])
      return [] unless node.respond_to?(:children) && node.children

      found = []

      if node.is_a?(Psych::Nodes::Mapping)
        seen = {}
        node.children.each_slice(2) do |key, value|
          name = key.respond_to?(:value) ? key.value : key.to_s
          found << (trail + [ name ]).join(' > ') if seen[name]
          seen[name] = true
          found.concat(duplicate_keys(value, trail + [ name ]))
        end
      else
        node.children.each { |child| found.concat(duplicate_keys(child, trail)) }
      end

      found
    end

    it "should have a file for every one we think we are checking" do
      expect(self.class.data_files.size).to be > 100
    end

    it "should parse, every file" do
      broken = self.class.data_files.filter_map do |path|
        begin
          YAML.load_file(path)
          nil
        rescue => e
          "#{short(path)}: #{e.message.lines.first.to_s.strip}"
        end
      end

      expect(broken).to eq []
    end

    # A tab is never valid indentation in YAML, and pasting one in is the usual way a file that
    # looks right refuses to load.
    it "should indent with spaces" do
      tabbed = self.class.data_files.filter_map do |path|
        line = File.readlines(path).index { |l| l =~ /^\s*\t/ }
        line && "#{short(path)}:#{line + 1}"
      end

      expect(tabbed).to eq []
    end

    it "should define each key once in a file" do
      dupes = self.class.data_files.flat_map do |path|
        duplicate_keys(Psych.parse_file(path)).map { |key| "#{short(path)} defines '#{key}' twice" }
      rescue StandardError
        []
      end

      expect(dupes.sort).to eq []
    end

    # A mis-indent usually parses. It just reparents: a line pushed one level too deep becomes a
    # field of the entry above it, and a line pulled out becomes an entry of its own. Neither
    # raises, both change the data, and this codebase has been bitten by it before. The two checks
    # below are the shapes that catch it - one generic, one for the file that is most hand-edited.

    # Every AresMUSH config file is a single root key wrapping everything else, so a second
    # top-level key means a block lost its indentation.
    it "should wrap each config file in exactly one root key" do
      wrong = Dir[File.join(ROOT, 'game', 'config', '*.yml')].sort.filter_map do |path|
        loaded = YAML.load_file(path)

        next "#{short(path)} is a #{loaded.class}, not a mapping" unless loaded.is_a?(Hash)
        next if loaded.keys.size == 1

        "#{short(path)} has #{loaded.keys.size} root keys: #{loaded.keys.first(4).inspect}"
      end

      expect(wrong).to eq []
    end

    # The fields a spell may have. A name outside this set is almost always an entry that slipped
    # a level and became a field of the spell above it.
    SPELL_FIELDS = %w{
      base_level traits actions effect range duration tradition heighten
      target area bloodline mystery trigger requirements
    }.freeze

    REQUIRED_SPELL_FIELDS = %w{base_level traits actions effect}.freeze

    def spell_catalogue
      @spell_catalogue ||= Dir[File.join(ROOT, 'game', 'config', '*spell*.yml')].sort
                           .each_with_object({}) { |path, all| (YAML.load_file(path)['pf2e_spells'] || {}).each { |k, v| all[k] = [ v, path ] } }
    end

    it "should give every spell the shape of a spell" do
      wrong = spell_catalogue.filter_map do |name, (entry, path)|
        next "#{short(path)}: '#{name}' is a #{entry.class}, not a mapping" unless entry.is_a?(Hash)

        missing = REQUIRED_SPELL_FIELDS - entry.keys
        stray = entry.keys - SPELL_FIELDS

        next "#{short(path)}: '#{name}' is missing #{missing.join(', ')}" if missing.any?
        next "#{short(path)}: '#{name}' has unexpected field(s) #{stray.join(', ')} - a mis-indented entry?" if stray.any?
      end

      expect(wrong.sort).to eq []
    end

    # The rename table is generated from Foundry's Remaster Changes journal, so a change in that
    # journal's markup shows up here as a row of the wrong shape rather than as a hint nobody
    # can read.
    RENAME_STATUSES = %w{renamed merged removed}.freeze

    # Generated rows and hand-added ones share a root key, and the game reads them merged.
    def rename_table
      @rename_table ||= Dir[File.join(ROOT, 'game', 'config', 'pf2e_renames*.yml')].sort
                        .each_with_object({}) do |path, all|
        (YAML.load_file(path)['pf2e_renames'] || {}).each { |kind, rows| (all[kind] ||= {}).merge!(rows || {}) }
      end
    end

    it "should give every pre-Remaster name a status and, unless it was removed, a replacement" do
      wrong = rename_table.flat_map do |kind, rows|
        rows.filter_map do |old, row|
          next "#{kind}: '#{old}' has status #{row['status'].inspect}" unless RENAME_STATUSES.include?(row['status'])
          next "#{kind}: '#{old}' was #{row['status']} into nothing" if row['status'] != 'removed' && row['to'].to_s.strip.empty?
          next "#{kind}: '#{old}' was removed but names a replacement" if row['status'] == 'removed' && row['to']
        end
      end

      expect(wrong.sort).to eq []
    end

    # A replacement that is itself a pre-Remaster name leaves the player one hop short of the
    # name they can actually look up.
    it "should point every rename at a current name" do
      chained = rename_table.flat_map do |kind, rows|
        rows.filter_map do |old, row|
          "#{kind}: '#{old}' points at '#{row['to']}', which is itself a pre-Remaster name" if row['to'] && rows.key?(row['to'])
        end
      end

      expect(chained.sort).to eq []
    end

    it "should hold both kinds the game looks up" do
      expect(rename_table.keys.sort).to eq [ 'feats', 'spells' ]
    end

    # The five spell files are merged into one catalogue, so a name in two of them loses whichever
    # loads first, and nothing says which spell the character ended up with.
    it "should define each spell in only one file" do
      seen = {}
      clashes = []

      Dir[File.join(ROOT, 'game', 'config', '*spell*.yml')].sort.each do |path|
        (YAML.load_file(path)['pf2e_spells'] || {}).each_key do |spell|
          clashes << "'#{spell}' is in #{short(seen[spell])} and #{short(path)}" if seen[spell]
          seen[spell] = path
        end
      end

      expect(clashes).to eq []
    end
  end
end
