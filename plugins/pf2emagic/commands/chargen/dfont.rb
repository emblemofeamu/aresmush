module AresMUSH
  module Pf2emagic

    class PF2DivineFontCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :font

      def parse_args
        self.font = downcase_arg(cmd.args)
      end

      def required_args
        [ self.font ]
      end

      # A font is a chargen choice for a cleric, but a level can open one too: a `magic_stats` block
      # granting `divine_font` with both options writes the same `to_assign` slot mid-climb, and
      # `advance/review` lists it as outstanding. The command that fills it has to be reachable then,
      # or the level cannot be finished - and `dfont` is the only one there is.
      def check_in_chargen
        return nil if font_owed_by_a_level?

        if enactor.is_approved? || enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif !Pf2e.in_chargen?(enactor)
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def font_owed_by_a_level?
        enactor.advancing && (enactor.pf2_to_assign || {})['divine font'].is_a?(Array)
      end

      def check_baseinfo_locked
        # They need to have done commit info before they can use this command.
        return nil if enactor.pf2_baseinfo_locked
        return t('pf2e.lock_info_first')
      end

      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :choose_divine_font, 'font' => self.font)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)

        # The font itself lives on the magic object, which is not state a core writes.
        enactor.magic&.update(:divine_font => outcome.state['divine_font'])

        Pf2e::CharState.emit_messages!(client, outcome)
      end
    end
  end
end
