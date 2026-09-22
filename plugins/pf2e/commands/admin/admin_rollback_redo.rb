module AresMUSH
  module Pf2e

    # admin/unrollback <character> - undoes the last admin/rollback.
    #
    # A rollback only marks the level-up transactions it reverted, so redoing one is a matter
    # of clearing that marker. The marker is stored on the character by the rollback itself,
    # which is what makes this reachable without reading the log.
    class PF2AdminRollbackRedoCmd
      include CommandHandler

      attr_accessor :character

      def parse_args
        self.character = trim_arg(cmd.args)
      end

      def required_args
        [ self.character ]
      end

      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      def handle
        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        failure = Pf2e.redo_rollback(char, enactor)

        if failure
          client.emit_failure failure
          return
        end

        char = Character[char.id]

        client.emit_success t('pf2e.rollback_redo_ok', :name => char.name, :level => char.pf2_level)

        char_client = Login.find_game_client(char)
        char_client.emit_ooc t('pf2e.rollback_redo_notice', :level => char.pf2_level) if char_client
      end

    end

  end
end
