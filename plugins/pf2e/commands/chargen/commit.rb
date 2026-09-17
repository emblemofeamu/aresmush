module AresMUSH
  module Pf2e
    class PF2CommitCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :commit

      def parse_args
        # What am I committing?
        self.commit = downcase_arg(cmd.args)
      end

      def required_args
        [ self.commit ]
      end

      # The stage machine and every completeness check live in Pf2e::Chargen::Lifecycle and
      # are unit tested there. The heavy part of a commit - building skill rows, HP, magic and
      # boost templates from config - is still the legacy lock helpers, called once the core
      # has agreed the stage may be committed.
      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :commit_stage, 'stage' => self.commit)

        return if Pf2e::CharState.emit_error!(client, outcome)

        failure = apply_stage_effects

        if failure
          client.emit_failure t('pf2e.cg_commit_failed', :msg => failure, :option => self.commit)
          return
        end

        Pf2e::CharState.commit!(enactor, before, outcome)
        Pf2e::CharState.emit_messages!(client, outcome)
      end

      def apply_stage_effects
        case self.commit
        when 'info'
          Pf2e.cg_lock_base_options(enactor, client)
        when 'abilities'
          Pf2eAbilities.cg_lock_abilities(enactor)
        when 'skills'
          Pf2eSkills.cg_lock_skills(enactor, client)
        when 'featskills'
          Pf2eSkills.cg_lock_featskills(enactor)
        end
      end

    end
  end
end
