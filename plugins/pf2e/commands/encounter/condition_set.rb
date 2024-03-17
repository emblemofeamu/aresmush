module AresMUSH
  module Pf2e
    class PF2ConditionSetCmd
      include CommandHandler

      attr_accessor :target, :condition, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)
        self.target = trimmed_list_arg(args.arg1)
        self.condition = titlecase_arg(args.arg2)
        self.value = integer_arg(args.arg3)
      end

      def required_args
        [ self.target, self.condition ]
      end

      def check_valid_condition
        condition_list = Global.read_config('pf2e_conditions').keys
        return nil if condition_list.include? self.condition
        return t('pf2e.condition_not_found', :options => condition_list.sort.join(", "))
      end

      def check_valid_value
        # If self.value is set, it should be 1-5, or 0 to clear the condition.
        return nil if !self.value
        return nil if self.value.between?(0,5)
        return t('pf2e.bad_value', :item => 'a condition')
      end

      def handle

        # You must be either a DM / staffer or the organizer of an active encounter in which the targets are participating.

        can_damage_pc = Pf2e.can_damage_pc?(enactor, self.target)

        if !can_damage_pc
          client.emit_failure t('pf2e.cannot_damage_pc')
          return
        end

        # This should already be nil-checked in the checks above, so I don't bother.

        condition_details = Global.read_config('pf2e_conditions', self.condition)

        if condition_details['value'] && !self.value
          client.emit_failure t('pf2e.condition_needs_value')
          return
        end

        # Do all of the targets exist as PC's?

        target_list = []
        not_found_list = []

        self.target.each do |char|
          result = ClassTargetFinder.find(char, Character, enactor)
          if result.found?
            target_list << result.target
          else
            not_found_list << char
          end
        end

        if !not_found_list.empty?
          client.emit_ooc t('pf2e.bad_value_in_list', :items => 'names', :list => not_found_list.join(', '))
        end


        target_list.each do |char|
          Pf2e.set_condition(char, self.condition, self.value)
        end

        client.emit_success t('pf2e.condition_set_ok',
          :condition => self.condition,
          :target => target_list.map { |t| t.name }.sort.join(", ")
        )

      end

    end
  end
end
