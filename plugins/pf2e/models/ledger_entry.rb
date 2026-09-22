module AresMUSH

  # One XP or money transaction.
  #
  # Kept in its own model, in the same idiom as SceneLog, so the character object stays small:
  # a character with fifty thousand awards is fifty thousand of these, not a fifty-thousand
  # element array that is read and rewritten in full every time one more arrives.
  #
  # **Never read these as a collection.** `char.pf2_ledger_entries.to_a` loads every row and sorts
  # in Ruby, the way every other collection in AresMUSH is read, at about 19 microseconds a row -
  # two seconds at a hundred thousand, on the one reactor thread the whole game shares. Go through
  # Pf2e::Audit, which pages against a sorted
  # set index and loads only the rows it returns.
  class Pf2eLedgerEntry < Ohm::Model
    include ObjectModel

    reference :character, "AresMUSH::Character"

    attribute :currency
    attribute :amount, :type => DataType::Integer
    attribute :balance_after, :type => DataType::Integer
    attribute :at, :type => DataType::Integer
    attribute :by
    attribute :reason
    attribute :ref

    index :currency
  end
end
