module AresMUSH
  module Pf2e

    class PF2ChargenOptionCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :type, :choice, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        left = trim_arg(args.arg1)
        self.value = trim_arg(args.arg2)

        if left && left.include?("/")
          parts = left.split("/", 2)
          self.type = downcase_arg(parts[0])
          self.choice = trim_arg(parts[1])
        else
          self.type = nil
          self.choice = left
        end
      end

      def required_args
        [ self.choice ]
      end

      def check_known_type
        return nil if self.type.nil?
        return nil if [ 'feat', 'charclass' ].include?(self.type)

        return t('pf2e.bad_element', :invalid => self.type, :options => 'feat, charclass')
      end

      def check_chargen
        if enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def handle
        found = Pf2e.validate_feat_choice(enactor, self.choice, self.type)

        if found.is_a?(String)
          client.emit_failure found
          return
        end

        name = found[0]
        block = found[1]

        # No value given, so tell them what they can pick.
        if self.value.blank?
          client.emit Pf2e.describe_choice_options(enactor, name, block)
          return
        end

        matched = Pf2e.match_choice_option(enactor, name, block, self.value)

        unless matched
          client.emit_failure Pf2e.describe_bad_choice_option(enactor, name, block)
          return
        end

        messages = Pf2e.apply_feat_choice(enactor, name, block, matched, client)

        client.emit_success t('pf2e.choice_resolved', :choice => name, :value => matched)
        messages.each { |msg| client.emit_ooc msg }
      end

    end

  end
end
