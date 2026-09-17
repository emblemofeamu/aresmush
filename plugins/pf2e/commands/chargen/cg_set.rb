module AresMUSH
  module Pf2e

    class PF2SetChargenCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :element, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.element = downcase_arg(args.arg1)
        self.value = trim_arg(args.arg2)
      end

      def required_args
        [ self.element, self.value ]
      end

      def check_in_chargen
        if enactor.is_approved? || enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.pf2_baseinfo_locked
          return t('pf2e.cg_options_locked')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      # Shell only. Every rule - option resolution, the champion and deity cross-checks,
      # clearing dependent picks - lives in Pf2e::Chargen::BaseInfo and is unit tested there
      # without a character, a client or a database.
      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :set_base_info, 'element' => self.element, 'value' => self.value)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)
        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
