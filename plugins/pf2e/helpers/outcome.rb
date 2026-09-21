module AresMUSH
  module Pf2e

    # The result of any character transformation, as a discriminated union.
    #
    #   case CharacterService.call(state, :set_base_info, args)
    #   in Ok(state:, grants:)  then ...
    #   in Err(code:, key:)     then ...
    #   end
    #
    # Ok carries the *new state*: a transformation is data in, data out, and nothing is
    # saved until the shell decides to. Err carries a machine-readable code (for callers and
    # tests) alongside the locale key and args (for players) - so a spec asserts on :locked
    # rather than on a rendered English sentence.
    module Outcome

      # Ruby's pattern matching reads these, which is what makes `in Ok(state:)` work.
      def deconstruct_keys(_keys)
        to_h
      end
    end

    class Ok
      include Outcome

      attr_reader :state, :grants, :messages, :revocations

      def initialize(state:, grants: [], messages: [], revocations: [])
        @state = state
        @grants = grants
        @messages = messages
        @revocations = revocations
      end

      def ok?
        true
      end

      def err?
        false
      end

      def to_h
        { :state => @state, :grants => @grants, :messages => @messages, :revocations => @revocations }
      end

      # Chains the next transformation onto this one, handing it the new state and
      # accumulating grants and messages. An Err anywhere in the chain wins and the rest of
      # the chain never runs.
      def and_then
        nxt = yield @state

        return nxt if nxt.err?

        Ok.new(
          :state => nxt.state,
          :grants => @grants + nxt.grants,
          :messages => @messages + nxt.messages,
          :revocations => @revocations + nxt.revocations
        )
      end

      def with_message(key, args = {})
        Ok.new(:state => @state, :grants => @grants, :messages => @messages + [ { 'key' => key, 'args' => args } ], :revocations => @revocations)
      end

      # An aside rather than the headline - the shell speaks it OOC.
      def with_ooc(key, args = {})
        Ok.new(:state => @state, :grants => @grants, :messages => @messages + [ { 'key' => key, 'args' => args, 'type' => 'ooc' } ], :revocations => @revocations)
      end

      def with_grant(kind, payload = {}, overrides = {})
        grant = { 'kind' => kind, 'payload' => payload }.merge(overrides)
        Ok.new(:state => @state, :grants => @grants + [ grant ], :messages => @messages, :revocations => @revocations)
      end

      # Asks for an earlier grant to be undone - how a chargen pick is taken back without
      # deleting anything. The shell resolves it against the ledger.
      def with_revocation(kind, match = {})
        revocation = { 'kind' => kind, 'match' => match }
        Ok.new(:state => @state, :grants => @grants, :messages => @messages, :revocations => @revocations + [ revocation ])
      end
    end

    class Err
      include Outcome

      attr_reader :code, :key, :args
      attr_accessor :failed_action

      # code: a symbol the code and the specs branch on.
      # key:  the locale key the player sees, rendered by the shell, never here.
      def initialize(code, key = nil, args = {})
        @code = code
        @key = key || "pf2e.#{code}"
        @args = (args || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      end

      def ok?
        false
      end

      def err?
        true
      end

      def state
        nil
      end

      def grants
        []
      end

      def messages
        []
      end

      def revocations
        []
      end

      def to_h
        { :code => @code, :key => @key, :args => @args }
      end

      def and_then
        self
      end

      # An Err absorbs the rest of the chain, the same way and_then does, so a core can write
      # `transform(...).with_message(...)` without checking first.
      def with_message(_key, _args = {})
        self
      end

      def with_ooc(_key, _args = {})
        self
      end
    end
  end
end
