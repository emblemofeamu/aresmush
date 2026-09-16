module AresMUSH

  # One spellcasting source a character casts from.
  #
  # PF2e lets a character cast from several places at once, each with its own statistics: a
  # class, an archetype's dedication, a focus tradition, innate spells from an ancestry or a
  # heritage, a staff or a wand, rituals. Foundry's PF2e system models each as its own
  # `SpellcastingEntry` item and Pathbuilder exports `spellCasters` as a list of the same thing.
  # This is that row.
  #
  # `PF2Magic`'s eighteen parallel hashes cannot express it, because they have no concept of a
  # source: each attribute invented its own key for which-source - class for most, focus *type*
  # for focus spells, spell *name* for innate - so two sources that agree on that key collide.
  # See docs/plans/2026-09-16-spellcasting-entries.md.
  #
  # Read these through `Pf2emagic::Entries`, never directly, so that the remaining hashes can
  # keep being migrated behind it.
  class Pf2eSpellcastingEntry < Ohm::Model
    include ObjectModel

    reference :character, "AresMUSH::Character"

    # What the player calls it: 'Sorcerer', 'Bard Archetype', 'devotion', 'Staff of Fire'.
    # Not unique on its own - two sources can share a name and still be separate entries, which
    # is the whole point.
    attribute :name

    # Where it came from: class | archetype | focus | innate | item | ritual.
    attribute :source_type

    # How it is cast: prepared | spontaneous | innate | focus | ritual | item. Distinct from
    # source_type because an archetype can be either prepared or spontaneous, and an item can
    # hold spells cast either way.
    attribute :category

    # This entry's own statistics. PF2e casts an innate spell from an ancestry feat at that
    # feat's tradition and ability, not the character's class's - which is why these live on the
    # entry rather than being looked up from the class.
    attribute :tradition
    attribute :ability
    attribute :proficiency

    # rank => how many slots. A prepared caster's slots; a spontaneous caster's casts per day.
    attribute :slots, :type => DataType::Hash, :default => {}

    # rank => [ spells ]. A repertoire for a spontaneous caster, a spellbook for a prepared one,
    # the granted list for innate and focus.
    attribute :known, :type => DataType::Hash, :default => {}

    # rank => [ spells ] actually prepared into this entry's slots today.
    attribute :prepared, :type => DataType::Hash, :default => {}

    # rank => [ spells ] designated signature, for a spontaneous caster.
    attribute :signature, :type => DataType::Hash, :default => {}

    # A curriculum, a bloodline's granted list, an order's spells - whatever narrows what may go
    # in. Shape is the restriction's own business.
    attribute :restrictions, :type => DataType::Hash, :default => {}

    # Charges or per-day uses, for items and for innate spells that are not at-will.
    attribute :uses, :type => DataType::Hash, :default => {}

    # The source that granted it, where that is known and is not the name - the feat behind an
    # innate spell, the archetype behind a focus type. Recording it is what lets two sources of
    # one focus type be told apart.
    attribute :granted_by

    # The level it was granted at. Recorded rather than derived, so a Cleric's domain spell can
    # say "Domain Healing, lvl 3" without anyone having to work out which domain and when from
    # the deity's list and the level table.
    attribute :granted_at, :type => DataType::Integer

    index :source_type
    index :category

    def to_h
      {
        'name' => name,
        'source_type' => source_type,
        'category' => category,
        'tradition' => tradition,
        'ability' => ability,
        'proficiency' => proficiency,
        'slots' => slots || {},
        'known' => known || {},
        'prepared' => prepared || {},
        'signature' => signature || {},
        'restrictions' => restrictions || {},
        'uses' => uses || {},
        'granted_by' => granted_by,
        'granted_at' => granted_at
      }
    end
  end
end
