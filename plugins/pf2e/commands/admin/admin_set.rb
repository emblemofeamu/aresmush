module AresMUSH
  module Pf2e

    class PF2AdminSetCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :character, :item, :value

      # The two corrections that do not go through the grant ledger, because focus spells and a
      # divine font are not part of the fold. `AdminSet` asks for them by name.
      MAGIC_OPS = {
        'update' => lambda { |char, client, op| PF2Magic.update_magic(char, op['charclass'], op['info'], client) },
        'revoke_focus' => lambda { |char, _client, op|
          Pf2emagic::Entries.revoke_focus!(char, op['focus_type'], op['spell'], :kind => op['kind'])
        }
      }.freeze

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.character = trim_arg(args.arg1)
        self.item = downcase_arg(args.arg2)
        self.value = titlecase_list_arg(args.arg3)
      end

      def required_args
        [ self.character, self.item, self.value ]
      end

      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      # The character being corrected, not the staff member typing it.
      def draft_subject
        @subject ||= Pf2e.get_character(self.character, enactor)
      end

      def handle
        char = draft_subject

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        # An approved character who predates the ledger has no grants to correct, so their
        # current sheet becomes the imported transaction this correction lands on top of.
        Ledger.seed_from_sheet!(char) if char.is_approved?

        before = CharState.of(char)
        outcome = CharacterService.call(before, :admin_set, 'item' => self.item, 'value' => self.value)

        return if CharState.emit_error!(client, outcome)

        # A staff correction applies at every level and no rollback reaches it: it is a decision
        # about the character rather than something they earned at a level.
        CharState.commit!(char, before, outcome, :source_type => 'staff',
                          :source_ref => "admin/set #{self.item}", :effective_level => nil,
                          :granted_by => enactor.name)

        Array(outcome.state['magic_ops']).each do |op|
          MAGIC_OPS[op['op']].call(char, client, op)
        end

        CharState.emit_messages!(client, outcome)
      end
    end
  end
end
