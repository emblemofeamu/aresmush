module AresMUSH
  module Pf2e

    # The creatures a GM can add to an encounter: Foundry's bestiaries, imported to `game/bestiary`
    # (`scripts/import_foundry_npcs.py`).
    #
    # Three thousand stat blocks are too many to hold in config, which is read whole at startup, so the
    # index of names is read once and a pack's file only when a creature in it is asked for.
    module Bestiary

      def self.dir
        File.join(AresMUSH.game_path, 'bestiary')
      end

      # Every creature the game lists. Pathfinder's dragons that aren't in Ea's setting keep their files, and
      # a creature already in a fight can still read its stat block (`entry`), but nothing offers them.
      def self.index
        @index ||= whole_index.reject { |name, _| name.match?(left_out) }
      end

      def self.whole_index
        @whole_index ||= load_file('index.yml')
      end

      def self.left_out
        kinds = Array(Global.read_config('pf2e_dragons', 'left_out'))

        kinds.empty? ? /\z\A/ : /\A(?:#{kinds.map { |one| Regexp.escape(one) }.join('|')}) (?:Dragon|Archdragon)\b/
      end

      def self.pack(name)
        @packs ||= {}
        @packs[name] ||= load_file("#{name}.yml")
      end

      def self.load_file(name)
        path = File.join(dir, name)

        File.exist?(path) ? (YAML.load_file(path) || {}) : {}
      end

      # Drops what has been read, for a spec or an import that has just rewritten the files.
      def self.reset!
        @index = nil
        @whole_index = nil
        @packs = nil
      end

      def self.entry(name)
        listed = whole_index[name]

        listed ? pack(listed['pack'])[name] : nil
      end

      # The creature called exactly this, if there is one.
      def self.named(term)
        wanted = Domains.slug(term)

        index.keys.find { |name| Domains.slug(name) == wanted }
      end

      # The creature a GM means, by the name they typed.
      def self.find(term)
        wanted = Domains.slug(term)
        names = index.keys

        exact = named(term)

        return Ok.new(:state => exact) if exact

        close = names.select { |name| Domains.slug(name).include?(wanted) }

        return Ok.new(:state => close.first) if close.size == 1
        return Err.new(:not_found, 'pf2e.creature_not_found', 'creature' => term) if close.empty?

        Err.new(:ambiguous, 'pf2e.creature_ambiguous', 'creature' => term,
                'options' => close.first(8).join(', '))
      end

      # Creatures whose name contains the words, at a level where one is given, by level then name.
      def self.search(words, level = nil)
        wanted = Domains.slug(words)

        index.select { |name, one|
          Domains.slug(name).include?(wanted) && (level.nil? || one['level'].to_i == level.to_i)
        }.sort_by { |name, one| [ one['level'].to_i, name ] }
      end
    end
  end
end
