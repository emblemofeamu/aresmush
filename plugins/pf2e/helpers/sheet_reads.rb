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
    #
    # `during` holds a memo for everyone a whole command asks about - a Strike reads its attacker's and
    # its target's sheets a thousand times over - and forgets everything the moment anything is written
    # to the database (`written!`), so nothing read before a write answers after it.
    module SheetReads

      KEY = :pf2e_sheet_reads

      def self.holding(char)
        previous = Thread.current[KEY]
        # A memo already open for them is shared, so a write inside empties it for the caller too.
        held = (previous || {}).merge(char.object_id => (previous || {})[char.object_id] || {})
        held.default_proc = previous&.default_proc
        Thread.current[KEY] = held

        yield
      ensure
        Thread.current[KEY] = previous
      end

      # A memo for anyone asked about, for the length of the block. One already open is kept.
      def self.during
        return yield if Thread.current[KEY]&.default_proc

        previous = Thread.current[KEY]
        Thread.current[KEY] = Hash.new { |memo, id| memo[id] = {} }.merge(previous || {})

        yield
      ensure
        Thread.current[KEY] = previous unless previous&.default_proc
      end

      # Something was written: everything held may be out of date. The memos are emptied in place,
      # because a sweep inside a command shares them with it.
      def self.written!
        Thread.current[KEY]&.each_value(&:clear)
      end

      # What only reads. Anything else - Ohm's saves are scripts - is taken as a write.
      READS = %w{GET MGET HGET HMGET HGETALL HEXISTS HLEN HKEYS SMEMBERS SISMEMBER SCARD SINTER SUNION SDIFF
                 EXISTS TYPE STRLEN TTL ZRANGE ZRANGEBYSCORE ZREVRANGE ZREVRANGEBYSCORE ZCARD ZSCORE ZRANK
                 LRANGE LLEN LINDEX SCAN SSCAN HSCAN KEYS PING ECHO SELECT AUTH}.freeze

      def self.write?(command)
        !READS.include?(command.to_s.upcase)
      end

      # Every command the database is sent passes here, so a write is seen however it was made.
      module Watch
        def write(args)
          SheetReads.written! if Thread.current[SheetReads::KEY] && SheetReads.write?(args.first)
          super
        end
      end

      # The character's rows for `collection`, from the memo when one is open.
      def self.rows(char, collection)
        memo(char, collection) { char.send(collection).to_a }
      end

      # Anything else worth reading once. Assembling a figure asks which feats, items and conditions
      # carry effects, which is a config lookup per feat; a sheet showing twenty figures would ask
      # twenty times.
      def self.memo(char, key)
        held = (Thread.current[KEY] || {})[char.object_id]

        return yield unless held

        held.key?(key) ? held[key] : held[key] = yield
      end
    end
  end
end

Redic::Client.prepend(AresMUSH::Pf2e::SheetReads::Watch)
