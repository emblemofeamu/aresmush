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

        to_assign = enactor.pf2_to_assign || {}
        feature_list = to_assign['class option'] || to_assign['charclass'] || to_assign['charclass option']

        @class_option_feature = if feature_list.is_a?(Hash)
          feature_list.keys.find { |f| f.to_s.casecmp?(self.option.to_s) }
        else
          nil
        end
      end

      def handle_class_option
        to_assign = enactor.pf2_to_assign || {}
        advancement = enactor.pf2_advancement || {}

        feature_list = to_assign['class option'] || to_assign['charclass'] || to_assign['charclass option']

        unless feature_list
          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        feature = class_option_feature

        unless feature
          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        options = feature_list[feature]
        option_list = if options.is_a?(Hash)
          options.keys
        else
          Array(options).map { |opt| opt.is_a?(Array) ? opt.first : opt }
        end

        # No value given, so tell them what they can pick.
        if self.value.blank?
          client.emit t('pf2e.choice_options', :choice => feature, :options => option_list.sort.join(", "))
          return
        end

        matched_option = option_list.find { |opt| opt.to_s.casecmp?(self.value) }

        unless matched_option
          client.emit_failure t('pf2e.bad_option', :element => feature, :options => option_list.join(", "))
          return
        end

        unless Pf2e.valid_class_option?(enactor, feature, matched_option)
          client.emit_failure t('pf2e.bad_option', :element => feature, :options => option_list.join(", "))
          return
        end

        feature_list[feature] = matched_option
        to_assign['class option'] = feature_list
        advancement['charclass_feature option'] = feature_list

        enactor.update(pf2_to_assign: to_assign)
        enactor.update(pf2_advancement: advancement)

        client.emit_success t('pf2e.adv_option_selected', :option => matched_option, :feature => feature)
      end

    end
  end
end
