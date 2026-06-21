module AresMUSH
  module Pf2noms

    class PF2NomDisplayCommand
      include CommandHandler

      attr_accessor :char

      def parse_args
        self.char = trim_arg(cmd.args)
      end

      def check_permissions
        return nil if enactor.has_permission?("manage_alts")

        return t('pf2noms.enactor_not_approved') if !enactor.is_approved?

        return nil if !self.char

        return t('pf2noms.view_only_own')
      end

      def handle

        is_staffer = enactor.has_permission?("manage_alts") ? true : false

        if is_staffer
          result = ClassTargetFinder.find(self.char, Character, enactor)
          if result.found?
            player = result.target.player
            character = result.target.name
          else
            player = nil
            character = nil
          end
        else
          player = enactor.player
          character = enactor.name
        end

        if !character
          client.emit_failure t('pf2noms.target_not_found', :target=>self.char)
          return nil
        elsif !player
          client.emit_failure t('pf2noms.invalid_player')
          return nil
        end

        weekly_noms = Global.read_config('pf2noms', 'noms_per_week')
        weekly_noms_available = player.totalnoms
        noms_given_today = player.nomlist.count

        msg = t('pf2noms.nom_check',
          :char => character,
          :weekly_noms => weekly_noms,
          :weekly_noms_available => weekly_noms_available,
          :noms_given_today => noms_given_today
        )

        client.emit_ooc msg

      end

    end
  end
end
