module AresMUSH
  module Pf2e
    class PF2RestoreChargenCmd
      include CommandHandler

      attr_accessor :checkpoint

      def parse_args
        self.checkpoint = downcase_arg(cmd.args)
      end

      def check_checkpoint
        valid_checkpoints = [ "info", "abilities", "skills" ]
        if !valid_checkpoints.include?(self.checkpoint)
          return t('pf2e.cg_restore_help')
        end
      end

      def check_in_chargen
        stages = { "featskills" => 7, "skills" => 6, "abilities" => 5, "info" => 4 }
        current_stage = stages[enactor.pf2_checkpoint]
        target_stage = stages[checkpoint]

        if enactor.is_approved? || enactor.chargen_locked
          return t('pf2e.only_in_chargen')
        elsif !enactor.chargen_stage
          return t('chargen.not_started')
        elsif !current_stage || !target_stage
          return t('pf2e.cg_restore_help')
        # In 5, going 6
        elsif current_stage < target_stage
          return t('pf2e.cg_cant_restore_to_stage_you_dont_have', :checkpoint=>self.checkpoint)
        else
          return nil
        end
      end

      def handle
        Pf2e.restore_checkpoint(enactor, checkpoint)
        client.emit_success t('pf2e.cg_restore_ok', :checkpoint=>checkpoint)
      end

    end
  end
end
