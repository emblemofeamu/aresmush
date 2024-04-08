module AresMUSH
  module Pf2e
    class PF2BoostSetCmd
      include CommandHandler

      attr_accessor :type, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.type = downcase_arg(args.arg1)
        self.value = titlecase_arg(args.arg2)
      end

      def required_args
        [ self.type, self.value ]
      end

      def check_chargen_or_advancement
        if enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def check_abilinfolock
        return t('pf2e.cg_abilities_locked') if enactor.pf2_abilities_locked
        return nil
      end

      def handle
        ##### VALIDATION SECTION #####
        # Verify that there are things to be assigned that this command handles.

        working_boost_list = enactor.pf2_boosts_working
        valid_boost_types = working_boost_list.keys

        if !(valid_boost_types.include?(self.type))
          client.emit_failure t('pf2e.bad_option', :element=>"boost type", :options=>valid_boost_types.join(", "))
          return
        end

        # Make sure they've committed their base info and their abilities are correctly created.
        char_abilities = enactor.abilities

        if !char_abilities || !enactor.pf2_baseinfo_locked
          client.emit_failure t('pf2e.lock_info_first')
          return
        end

        # Is the value given in the command valid?
        ability_options = char_abilities.map { |a| a.name }

        if !(ability_options.include?(self.value))
          client.emit_failure t('pf2e.bad_option', :element=>"abilities", :options=>ability_options.join(", "))
          return
        end

        # Do they already have that boost in that list? Duplicates are not allowed.

        boost_values = working_boost_list[self.type]

        if boost_values.include?(self.value)
          client.emit_failure t('pf2e.no_duplicate_boosts')
          return
        end

        # Do they have an open option to set that type to?
        # Location of open option becomes variable 'assigning'

        if boost_values.is_a?(String)
          client.emit_failure t('pf2e.no_free', :element=>self.type)
          return
        end

        # This could be an option assignment. If it is, that assignment
        # gets priority over an open slot. If not, assign to an open slot.

        option_check = boost_values.select { |val| val.is_a?(Array) }.flatten

        if !option_check.empty?
          if option_check.include?(self.value)
            assigning = boost_values.index(option_check)
          end
        else
          assigning = boost_values.index("open")
        end

        if !assigning
          client.emit_failure t('pf2e.no_free', :element=>self.type)
          return
        end

        ##### VALIDATION SECTION END #####

        boost_values[assigning] = self.value

        Pf2eAbilities.update_base_score(enactor,self.value)

        if self.type == 'charclass'
          combat = enactor.combat
          combat.update(key_abil: self.value)
        end

        working_boost_list[self.type] = boost_values

        enactor.update(pf2_boosts_working: working_boost_list)

        client.emit_success t('pf2e.assignment_ok', :type => self.type, :value => self.value)

      end

    end
  end
end
