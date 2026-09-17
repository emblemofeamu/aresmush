module AresMUSH
  module Pf2e
    class PF2BoostSetCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

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
        elsif !Pf2e.in_chargen?(enactor)
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def check_abilinfolock
        return t('pf2e.cg_abilities_locked') if enactor.pf2_abilities_locked
        return nil
      end

      # Shell only: build state, run the transformation, save what it changed, speak.
      # The rules live in Pf2e::Chargen::Boosts and are unit tested there.
      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :set_boost, 'type' => self.type, 'ability' => self.value)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)

        # Not yet owned by the fold: ability scores and the class key ability are still
        # written directly. Moving them into the materialiser is the next step.
        Pf2eAbilities.update_base_score(enactor, self.value)
        enactor.combat.update(key_abil: self.value) if self.type == 'charclass' && enactor.combat

        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
