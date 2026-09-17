module AresMUSH
  module Pf2e
    class PF2BoostUnsetCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :type, :value

      # Disabling validations for now since this command is currently non-functional.
      # Will re-enable when the boost system is reworked.
      # def parse_args
      #   args = cmd.parse_args(ArgParser.arg1_equals_arg2)
      #   self.type = downcase_arg(args.arg1)
      #   self.value = titlecase_arg(args.arg2)
      # end

      # def required_args
      #   [ self.type, self.value ]
      # end

      # def check_chargen_or_advancement
      #   if enactor.chargen_locked || enactor.is_admin?
      #     return t('pf2e.only_in_chargen')
      #   elsif enactor.chargen_stage.zero?
      #     return t('chargen.not_started')
      #   else
      #     return nil
      #   end
      # end

      # def check_abilinfolock
      #   return t('pf2e.cg_abilities_locked') if enactor.pf2_abilities_locked
      #   return nil
      # end

      def check_out
        # Due to the complexity of the boost system, this command is currently disabled.
        return t('pf2e.boost_not_working')
      end


      def handle
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :unset_boost, 'type' => self.type, 'ability' => self.value)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)

        Pf2eAbilities.update_base_score(enactor, self.value, -2)
        enactor.combat.update(key_abil: nil) if self.type == 'charclass' && enactor.combat

        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
