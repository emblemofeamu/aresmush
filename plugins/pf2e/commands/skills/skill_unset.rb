module AresMUSH
  module Pf2e
    class PF2SkillUnSetCmd
      include CommandHandler

      attr_accessor :type, :value

      CHOICE_TYPES = [ 'bg skill choice', 'class skill choice', 'specialty skill choice' ]

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
        elsif !Pf2e.in_chargen?(enactor)
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

      def check_skill_in_checkpoint
        # Can't change skills set before feats grant additional skills, represented by
        # skill being contained in the skill checkpoint.

        if enactor.pf2_checkpoint == 'skills' # Enactor is selecting feats now.
          assigned = Pf2e::Checkpoints.attrs_at(enactor, 'skills')['pf2_to_assign'] || {}
          open_skills = Array(assigned["open skills"])

          bg_choice = assigned["bg skill choice"]
          class_choice = assigned["class skill choice"]
          specialty_choice = assigned["specialty skill choice"]

          if open_skills.include?(self.value) ||
             (bg_choice && bg_choice['selected'] == self.value) ||
             (class_choice && class_choice['selected'] == self.value) ||
             (specialty_choice && specialty_choice['selected'] == self.value)
            return t('pf2e.invalid_skill_change')
          end
        else
          return nil
        end
      end

      # Shell only: the rules live in Pf2e::Chargen::Skills and are unit tested there.
      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :untrain_skill, 'type' => self.type, 'skill' => self.value)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome, :source_type => 'chargen', :source_ref => 'skill pick', :effective_level => 1)
        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
