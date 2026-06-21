module AresMUSH
  module Pf2e
    class PF2CommitCmd
      include CommandHandler

      attr_accessor :commit

      def parse_args
        # What am I committing?
        self.commit = downcase_arg(cmd.args)
      end

      def required_args
        [ self.commit ]
      end

      def check_in_chargen
        return nil if enactor.chargen_stage > 0 && !(enactor.is_approved?)
        return t('pf2e.only_in_chargen')
      end

      def check_can_commit
        # Is the argument valid?
        checkpoints = %w(start info abilities skills featskills)

        index = checkpoints.index(self.commit)
        options = (checkpoints - ['start']).join(", ")
        syntax_msg = t('pf2e.bad_option', :element => 'commit', :options => options)
        return syntax_msg unless index

        # Enforce checkpoint order.
        last_checkpoint = checkpoints[index - 1]

        return t('pf2e.wrong_stage') unless (last_checkpoint == enactor.pf2_checkpoint)
        return nil
      end

      def handle
        case self.commit
        when 'info'
          commit = Pf2e.cg_lock_base_options(enactor, client)
        when 'abilities'
          commit = Pf2eAbilities.cg_lock_abilities(enactor)
        when 'skills'
            commit = Pf2eSkills.cg_lock_skills(enactor, client)
        when 'featskills'
          commit = Pf2eSkills.cg_lock_featskills(enactor)
        else
          client.emit_failure "To go back to the beginning, type %x172cg/reset%xn."
        end

        # Commit will return a string if it went sideways and nil if it's okay.
        if commit
          client.emit_failure t('pf2e.cg_commit_failed', :msg => commit, :option => self.commit)
        else
          client.emit_success t('pf2e.chargen_committed')
        end
      end

    end
  end
end
