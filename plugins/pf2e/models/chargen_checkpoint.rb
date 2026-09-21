module AresMUSH

  # A chargen stage as the character stood when it began. `cg/restore` writes one back.
  #
  # Held off the character rather than in an attribute, because the shape carries a row per skill:
  # on the character every command would read and diff it through CharState, and a checkpoint taken
  # at a later stage would carry a copy of the ones taken before it.
  class Pf2eChargenCheckpoint < Ohm::Model
    include ObjectModel

    attribute :name
    index :name

    # A whole DraftSnapshot: the character's attributes, skill rows, ability rows and magic.
    attribute :shape, :type => DataType::Hash, :default => {}

    attribute :at, :type => DataType::Time

    reference :character, "AresMUSH::Character"
  end
end
