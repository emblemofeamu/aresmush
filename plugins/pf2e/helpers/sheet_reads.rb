module AresMUSH
  module Pf2e

    # Reads a character's skill and ability rows once for the length of a block.
    #
    # Both are Ohm collections, so every lookup is a fresh read of every row. A sweep over the feat
    # catalogue asks for a skill or an attribute once per prerequisite - 584 skill lookups against a
    # level 20 character with 255 skill rows, which cost 956ms of the one reactor thread the whole
    # game shares. Reading each collection once takes that to tens of milliseconds.
    #
    # Scoped to a block and restored afterwards, because the caller usually writes to the sheet
    # immediately after asking - a level-up raises the very skills it just read - and a memo held
    # past the block would answer with what was true before the write.
    #
    # Keyed by object identity: the memo is only valid for the object the block was handed, and not
    # every caller's character responds to `id`. Filled on first use, so a block that asks nothing
    # reads nothing.
    module SheetReads

      KEY = :pf2e_sheet_reads

      def self.holding(char)
        previous = Thread.current[KEY]
        Thread.current[KEY] = (previous || {}).merge(char.object_id => {})

        yield
      ensure
        Thread.current[KEY] = previous
      end

      # The character's rows for `collection`, from the memo when one is open.
      def self.rows(char, collection)
        held = (Thread.current[KEY] || {})[char.object_id]

        return char.send(collection).to_a unless held

        held[collection] ||= char.send(collection).to_a
      end
    end
  end
end
