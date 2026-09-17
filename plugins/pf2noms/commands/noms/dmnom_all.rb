module AresMUSH
  module Pf2noms

    class PF2DMNomAllCommand
      include CommandHandler

      def check_approval
        return t('dispatcher.not_allowed') if !enactor.has_permission("dm")
        return nil
      end

      def handle

        nom_okay = []
        char_list = Global.client_monitor.logged_in

        char_list.each do |char|

          if !(char.player)
            client.emit_ooc t('pf2noms.target_bad_player', :target=>char.name)
            next
          elsif !char.is_approved?
            client.emit_ooc t('pf2noms.target_not_approved', :target=>char.name)
            next
          else
            nom_okay << char
          end
        end

        nom_amount = Global.read_config('pf2noms', 'dmnom_amount')
        nom_money = Global.read_config('pf2noms', 'dmnom_money')

        nom_okay.each do |target|
          Pf2e.award_xp(target, nom_amount, enactor.name, 'GM nomination')
          Pf2egear.pay_player(target, nom_money, enactor.name, 'GM nomination')
        end

        client.emit_ooc t('pf2noms.dmnomallsuccess')

        message = t('pf2noms.dmnom_notify', :sender => enactor.name)

        Global.notifier.notify_ooc(type, message) do |char|
          char & nom_okay.include?(char)
        end

      end

    end
  end
end
