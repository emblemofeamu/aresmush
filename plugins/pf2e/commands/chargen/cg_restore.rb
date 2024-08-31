module AresMUSH
  module Pf2e
    class PF2RestoreChargenCmd
      include CommandHandler

      attr_accessor :checkpoint

      def parse_args
        self.checkpoint = cmd.args
        if ![ "info", "abilities", "skills" ].include? self.checkpoint
          return nil
        end
      end

      def check_in_chargen
        if enactor.is_approved? || enactor.chargen_locked
          return t('pf2e.only_in_chargen')
        elsif !enactor.chargen_stage
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def handle
        client.emit char.name
        client.emit checkpoint
        Pf2e.restore_checkpoint(char, checkpoint)
        client.emit_success message

      end

    end
  end
end
