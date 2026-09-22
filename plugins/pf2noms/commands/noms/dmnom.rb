module AresMUSH
  module Pf2noms

    class PF2DMNomCommand
      include CommandHandler

      attr_accessor :list

      def parse_args
        self.list = list_arg(cmd.args)
      end

      def check_approval
        return t('dispatcher.not_allowed') if !enactor.has_permission("dm")
        return nil
      end

      def handle

        nom_okay = []

        self.list.each do |item|
          char = Pf2e.get_character(item, enactor)

          if !(char.player)
            client.emit_ooc t('pf2noms.target_bad_player', :target=>char.name)
            next
          elsif !(char.is_approved?)
            client.emit_ooc t('pf2noms.target_not_approved', :target=>char.name)
            next
          end

          times_present = already_nomd.count(char.player)

          if times_present >= max_per_day
            client.emit_ooc t('pf2noms.target_already_nomd', :target=>char.name)
            next
          else
            nom_okay << char
          end
        end

        nom_amount = Global.read_config('pf2noms', 'dmnom_amount')
        nom_money = Global.read_config('pf2noms', 'dmnom_money')
        success_list = []

        nom_okay.each do |target|
          Pf2e.award_xp(target, nom_amount, enactor.name, 'GM nomination')
          Pf2egear.pay_player(target, nom_money, enactor.name, 'GM nomination')
          success_list << target.name
        end

        client.emit_ooc t('pf2noms.success', :list=>success_list.sort.join(", "))

        message = t('pf2noms.dmnom_notify', :sender => enactor.name)

        Global.notifier.notify_ooc(type, message) do |char|
          char & nom_okay.include?(char)
        end

      end

    end
  end
end
