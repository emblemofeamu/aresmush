module AresMUSH
  module Pf2emagic

    class PF2RefocusCmd
      include CommandHandler

      attr_accessor :character

      def parse_args
        self.character = trim_arg(cmd.args)
      end

      def check_permissions
        # Admins can do this on any character, others only on themselves.

        return nil if !self.character
        return nil if enactor.is_admin?
        return t('dispatcher.not_allowed')
      end

      def handle

        char = Pf2e.get_character(self.character, enactor)
        before_refocus = char.magic.focus_pool['current'].to_i

        msg = Pf2emagic.do_refocus(char, enactor)

        if msg
          client.emit_failure msg
          return
        end

        after_refocus = char.magic.focus_pool['current'].to_i
        restored = [ after_refocus - before_refocus, 0 ].max

        success_msg = if restored == 1
                        t('pf2emagic.refocus_ok_one', :points => restored)
                      else
                        t('pf2emagic.refocus_ok_many', :points => restored)
                      end

        client.emit_success success_msg

      end


    end

  end
end
