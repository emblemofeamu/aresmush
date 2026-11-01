require 'json'

module AresMUSH
  module Pf2e

    # An encounter's log, as a list of its own beside the encounter's record: a line is pushed onto the
    # end, and the record, which every encounter command reads, does not carry it. Each line is
    # `[ time, message, notice, notice details, line ]` with nothing after its last field
    # (`PF2Encounter.send_to_encounter`).
    #
    # An encounter logged before kept its lines in its record's `messages`; they are read ahead of the
    # list's.
    module EncounterLog

      def self.key(encounter)
        PF2Encounter.key[encounter.id][:log].to_s
      end

      def self.add(encounter, line)
        Ohm.redis.call('RPUSH', key(encounter), JSON.dump(line))
      end

      # Every line, or the last `last` of them.
      def self.lines(encounter, last = nil)
        kept = Array(Ohm.redis.call('HGET', PF2Encounter.key[encounter.id].to_s, 'messages')&.then { |raw| JSON.parse(raw) })
        listed = Ohm.redis.call('LRANGE', key(encounter), last ? -last : 0, -1).map { |raw| JSON.parse(raw) }
        all = kept + listed

        last ? all.last(last) : all
      end

      def self.delete(encounter)
        Ohm.redis.call('DEL', key(encounter))
      end
    end
  end
end
