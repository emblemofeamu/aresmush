module AresMUSH
  module Pf2egear
    class PF2DisplayGearCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args)
      end

      def check_permissions
        # Any character may view their own; only people who can see alts can see others'.

        return nil if !self.target
        # return nil if enactor.has_permission?('manage_alts')
        # return t('dispatcher.not_allowed')
      end

      def handle

        char = Pf2e.get_character(self.target, enactor)

        if char.is_admin?
          client.emit_failure t('pf2e.admin_use_inv_look')
          return
        end

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        if !(char.pf2_baseinfo_locked)
          client.emit_failure t('pf2e.lock_info_first')
          return
        end

        template = Pf2eDisplayGearTemplate.new(char, client)

        client.emit template.render

      end

    end
  end
end
