module AresMUSH
  module Pf2e
    class PF2ResetChargenCmd
      include CommandHandler

      attr_accessor :confirm

      def parse_args
        self.confirm = cmd.args
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

        if (enactor.pf2_reset && !self.confirm)
          client.emit_ooc t('pf2e.must_confirm')
          return nil
        elsif !enactor.pf2_reset && self.confirm
          client.emit_failure t('pf2e.reset_first')
          return nil
        elsif !enactor.pf2_reset && !self.confirm
          client.emit_ooc t('pf2e.are_you_sure')
          enactor.update(pf2_reset: true)
          return nil
        end

        Pf2e.reset_character(enactor)

        cuddles = rand(0..20)

        message = cuddles.zero? ? t('pf2e.cg_reset_ok_cuddles') : t('pf2e.cg_reset_ok')

        client.emit_success message

      end

    end
  end
end
