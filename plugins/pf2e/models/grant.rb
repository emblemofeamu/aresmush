module AresMUSH

  # One immutable entry in a character's grant ledger.
  #
  # Rows are never edited and never deleted. An undo sets reverted_by; a redo clears it.
  # payload holds the *resolved outcome* ("Arcana to expert"), never a recipe to re-derive
  # from config, so editing game/config/pf2e_*.yml cannot rewrite an existing character's
  # history.
  class Pf2eGrant < Ohm::Model
    include ObjectModel

    attribute :seq, :type => DataType::Integer
    index :seq

    # Groups the grants written by one action: a level-up, a chargen stage, a staff edit.
    # Undo and redo work on a whole txn, never on a single grant.
    attribute :txn
    index :txn

    # One of AresMUSH::Pf2e::Ledger::KINDS.
    attribute :kind
    index :kind

    attribute :payload, :type => DataType::Hash, :default => {}

    # chargen | level_up | boon | staff | background | class_feature | archetype | imported
    attribute :source_type
    index :source_type

    # Feat name, boon id, job number, staff name - whatever names the cause.
    attribute :source_ref

    # The level from which this grant applies. nil or 0 means global: it survives any
    # rollback, which is how a boon awarded outside the level ladder stays awarded.
    attribute :effective_level, :type => DataType::Integer
    index :effective_level

    attribute :granted_at, :type => DataType::Time
    attribute :granted_by

    # The txn id that undid this grant, or nil while it is live.
    attribute :reverted_by
    index :reverted_by

    reference :character, "AresMUSH::Character"

    def live?
      self.reverted_by.blank?
    end

    # The plain-hash form the pure fold consumes.
    def to_row
      {
        'id' => self.id,
        'seq' => self.seq,
        'txn' => self.txn,
        'kind' => self.kind,
        'payload' => self.payload,
        'source_type' => self.source_type,
        'source_ref' => self.source_ref,
        'effective_level' => self.effective_level,
        'granted_at' => self.granted_at,
        'granted_by' => self.granted_by,
        'reverted_by' => self.reverted_by
      }
    end
  end
end
