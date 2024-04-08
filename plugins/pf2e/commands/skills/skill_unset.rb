module AresMUSH
  module Pf2e
    class PF2SkillUnSetCmd
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
        return t('pf2e.lock_abil_first') if !enactor.pf2_abilities_locked
        return nil
      end

      def check_skill_lock
        return t('pf2e.cg_locked', :cp => 'skills') if enactor.pf2_skills_locked
        return nil
      end

      def handle
        ##### VALIDATION SECTION #####

        # Verify that there are things to be assigned that this command handles.
        skill_types = { 'background'=>'bgskill', 'free'=>'open skills' }
        options = skill_types.keys
        to_assign = enactor.pf2_to_assign

        if !(options.include?(self.type))
          client.emit_failure t('pf2e.bad_option', :element=> "skill type", :options=> options.sort.join(", "))
          return
        end

        # Verify that this character's options left to assign include the listed type.

        assignment_type = skill_types[self.type]

        skill_options = to_assign[assignment_type]

        if !skill_options
          client.emit_failure t('pf2e.cannot_assign_type', :element=>"skill")
          return
        end

        # Is self.value a valid skill?

        all_skills = Global.read_config('pf2e_skills').keys

        if !all_skills.include?(self.value)
          client.emit_failure t('pf2e.bad_option', :element=>'skill name', :options=>all_skills.join(", "))
          return
        end

        # Do they have this skill?

        skill_for_char = Pf2eSkills.find_skill(self.value, enactor)

        if skill_for_char.prof_level == 'untrained'
          client.emit_failure t('pf2e.does_not_have', :item=>'skill')
          return
        end

        # Is this skill set by chargen options? If so, they can't change it.

        if skill_for_char.cg_skill
          client.emit_failure t('pf2e.element_cglocked', :element=>'skill')
          return
        end

        ##### VALIDATION SECTION END #####

        reference = enactor.pf2_cg_assigned[assignment_type]

        case assignment_type
        when "bgskill"

        skill_options = reference

        # If open skill, find the skill in the list and set it to 'open'.

        when "open skills"
          index = skill_options.index(self.value)

          if !index
            client.emit_failure t('pf2e.not_in_list', :option=>self.value)
            return
          end

          skill_options[index] = 'open'
        end

        to_assign[assignment_type] = skill_options

        enactor.update(pf2_to_assign: to_assign)

        skill_for_char.update(prof_level: 'untrained')

        client.emit_success t('pf2e.reset_ok', :element=>assignment_type, :option=>self.value)
      end

    end
  end
end
