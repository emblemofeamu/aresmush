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
        'restrictions' => {}
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
        # Focus spells, keyed by focus type rather than by the source that granted them -
        # 'devotion' for a Champion, 'revelation' for an Oracle, 'qi' for a Monk.
        {
          'kind' => 'focus',
          'entries' => lambda { |magic, _caster_types|
            spells = magic['focus_spells'] || {}
            cantrips = magic['focus_cantrips'] || {}

            (spells.keys + cantrips.keys).uniq.map do |type|
              Entries.entry(
                'name' => type,
                'source_type' => FOCUS,
                'category' => FOCUS,
                'known' => {
                  'cantrip' => Array(cantrips[type]),
                  'spell' => Array(spells[type])
                }.reject { |_k, v| v.empty? }
              )
            end
          }
        },
        # Innate spells, keyed by spell name, each carrying the tradition and ability it is cast
        # with. Grouped by those, because they are the closest thing the old shape records to a
        # source - two grants that agree on both are indistinguishable.
        {
          'kind' => 'innate',
          'entries' => lambda { |magic, _caster_types|
            by_source = (magic['innate_spells'] || {}).each_with_object({}) do |(spell, info), grouped|
              next unless info.is_a?(Hash)

              key = [ info['tradition'], info['cast_stat'] ]
              rank = info['level'].to_s
              known = (grouped[key] ||= {})

              known[rank] = Array(known[rank]) + [ spell ]
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

      # The same, for a live magic object.
      def self.for_magic(magic)
        return [] unless magic

        attributes = ATTRIBUTES.each_with_object({}) { |attr, h| h[attr] = magic.send(attr) }
        types = (attributes['tradition'] || {}).keys.each_with_object({}) do |source, h|
          h[source] = Pf2emagic.get_caster_type(source)
        end

        derive(attributes, :caster_types => types)
      end

      # What derive reads. Listed so for_magic does not depend on the model having exactly
      # these and nothing else.
      ATTRIBUTES = %w(
        tradition spell_abil spells_per_day spellbook repertoire signature_spells
        restricted_spellbook focus_spells focus_cantrips innate_spells
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
