module AresMUSH
  module Pf2e
    class PF2SkillSetCmd
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

        # Is self.value a valid skill?

        all_skills = Global.read_config('pf2e_skills').keys

        if !all_skills.include?(self.value)
          # The list is long and spammy. Divert lores into their own list.
          option_msg = Pf2e.easter_scrub(all_skills).join(", ")
          client.emit_failure t('pf2e.bad_option', :element=>'skill name', :options=>option_msg)
          return
        end

        # Verify that this character's options left to assign include the listed type.

        assignment_type = skill_types[self.type]

        skill_options = to_assign[assignment_type]

        if !skill_options
          client.emit_failure t('pf2e.cannot_assign_type', :element=>"skill")
          return
        end

        # Does that character already have that skill trained?

        skill_for_char = Pf2eSkills.find_skill(self.value, enactor)

        if !(skill_for_char.prof_level == 'untrained')
          client.emit_failure t('pf2e.already_has_skill')
          return
        end

        ##### VALIDATION SECTION END #####

        # Type-specific handling

        # Background skills, if present, are an array of choices.
        # Match self.value to a choice in the array and assign it.

        case assignment_type
        when "bgskill"
          skill_choice = skill_options.select { |skill| skill == self.value }

          if skill_choice.size.zero?
            client.emit_failure t('pf2e.bad_option', :element=>"skill option", :options=>skill_options.sort.join(", "))
            return
          elsif skill_choice.size > 1
            client.emit_failure t('pf2e.ambiguous_target')
            return
          else
            skill_choice = skill_choice.first
          end

          skill_options = skill_choice

        # Open skills are a matter of finding an open skill left to assign.

        when "open skills"
          loc = skill_options.index("open")

          if !(loc)
            client.emit_failure t('pf2e.no_free', :element=>self.type)
            return
          end

          skill_options[loc] = self.value
        end

        to_assign[assignment_type] = skill_options

        enactor.update(pf2_to_assign: to_assign)

        skill_for_char.update(prof_level: 'trained')

        client.emit_success t('pf2e.add_ok', :item=>self.value, :list=>'skills')
      end

    end
  end
end
