module AresMUSH

  # One step of a draft, as the two writes that move between the character before it and the
  # character after.
  #
  # `undo` and `redo` are partial snapshots: only the slices the step changed, each holding the
  # value from that side of it. Storing values rather than operations is what keeps the journal
  # independent of draft keys and grant kinds - a step that touches something the journal has never
  # heard of is recorded correctly anyway.
  #
  # A step is discarded when the draft reaches its commit boundary, because from then on the grant
  # ledger is the record.
  class Pf2eDraftStep < Ohm::Model
    include ObjectModel

    attribute :seq, :type => DataType::Integer
    index :seq

    # What the player typed, for the message undo speaks.
    attribute :action

    # A digest of the whole draft as this step left it, so a change nothing recorded can be told
    # from one the journal knows about.
    attribute :shape

    # The whole draft as this step left it, kept on the newest step only. The next step reads it
    # instead of reading the character again: a snapshot walks every skill and ability row, and
    # taking one per command rather than two halves what a draft costs.
    attribute :shape_data, :type => DataType::Hash, :default => {}

    attribute :undo, :type => DataType::Hash, :default => {}
    attribute :redo_to, :type => DataType::Hash, :default => {}

    # Set while the step is undone and waiting to be redone. A new step clears the undone tail.
    attribute :undone, :type => DataType::Boolean
    index :undone

    attribute :at, :type => DataType::Time

    reference :character, "AresMUSH::Character"

    def live?
      !self.undone
    end
  end
end
