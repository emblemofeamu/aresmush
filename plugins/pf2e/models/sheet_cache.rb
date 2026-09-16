module AresMUSH

  # A materialised fold, kept only as a cache.
  #
  # Nothing in the game is allowed to treat this as the record of truth: it is valid only
  # for the exact (level, head_seq) pair it was built from, and throwing the whole table
  # away costs nothing but a refold.
  class Pf2eSheetCache < Ohm::Model
    include ObjectModel

    attribute :level, :type => DataType::Integer
    index :level

    # The highest grant seq that existed when this fold was built. If the ledger has moved,
    # the cache is stale - no other invalidation logic is needed.
    attribute :head_seq, :type => DataType::Integer

    attribute :sheet, :type => DataType::Hash, :default => {}
    attribute :built_at, :type => DataType::Time

    reference :character, "AresMUSH::Character"

    def to_row
      { 'level' => self.level, 'head_seq' => self.head_seq, 'sheet' => self.sheet }
    end
  end
end
