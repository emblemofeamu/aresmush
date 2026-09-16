module AresMUSH
  module Pf2e

    class PF2AdvanceOptionCmd
      include CommandHandler

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

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def check_known_type
        return nil if self.type.nil?
        return nil if [ 'feat', 'charclass' ].include?(self.type)

        return t('pf2e.bad_element', :invalid => self.type, :options => 'feat, charclass')
      end

      def handle
        # A class feature option is only ever reachable bare or under charclass/.
        if self.type != 'feat' && class_option_feature
          handle_class_option
          return
        end

        found = Pf2e.validate_feat_choice(enactor, self.option, self.type)

        if found.is_a?(Array)
          handle_feat_choice(found[0], found[1])
          return
        end

        client.emit_failure found
      end

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

        messages = Pf2e.stage_feat_choice(enactor, name, block, matched, client)

        client.emit_success t('pf2e.choice_resolved', :choice => name, :value => matched)
        messages.each { |msg| client.emit_ooc msg }
      end

      # The pending class feature matching self.option, or nil.
      def class_option_feature
        return @class_option_feature if defined?(@class_option_feature)

        @class_option_feature = pending_features.keys.find { |f| f.to_s.casecmp?(self.option.to_s) }
      end

      # The feature list this level left open, wherever it was put.
      def pending_features
        to_assign = enactor.pf2_to_assign || {}
        slot = Pf2e::Advancement::Options::SLOTS.find { |key| to_assign[key].is_a?(Hash) }

        slot ? to_assign[slot] : {}
      end

      def handle_class_option
        feature = class_option_feature

        # No value given, so tell them what they can pick.
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
