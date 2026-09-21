module AresMUSH
  module Pf2e

    class PF2ShowSheetCmd
      include CommandHandler

      attr_accessor :section, :target

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.target = trim_arg(args.arg1)
        self.section = args.arg2 ? downcase_arg(args.arg2) : "all"
      end

      def handle
        if enactor.is_admin?
          client.emit_ooc t('pf2e.admin_no_sheet')
          return
        end

        if !cmd.args
          client.emit PF2SheetPermissions.new(enactor.pf2_viewsheet).render
          return
        end

        # `find` hands back a FindResult, not a character: `target`, `error` and `found?` are its
        # whole interface.
        found = ClassTargetFinder.find(self.target, Character, enactor)

        if !found.found?
          # The finder's own message distinguishes an unknown name from an ambiguous one.
          client.emit_failure found.error
          return
        end

        char = found.target

        if char.is_admin?
          client.emit_failure t('pf2e.admin_no_sheet')
          return
        end

        # You can only share a section you have, read from the same table both display commands
        # use.
        outcome = Pf2e::Sheet.available(enactor, self.section)

        return if Pf2e::CharState.emit_error!(client, outcome)

        section = outcome.state

        # A name, not a character object: this is a hash attribute, and what reads it needs
        # something it can print and compare.
        before = Pf2e::CharState.of(enactor)
        outcome = Pf2e::CharacterService.call(before, :add_record,
          'record' => 'viewsheet', 'key' => section, 'value' => char.name)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)
        Pf2e::CharState.emit_messages!(client, outcome)
      end

    end
  end
end
