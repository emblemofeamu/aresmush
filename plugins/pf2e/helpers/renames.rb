module AresMUSH
  module Pf2e

    # Pre-Remaster names, and where each one went.
    #
    # The catalogue ships Remaster names; players arrive knowing the old ones. Every lookup that
    # misses asks this table before saying the name is not in the game, so `Magic Missile` answers
    # "that is Force Barrage now" instead of "check your spelling".
    #
    # `game/config/pf2e_renames.yml` holds one row per legacy name under `spells` and `feats`,
    # each with a status and, unless the thing was removed outright, the name it became.
    module Renames

      # What to say for a row, keyed by status and by whether this game stocks the replacement.
      # A replacement is worth naming either way - a player who knows Glyph of Warding is Rune Trap
      # stops hunting for it - but only one of the two is something they can go and take.
      MESSAGES = {
        'renamed' => { true => 'pf2e.remaster_renamed', false => 'pf2e.remaster_renamed_absent' },
        'merged'  => { true => 'pf2e.remaster_merged',  false => 'pf2e.remaster_merged_absent' },
        'removed' => { true => 'pf2e.remaster_removed', false => 'pf2e.remaster_removed' }
      }.freeze

      # A term shorter than this matches half the table, so a near-match search ignores it.
      SHORTEST_FRAGMENT = 3

      # AresMUSH merges every config file sharing a root key, so pf2e_renames_extra.yml's rows
      # arrive here alongside the generated ones.
      def self.table(kind)
        Global.read_config('pf2e_renames', kind.to_s) || {}
      end

      # [ legacy name, row ] for an exact, case-insensitive match, or nil.
      def self.lookup(term, table)
        wanted = term.to_s.strip.downcase

        return nil if wanted.empty?

        table.find { |name, _row| name.downcase == wanted }
      end

      # Legacy names holding the term, minus one that matched exactly.
      def self.near(term, table)
        wanted = term.to_s.strip.downcase

        return [] if wanted.size < SHORTEST_FRAGMENT

        table.keys.select { |name| name.downcase.include?(wanted) && name.downcase != wanted }.sort
      end

      # [ locale key, args ] for one row. Specs assert the key, so the wording stays in the locale.
      def self.message(name, row, stocked)
        status = row['status'].to_s
        to = status == 'removed' ? nil : row['to']
        by_stock = MESSAGES[status] || MESSAGES['renamed']

        [ by_stock[!to.nil? && stocks?(stocked, to)], { :old => name, :new => to } ]
      end

      def self.describe_one(name, row, stocked)
        key, args = message(name, row, stocked)

        t(key, **args)
      end

      # What to tell a player whose name matched nothing, or nil when this table has no answer.
      def self.hint(term, table, stocked)
        found = lookup(term, table)

        return describe_one(found.first, found.last, stocked) if found

        options = near(term, table)

        return nil if options.empty?

        t('pf2e.remaster_near', :options => options.first(6).map { |name| describe_one(name, table[name], stocked) }.join(" "))
      end

      # The same answer read straight from config. `stocked` is the game's current names.
      def self.hint_for(kind, term, stocked)
        hint(term, table(kind), stocked)
      end

      def self.stocks?(stocked, name)
        Array(stocked).any? { |held| held.to_s.casecmp?(name.to_s) }
      end
    end
  end
end
