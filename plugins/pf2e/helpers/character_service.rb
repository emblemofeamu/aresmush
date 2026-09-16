module AresMUSH
  module Pf2e

    # The single door every character change goes through.
    #
    #   CharacterService.call(state, :set_base_info, 'element' => 'ancestry', 'value' => 'Khazad')
    #   # => Ok(state:, grants:, messages:) | Err(code:, key:, args:)
    #
    # Handlers are pure: state and args in, an Outcome out. Nothing here reads a character,
    # a client or Global - which is why a whole chargen can be run as data in a spec with no
    # Redis anywhere near it.
    module CharacterService

      # Resolved lazily so the registry can name a core before it exists.
      ACTIONS = {
        :set_base_info => lambda { |state, args| Chargen::BaseInfo.set(state, args) },
        :set_boost     => lambda { |state, args| Chargen::Boosts.set(state, args) },
        :unset_boost   => lambda { |state, args| Chargen::Boosts.unset(state, args) },
        :learn_language => lambda { |state, args| Chargen::Languages.learn(state, args) },
        :forget_language => lambda { |state, args| Chargen::Languages.forget(state, args) },
        :train_skill   => lambda { |state, args| Chargen::Skills.train(state, args) },
        :untrain_skill => lambda { |state, args| Chargen::Skills.untrain(state, args) },
        :commit_stage  => lambda { |state, args| Chargen::Lifecycle.commit(state, args) },
        :restore_stage => lambda { |state, args| Chargen::Lifecycle.restore(state, args) },
        :reset_chargen => lambda { |state, args| Chargen::Lifecycle.reset(state, args) },

        # Advancement. These write the draft in state['advancement']; it becomes one
        # level_up transaction at advance/done, through Ledger.commit_level_up!.
        :advance_language => lambda { |state, args| Advancement::Languages.pick(state, args) },
        :advance_raise => lambda { |state, args| Advancement::Raises.set(state, args) },
        :advance_option => lambda { |state, args| Advancement::Options.choose(state, args) },
        :reset_advancement => lambda { |state, args| Advancement::Lifecycle.reset(state, args) }
      }.freeze

      def self.actions
        ACTIONS.keys
      end

      def self.call(state, action, args = {})
        handler = ACTIONS[action]

        return Err.new(:unknown_action, 'pf2e.unknown_action', 'action' => action.to_s) unless handler

        outcome = handler.call(state, args || {})
        outcome.failed_action = action if outcome.err? && outcome.failed_action.nil?
        outcome
      end

      # Runs a list of [action, args] pairs, handing each the state the last one produced.
      # This is how a whole chargen is expressed as data - and how the walkthrough specs
      # assert on a finished sheet without touching a command or a database.
      def self.chain(state, steps)
        steps.reduce(Ok.new(:state => state)) do |outcome, (action, args)|
          outcome.and_then { |current| call(current, action, args) }
        end
      end
    end
  end
end
