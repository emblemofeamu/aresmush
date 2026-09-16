module AresMUSH
  module Pf2emagic

    # A character's spellcasting, as one self-describing entry per source.
    #
    # This is the shape Foundry's PF2e system and Pathbuilder both settled on: a character has
    # N spellcasting entries, each carrying its own tradition, category, ability, proficiency
    # and spell lists. Nothing has to work out "which source" from a key.
    #
    # `PF2Magic` instead holds eighteen parallel hashes with no source concept, so each
    # attribute invented its own key for which-source and they disagree - class for most, focus
    # *type* for focus spells, spell *name* for innate, and in one place a feat's name, which is
    # how Arcane Evolution's signature spell came to be silently ignored. See
    # docs/plans/2026-09-16-spellcasting-entries.md.
    #
    # `derive` is the projection from those hashes onto entries. It is pure - a plain hash of
    # attributes in, entry hashes out, no character and no config - so the mapping can be proven
    # before any reader is moved onto it, which is what makes the migration safe to do in steps.
    #
    # It is deliberately lossy in one place, and honest about it: two sources feeding the same
    # focus type are a single bucket today, so deriving cannot separate what was never
    # separately recorded. That loss *is* the finding.
    module Entries

      FOCUS = 'focus'.freeze
      INNATE = 'innate'.freeze

      # A slot the player has not filled yet. The same marker Pf2e::Slots uses, named here so the
      # magic plugin does not reach into the other one for a string.
      OPEN = 'open'.freeze

      # The blank entry, so every row has every field whether or not its source fills it.
      FIELDS = {
        'name' => nil,
        'source_type' => nil,
        'category' => nil,
        'tradition' => nil,
        'ability' => nil,
        'proficiency' => nil,
        'slots' => {},
        'known' => {},
        'signature' => {},
        'restrictions' => {},
        'prepared' => {},
        'uses' => {},
        'granted_by' => nil,
        'granted_at' => nil
      }.freeze

      # One row per kind of source, each turning the hashes that describe it into entries.
      SOURCES = [
        # A casting class or archetype. `tradition` is the register of them - keyed by class,
        # except for the literal 'innate' key its default value carries, which is not one.
        {
          'kind' => 'class',
          'entries' => lambda { |magic, caster_types|
            (magic['tradition'] || {}).reject { |key, _v| key.to_s.casecmp?(INNATE) }.map do |source, trad|
              category = caster_types[source] || caster_types[source.to_s]
              spontaneous = category.to_s == 'spontaneous'

              Entries.entry(
                'name' => source,
                'source_type' => source.to_s.downcase.include?('archetype') ? 'archetype' : 'class',
                'category' => category,
                'tradition' => Array(trad)[0],
                'proficiency' => Array(trad)[1],
                'ability' => (magic['spell_abil'] || {})[source],
                'slots' => (magic['spells_per_day'] || {})[source] || {},
                # A spontaneous caster knows a repertoire; a prepared one keeps a spellbook.
                'known' => ((spontaneous ? magic['repertoire'] : magic['spellbook']) || {})[source] || {},
                'signature' => (magic['signature_spells'] || {})[source] || {},
                'restrictions' => (magic['restricted_spellbook'] || {})[source] || {}
              )
            end
          }
        },
        # Innate spells: a list of grants, each carrying its own rank, tradition and the ability
        # it is cast off. Grouped by tradition and ability, which is what distinguishes one
        # innate source from another as far as casting is concerned.
        {
          'kind' => 'innate',
          'entries' => lambda { |magic, _caster_types|
            by_source = Array(magic['innate_spells']).each_with_object({}) do |grant, grouped|
              next unless grant.is_a?(Hash)

              key = [ grant['tradition'], grant['cast_stat'] ]
              rank = grant['level'].to_s
              known = (grouped[key] ||= {})

              known[rank] = Array(known[rank]) + [ grant['name'] ]
            end

            by_source.map do |(tradition, ability), known|
              Entries.entry(
                'name' => [ tradition, INNATE ].compact.join(" "),
                'source_type' => INNATE,
                'category' => INNATE,
                'tradition' => tradition,
                'ability' => ability,
                'known' => known
              )
            end
          }
        }
      ].freeze

      # Entry hashes for everything this character casts from.
      #
      # `caster_types` maps a source name to 'prepared' or 'spontaneous'. It is passed in rather
      # than read from config so this stays pure and specs need no game data.
      def self.derive(magic, caster_types: {})
        attributes = stringify(magic)

        SOURCES.flat_map { |source| Array(source['entries'].call(attributes, caster_types)) }
      end

      # Everything a live character casts from.
      #
      # This is the seam, and it merges rather than choosing. For each source, whatever has been
      # stored as a row wins, and the projection from the legacy hashes fills in the fields that
      # have not moved yet. So one field of one category can be migrated at a time - a class's
      # tradition before its repertoire - and a reader sees a complete entry throughout, unable
      # to tell which side of the move each field came from.
      #
      # A category migrated in full simply has nothing left to fill in.
      def self.for_magic(magic)
        return [] unless magic

        rows = stored(magic.character)
        projected = derived(magic)

        merged = projected.map do |entry|
          row = rows.find { |r| same_source?(r, entry) }

          row ? fill_gaps(row, entry) : entry
        end

        # Sources that exist only as rows - a focus type, an item, a ritual - have nothing to
        # project from.
        merged + rows.reject { |row| projected.any? { |entry| same_source?(row, entry) } }
      end

      # Two descriptions of the same source. Name and category together, because a name alone is
      # not unique: a Bard's repertoire and their composition focus spells share one.
      def self.same_source?(row, entry)
        row['name'].to_s.casecmp?(entry['name'].to_s) && row['category'].to_s == entry['category'].to_s
      end

      # The row, with anything it has not got taken from the projection. A row's blank is treated
      # as "not migrated yet" rather than as "empty", which is the price of migrating field by
      # field - and the reason a category should not be left half-moved for long.
      def self.fill_gaps(row, projected)
        row.each_with_object({}) do |(field, value), merged|
          merged[field] = blank_field?(value) ? projected[field] : value
        end
      end

      def self.blank_field?(value)
        value.nil? || value == {} || value == [] || value == ""
      end

      def self.derived(magic)
        return [] unless magic

        attributes = ATTRIBUTES.each_with_object({}) { |attr, h| h[attr] = magic.send(attr) }
        types = (attributes['tradition'] || {}).keys.each_with_object({}) do |source, h|
          h[source] = Pf2emagic.get_caster_type(source)
        end

        derive(attributes, :caster_types => types)
      end

      # ------------------------------------------------------------------------------
      # Stored rows
      # ------------------------------------------------------------------------------

      def self.stored(char)
        return [] unless char && char.respond_to?(:spellcasting_entries)

        char.spellcasting_entries.to_a.map { |row| row.to_h }
      end

      def self.rows(char, category)
        return [] unless char && char.respond_to?(:spellcasting_entries)

        char.spellcasting_entries.to_a.select { |row| row.category.to_s == category.to_s }
      end

      # Creates or updates one entry. Identified by name and category together, because a name
      # alone is not unique - two sources may share one.
      def self.store!(char, values)
        attrs = FIELDS.merge(stringify(values))
        existing = char.spellcasting_entries.to_a.find do |row|
          row.name.to_s.casecmp?(attrs['name'].to_s) &&
            row.category.to_s == attrs['category'].to_s &&
            row.granted_by.to_s == attrs['granted_by'].to_s
        end

        writable = attrs.reject { |key, _v| key == 'name' && existing }
        row = existing || Pf2eSpellcastingEntry.create(:character => char, :name => attrs['name'])

        row.update(writable.each_with_object({}) { |(key, value), h| h[key.to_sym] = value })

        row
      end

      def self.forget!(char, category)
        rows(char, category).each { |row| row.delete }
      end

      # What derive reads. Listed so for_magic does not depend on the model having exactly
      # these and nothing else.
      # What the projection still reads. Focus spells are absent because they are stored as rows
      # now, not projected - which is what a finished migration looks like for a category.
      ATTRIBUTES = %w(
        tradition spell_abil spells_per_day spellbook repertoire signature_spells
        restricted_spellbook innate_spells
      ).freeze

      # ------------------------------------------------------------------------------
      # Asking questions of the entries
      # ------------------------------------------------------------------------------
      #
      # These are the seam. Readers that used to reach into the parallel hashes ask here
      # instead, so when the entries become the storage rather than a projection of it, the
      # readers do not change.

      def self.find(magic, source)
        for_magic(magic).find { |e| e['name'].to_s.casecmp?(source.to_s) }
      end

      # The ranks at which a spell is one of this source's signature spells.
      #
      # Ranks rather than a yes/no, because a signature spell may be heightened to any rank the
      # caster has a slot for, and the caller needs to know which. Matched case-insensitively,
      # like every other name comparison in the game - the old inline version was exact, so a
      # difference in capitalisation between how a spell was recorded and how it was cast would
      # have quietly lost the heightening.
      def self.signature_ranks(magic, source, spell)
        entry = find(magic, source)

        return [] unless entry

        (entry['signature'] || {}).select do |_rank, spells|
          Array(spells).any? { |s| s.to_s.casecmp?(spell.to_s) }
        end.keys
      end

      # The class and archetype entries - what a character casts spells *from*, as opposed to
      # their focus and innate spells. Replaces `tradition.keys - ['innate']`, which was spelled
      # out in three places, each having to remember that 'innate' is in there and is not a
      # class.
      def self.casting(magic)
        for_magic(magic).select { |e| [ 'class', 'archetype' ].include?(e['source_type']) }
      end

      def self.casts_from?(magic, source)
        !find(magic, source).nil?
      end

      # The tradition and proficiency a source casts at.
      #
      # Named, because the underlying store is a two-element array and every reader had to know
      # that [0] is the tradition and [1] the proficiency.
      def self.tradition_of(magic, source)
        (find(magic, source) || {})['tradition']
      end

      def self.proficiency_of(magic, source)
        (find(magic, source) || {})['proficiency']
      end

      # ------------------------------------------------------------------------------
      # How a source decides which spells it may cast
      # ------------------------------------------------------------------------------
      #
      # PF2e has two answers and they are not variations of each other:
      #
      #   **enumerated** - the source knows particular spells and nothing else. A Wizard's
      #     spellbook, a Sorcerer's or Bard's repertoire. Learning one is an event that happens
      #     at a level, so it belongs on the level ladder.
      #   **by rule** - the source may cast anything on its tradition's list at a rank it has a
      #     slot for. A Cleric or Druid has no spellbook; they prepare from the whole divine or
      #     primal list. There is nothing to enumerate, and enumerating it would mean that adding
      #     a spell to the game required touching every such character.
      #
      # Which one a source uses is in config already - a class whose magic_stats grant a
      # `spellbook` or a `repertoire` enumerates, and one that grants only `spells_per_day` casts
      # by rule. Reading it from there rather than naming classes in code is what keeps a new
      # class, or a new spell, from needing anything special.

      ENUMERATING_KEYS = %w(spellbook repertoire).freeze

      def self.access(source)
        enumerated?(source) ? 'enumerated' : 'tradition'
      end

      # Does this class or archetype have to acquire its spells one at a time?
      def self.enumerated?(source)
        return false if source.blank?

        blocks = magic_stat_blocks(source)

        blocks.any? { |block| ENUMERATING_KEYS.any? { |key| block.key?(key) } }
      end

      # Every magic_stats block a source's config carries: at chargen, at each level, and - for
      # a class - in each of its specialties. A Witch's tradition comes from their patron rather
      # than from the class, so a source's magic is not all in one place, and a class whose
      # enumerated list arrived only through a specialty would otherwise be misread as casting
      # by rule. None currently does; it is one line to be right about anyway.
      def self.magic_stat_blocks(source)
        sections = [
          Global.read_config('pf2e_class', source),
          Global.read_config('pf2e_archetype', source)
        ].compact.select { |info| info.is_a?(Hash) }

        specialties = Array((Global.read_config('pf2e_specialty', source) || {}).values)
          .select { |info| info.is_a?(Hash) }

        (sections + specialties).flat_map { |info| blocks_in(info) }
          .compact.select { |block| block.is_a?(Hash) }
      end

      def self.blocks_in(info)
        [ (info['chargen'] || {})['magic_stats'], (info['initial_dedication'] || {})['magic_stats'] ] +
          (info['advance'] || {}).values.map { |entry| (entry || {})['magic_stats'] }
      end

      # Records what a class or archetype casts at. Its category - prepared or spontaneous -
      # comes from config rather than being passed in, so a caller cannot get it wrong.
      def self.grant_casting!(char, source, tradition: nil, proficiency: nil, ability: nil)
        category = Pf2emagic.get_caster_type(source)

        return nil unless category

        existing = stored(char).find { |e| e['name'].to_s.casecmp?(source.to_s) && e['category'] == category } || {}

        store!(char,
          'name' => source,
          'source_type' => source.to_s.downcase.include?('archetype') ? 'archetype' : 'class',
          'category' => category,
          'tradition' => tradition || existing['tradition'],
          'proficiency' => proficiency || existing['proficiency'],
          'ability' => ability || existing['ability'])
      end

      # ------------------------------------------------------------------------------
      # Known spells, for the level ladder
      # ------------------------------------------------------------------------------
      #
      # Only enumerated sources have anything here. A Cleric prepares from the whole divine list,
      # so there is nothing to record and nothing a rollback could take away - which is the
      # second axis paying for itself.

      # Every enumerated source's known spells, as source => rank => [ spells ]. What
      # Ledger.commit_level_up! diffs to work out which spells were learned at a level.
      def self.known_lists(char)
        magic = char.magic

        return {} unless magic

        for_magic(magic).each_with_object({}) do |entry, lists|
          next unless [ 'class', 'archetype' ].include?(entry['source_type'])
          next unless enumerated?(entry['name'])

          known = (entry['known'] || {}).each_with_object({}) do |(rank, spells), by_rank|
            kept = Array(spells).reject { |spell| spell.to_s.casecmp?(OPEN) }

            by_rank[rank.to_s] = kept unless kept.empty?
          end

          lists[entry['name']] = known unless known.empty?
        end
      end

      # Writes a source's known spells back, into whichever list its casting mode keeps them in.
      # Called by the materialiser, so the ledger is what decides what a character knows.
      def self.set_known!(char, source, lists)
        magic = char.magic

        return unless magic

        attr = Pf2emagic.get_caster_type(source) == 'spontaneous' ? :repertoire : :spellbook
        held = magic.send(attr) || {}

        # An 'open' marker is a pick the player has not made yet and is not something the ledger
        # knows about, so it is carried over rather than folded away.
        pending = (held[source] || {}).each_with_object({}) do |(rank, spells), open|
          markers = Array(spells).select { |spell| spell.to_s.casecmp?(OPEN) }

          open[rank.to_s] = markers unless markers.empty?
        end

        rebuilt = (lists.keys + pending.keys).uniq.each_with_object({}) do |rank, by_rank|
          by_rank[rank] = Array(lists[rank]) + Array(pending[rank])
        end

        magic.update(attr => held.merge(source => rebuilt))
      end

      # ------------------------------------------------------------------------------
      # Focus spells
      # ------------------------------------------------------------------------------
      #
      # One entry per focus type *per granting source*, which is the difference that matters:
      # PF2e shares one focus pool across every source but casts each source's spells at that
      # source's own DC. A single bucket keyed by focus type could hold the spells but not say
      # whose they were, so two sources of one type - a feat granting devotion spells to a
      # non-Champion, say - had nowhere to go.
      #
      # Casting still wants the merged list for a type, so that is what `focus_spells` and
      # `focus_cantrips` give; `focus_entries` is there for when the source matters.

      def self.focus_entries(magic, type = nil)
        found = for_magic(magic).select { |e| e['category'] == FOCUS }

        type.nil? ? found : found.select { |e| e['name'].to_s.casecmp?(type.to_s) }
      end

      def self.focus_types(magic)
        focus_entries(magic).map { |e| e['name'] }.compact.uniq
      end

      def self.focus?(magic)
        !focus_entries(magic).empty?
      end

      # Every focus spell of a type, across the sources that granted them.
      def self.focus_spells(magic, type)
        focus_entries(magic, type).flat_map { |e| Array((e['known'] || {})['spell']) }.uniq
      end

      def self.focus_cantrips(magic, type)
        focus_entries(magic, type).flat_map { |e| Array((e['known'] || {})['cantrip']) }.uniq
      end

      # Everything focus, of either kind, for a prerequisite that only asks whether they hold one.
      def self.all_focus(magic)
        focus_entries(magic).flat_map { |e| Array((e['known'] || {}).values).flatten }.compact.uniq
      end

      # Records focus spells or cantrips for a type, attributed to the source that granted them.
      def self.grant_focus!(char, type, spells, kind:, granted_by: nil, granted_at: nil, tradition: nil, ability: nil)
        wanted = Array(spells).compact.map(&:to_s).reject(&:empty?)

        return nil if wanted.empty?

        existing = stored(char).find do |e|
          e['category'] == FOCUS && e['name'].to_s.casecmp?(type.to_s) && e['granted_by'].to_s == granted_by.to_s
        end

        known = (existing || {})['known'] || {}
        known = known.merge(kind.to_s => (Array(known[kind.to_s]) + wanted).uniq)

        store!(char,
          'name' => type,
          'source_type' => FOCUS,
          'category' => FOCUS,
          'granted_by' => granted_by,
          'granted_at' => granted_at || (existing || {})['granted_at'],
          'tradition' => tradition || (existing || {})['tradition'],
          'ability' => ability || (existing || {})['ability'],
          'known' => known)
      end

      # How a focus entry names itself: "Domain Healing, lvl 3" for a cleric's domain spell,
      # "devotion" for a champion whose class simply grants them. Built from what was recorded
      # when the spell was granted rather than worked back out of the deity's domain list and the
      # level table.
      def self.focus_label(entry)
        source = entry['granted_by'].to_s
        level = entry['granted_at']
        name = source.empty? ? entry['name'].to_s : source

        level.to_i > 0 ? "#{name}, lvl #{level.to_i}" : name
      end

      # Takes a focus spell or cantrip away, wherever it was granted from.
      def self.revoke_focus!(char, type, spell, kind:)
        rows(char, FOCUS).each do |row|
          next unless row.name.to_s.casecmp?(type.to_s)

          known = row.known || {}
          held = Array(known[kind.to_s])
          kept = held.reject { |s| s.to_s.casecmp?(spell.to_s) }

          next if kept.size == held.size

          row.update(:known => known.merge(kind.to_s => kept))
        end
      end

      # ------------------------------------------------------------------------------
      # Innate spells
      # ------------------------------------------------------------------------------
      #
      # Stored as a list of grants, each { 'name', 'level', 'tradition', 'cast_stat' }, because
      # two sources can grant the same spell with different ranks or traditions and a map keyed
      # by name loses one of them.

      def self.innate_grants(magic)
        return [] unless magic

        Array(magic.innate_spells).select { |grant| grant.is_a?(Hash) }
      end

      def self.innate?(magic)
        !innate_grants(magic).empty?
      end

      # Every grant of a spell by that name. More than one is legitimate - the same spell from
      # two sources, at each source's own rank and tradition.
      def self.innate_for(magic, spell)
        innate_grants(magic).select { |grant| grant['name'].to_s.casecmp?(spell.to_s) }
      end

      def self.knows_innate?(magic, spell)
        !innate_for(magic, spell).empty?
      end

      # Grants still waiting for the player to choose the spell.
      def self.pending_innate(magic)
        innate_for(magic, 'open')
      end

      def self.innate_traditions(magic)
        innate_grants(magic).map { |grant| grant['tradition'].to_s.downcase }.uniq.reject(&:empty?)
      end

      # Innate spells that take a slot - cantrips are cast at will.
      def self.innate_ranked(magic)
        innate_grants(magic).reject do |grant|
          rank = grant['level'].to_s

          rank.casecmp?('cantrip') || rank.to_i.zero?
        end
      end

      # Every source that has a signature spell recorded, for the display.
      def self.with_signatures(magic)
        for_magic(magic).select { |e| (e['signature'] || {}).any? { |_rank, spells| !Array(spells).empty? } }
      end

      def self.entry(values)
        FIELDS.merge(values)
      end

      def self.stringify(magic)
        (magic || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      end
    end
  end
end
