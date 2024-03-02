module AresMUSH
  module Pf2e

    class PF2DisplayCombatSheetCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args)
      end

      def check_can_view
        return nil if !self.target
        return nil if Global.read_config('pf2e','open_sheets')
        return nil if enactor.has_permission?("view_sheets")
        return t('pf2e.cannot_view_sheet')
      end

      def handle
        char = Pf2e.get_character(self.target, enactor)

        if !char
          client.emit_failure t('pf2e.char_not_found')
          return
        elsif char.is_admin?
          client.emit_failure t('pf2e.admin_no_sheet')
          return
        elsif !char.pf2_baseinfo_locked
          client.emit_failure t('pf2e.no_sheet_yet')
          return
        end

        template = PF2CombatSheetTemplate.new(char, client)

        client.emit template.render
      end

    end

  end
end
