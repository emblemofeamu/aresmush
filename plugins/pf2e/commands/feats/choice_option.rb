module AresMUSH
  module Pf2e

    # Resolves a choice a feat or a class feature carries.
    #
    # `cg/option` and `advance/option` are this one command. They differ in one thing: a choice made
    # during a level-up is staged for `advance/done`, and one made during chargen applies straight
    # away, because chargen's boundary is approval and there is nothing later to stage it for.
    #
    # Both accept `<choice>=<value>`, or `feat/<choice>` and `charclass/<feature>` where a name is
    # ambiguous. Without a value, they describe what may be picked.
    class PF2ChoiceOptionCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      TYPES = [ 'feat', 'charclass' ].freeze

      attr_accessor :type, :option, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        left = trim_arg(args.arg1)
        self.value = trim_arg(args.arg2)

        if left && left.include?("/")
          parts = left.split("/", 2)
          self.type = downcase_arg(parts[0])
          self.option = trim_arg(parts[1])
        else
          self.type = nil
          self.option = left
        end
      end

      def required_args
        [ self.option ]
      end

      def check_known_type
        return nil if self.type.nil? || TYPES.include?(self.type)

        t('pf2e.bad_element', :invalid => self.type, :options => TYPES.join(', '))
      end

      # A choice belongs to an open draft either side of approval, which is what Ledger.drafting?
      # answers: chargen before approval, or an advancement between `advance` and `advance/done`.
      def check_drafting
        return nil if Pf2e::Ledger.drafting?(enactor)
        return t('chargen.not_started') if !enactor.is_approved? && !Pf2e.in_chargen?(enactor)

        t('pf2e.not_advancing')
      end

      def handle
        # A class feature option is only ever reachable bare or under charclass/.
        return handle_class_option if self.type != 'feat' && class_option_feature

        found = Pf2e.validate_feat_choice(enactor, self.option, self.type)

        return client.emit_failure(found) unless found.is_a?(Array)

        handle_feat_choice(found[0], found[1])
      end

      private

      def handle_feat_choice(name, block)
        if self.value.blank?
          client.emit Pf2e.describe_choice_options(enactor, name, block)
          return
        end

        matched = Pf2e.match_choice_option(enactor, name, block, self.value)

        unless matched
          client.emit_failure Pf2e.describe_bad_choice_option(enactor, name, block)
          return
        end

        # Staged while a level is open, applied now while chargen is: the two have different
        # boundaries, and this is the only place the difference shows.
        messages = if enactor.advancing
          Pf2e.stage_feat_choice(enactor, name, block, matched, client)
        else
          Pf2e.apply_feat_choice(enactor, name, block, matched, client)
        end

        client.emit_success t('pf2e.choice_resolved', :choice => name, :value => matched)
        messages.each { |msg| client.emit_ooc msg }
      end

      # The pending class feature matching self.option, or nil.
      def class_option_feature
        return @class_option_feature if defined?(@class_option_feature)

        @class_option_feature = pending_features.keys.find { |f| f.to_s.casecmp?(self.option.to_s) }
      end

      # The feature list a level left open, wherever it was put.
      def pending_features
        to_assign = enactor.pf2_to_assign || {}
        slot = Pf2e::Advancement::Options::SLOTS.find { |key| to_assign[key].is_a?(Hash) }

        slot ? to_assign[slot] : {}
      end

      def handle_class_option
        feature = class_option_feature

        if self.value.blank?
          options = Pf2e::Advancement::Options.option_list(pending_features[feature])

          client.emit t('pf2e.choice_options', :choice => feature, :options => options.sort.join(", "))
          return
        end

        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :advance_option, 'feature' => feature, 'value' => self.value)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)
        Pf2e::CharState.emit_messages!(client, outcome)
      end
    end
  end
end
