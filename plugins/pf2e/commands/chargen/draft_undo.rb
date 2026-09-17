module AresMUSH
  module Pf2e

    # Takes back the last step of an open draft, or puts it back.
    #
    # One command for both drafts, because a step is a step: `cg/undo` before approval and
    # `advance/undo` during a level-up reach the same journal. What it cannot do is reach past the
    # commit boundary - an approved character's history belongs to the grant ledger, and
    # `admin/rollback` is the undo for that.
    class PF2DraftUndoCmd
      include CommandHandler

      # undo | redo, from the switch.
      attr_accessor :direction

      DIRECTIONS = {
        'undo' => {
          'act' => lambda { |char| DraftJournal.undo!(char) },
          'ok' => 'pf2e.draft_undone',
          'empty' => 'pf2e.draft_nothing_to_undo'
        },
        'redo' => {
          'act' => lambda { |char| DraftJournal.redo!(char) },
          'ok' => 'pf2e.draft_redone',
          'empty' => 'pf2e.draft_nothing_to_redo'
        }
      }.freeze

      def parse_args
        self.direction = cmd.switch.to_s.downcase
      end

      def check_drafting
        return nil if Ledger.drafting?(enactor)
        return t('pf2e.draft_closed')
      end

      def check_direction
        return nil if DIRECTIONS.key?(self.direction)
        return t('pf2e.bad_option', :element => 'undo', :options => DIRECTIONS.keys.join(', '))
      end

      def handle
        row = DIRECTIONS[self.direction]

        if self.direction == 'undo' && DraftJournal.stale?(enactor)
          client.emit_failure t('pf2e.draft_changed_elsewhere')
          return
        end

        action = row['act'].call(enactor)

        if action.blank?
          client.emit_failure t(row['empty'])
          return
        end

        client.emit_success t(row['ok'], :action => action)
        client.emit_ooc t('pf2e.draft_steps_left', :count => DraftJournal.steps(Character[enactor.id]).size)
      end
    end
  end
end
