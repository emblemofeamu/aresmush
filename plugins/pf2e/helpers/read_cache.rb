module AresMUSH
  module Pf2e

    # What the database said, held for the length of a command: a read it was already asked is answered
    # from its reply, until anything is written.
    #
    # A command reads the same records over and over - the encounter, each combatant, each one's effects
    # and gear - because Ohm loads a record afresh each time it is asked for, and the code asks for one
    # afresh whenever it wants it as it stands. Each read is a round trip to the database, and those
    # round trips are most of what a command costs.
    #
    # Every command the database is sent passes through the client here. A write - anything but a read,
    # by this thread or any other - moves `generation` on, and a cache held at an earlier generation is
    # emptied before it answers anything. Each reader is given its own copy of a reply, so nothing one
    # does to what it read reaches another.
    module ReadCache

      KEY = :pf2e_read_cache

      @generation = 0
      @lock = Mutex.new

      # What only reads. Anything else - Ohm's saves are scripts - is taken as a write.
      READS = %w{GET MGET HGET HMGET HGETALL HEXISTS HLEN HKEYS SMEMBERS SISMEMBER SCARD SINTER SUNION SDIFF
                 EXISTS TYPE STRLEN TTL ZRANGE ZRANGEBYSCORE ZREVRANGE ZREVRANGEBYSCORE ZCARD ZSCORE ZRANK
                 LRANGE LLEN LINDEX SCAN SSCAN HSCAN KEYS PING ECHO SELECT AUTH}.freeze

      # The reads whose reply is the same until something is written.
      HELD = (READS - %w{TTL SCAN SSCAN HSCAN KEYS PING ECHO SELECT AUTH}).freeze

      class << self
        attr_reader :generation
      end

      def self.written!
        @lock.synchronize { @generation += 1 }
      end

      # Ohm's find by more than one index runs Stal's script, which only reads.
      def self.finding?(args)
        args.first.to_s.casecmp?('EVALSHA') && args[1].to_s == Stal::SHA
      end

      def self.write?(args)
        !finding?(args) && !READS.include?(args.first.to_s.upcase)
      end

      def self.held?(args)
        finding?(args) || HELD.include?(args.first.to_s.upcase)
      end

      def self.during
        return yield if Thread.current[KEY]

        begin
          Thread.current[KEY] = { 'at' => generation, 'replies' => {} }
          yield
        ensure
          Thread.current[KEY] = nil
        end
      end

      # The replies held, emptied first if anything has been written since they were.
      def self.replies
        held = Thread.current[KEY]

        return nil unless held

        unless held['at'] == generation
          held['replies'].clear
          held['at'] = generation
        end

        held['replies']
      end

      def self.copy(reply)
        case reply
        when Array then reply.map { |one| copy(one) }
        when String then reply.dup
        else reply
        end
      end

      # A reply kept, unless something was written while it was on its way.
      def self.keep(asked, reply, at)
        store = replies

        store[asked] = copy(reply) if store && at == generation && !reply.is_a?(RuntimeError)
      end

      def self.asked(args)
        args.map(&:to_s)
      end

      # Every command sent: a write moves the generation on.
      module Sent
        def write(args)
          if ReadCache.write?(args)
            ReadCache.written!
            SheetReads.written!
          end

          super
        end
      end

      # A read, from what is held where it can be.
      module Answered
        def call(*args)
          store = ReadCache.replies

          return super unless store && ReadCache.held?(args)

          asked = ReadCache.asked(args)

          return ReadCache.copy(store[asked]) if store.key?(asked)

          at = ReadCache.generation
          reply = super
          ReadCache.keep(asked, reply, at)
          reply
        end

        # Reads queued together, as Ohm fetches a collection's records: answered whole from what is held,
        # or sent whole and held.
        def commit
          store = ReadCache.replies
          queued = buffer.map { |args| ReadCache.asked(args) }

          return super unless store && !queued.empty? && queued.all? { |args| ReadCache.held?(args) }

          if queued.all? { |args| store.key?(args) }
            reset
            return queued.map { |args| ReadCache.copy(store[args]) }
          end

          at = ReadCache.generation
          replies = super
          queued.zip(Array(replies)).each { |args, reply| ReadCache.keep(args, reply, at) }
          replies
        end
      end
    end
  end
end

Redic::Client.prepend(AresMUSH::Pf2e::ReadCache::Sent)
Redic.prepend(AresMUSH::Pf2e::ReadCache::Answered)
