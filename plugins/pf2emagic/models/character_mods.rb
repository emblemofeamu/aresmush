module AresMUSH
  class Character

    # A character casts from as many sources as PF2e gives them - a class, an archetype, a focus
    # tradition, innate grants, an item. Each is a row. Read them through Pf2emagic::Entries.
    collection :spellcasting_entries, "AresMUSH::Pf2eSpellcastingEntry"

  end
end
