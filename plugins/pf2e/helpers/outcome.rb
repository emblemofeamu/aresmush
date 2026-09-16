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

      attr_reader :state, :grants, :messages

      def initialize(state:, grants: [], messages: [])
        @state = state
        @grants = grants
        @messages = messages
      end

      def ok?
        true
      end

      def err?
        false
      end

      def to_h
        { :state => @state, :grants => @grants, :messages => @messages }
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
          :messages => @messages + nxt.messages
        )
      end

      def with_message(key, args = {})
        Ok.new(:state => @state, :grants => @grants, :messages => @messages + [ { 'key' => key, 'args' => args } ])
      end

      def with_grant(kind, payload = {}, overrides = {})
        grant = { 'kind' => kind, 'payload' => payload }.merge(overrides)
        Ok.new(:state => @state, :grants => @grants + [ grant ], :messages => @messages)
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

      def to_h
        { :code => @code, :key => @key, :args => @args }
      end

      def and_then
        self
      end
    end
  end
end
