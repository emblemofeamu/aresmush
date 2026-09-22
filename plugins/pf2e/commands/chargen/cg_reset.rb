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

      # The confirmation dance is Pf2e::Chargen::Lifecycle.reset; the destructive part runs
      # here once the core says the player confirmed.
      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :reset_chargen, 'confirm' => !!self.confirm)

        return if Pf2e::CharState.emit_error!(client, outcome)

        if outcome.state['do_reset']
          Pf2e.reset_character(enactor)

          # The cuddles are load-bearing.
          message = rand(0..20).zero? ? t('pf2e.cg_reset_ok_cuddles') : t('pf2e.cg_reset_ok')
          enactor.update(:pf2_reset => false)
          client.emit_success message
          return
        end

        enactor.update(:pf2_reset => !!outcome.state['reset_pending'])
        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
