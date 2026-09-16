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

        # `find` hands back a FindResult, not a character. Reading `is_admin?` off the result
        # raised NoMethodError, so this command failed for every name it was given.
        found = ClassTargetFinder.find(self.target, Character, enactor)

        if !found.found?
          # The finder says whether the name was unknown or ambiguous; this used to report
          # everything as ambiguous.
          client.emit_failure found.error
          return
        end

        char = found.target

        if char.is_admin?
          client.emit_failure t('pf2e.admin_no_sheet')
          return
        end

        # You can only share a section you have: the same table both display commands read, so
        # `sheet/show` can no longer grant a section `sheet` would refuse to render.
        outcome = Pf2e::Sheet.available(enactor, self.section)

        if outcome.err?
          client.emit_failure t(outcome.key, outcome.args.transform_keys(&:to_sym))
          return
        end

        section = outcome.state

        # Names, not character objects: this is a hash attribute, and what reads it wants
        # something it can print and compare.
        permissions = enactor.pf2_viewsheet
        granted = Array(permissions[section])

        if granted.any? { |name| name.to_s.casecmp?(char.name.to_s) }
          client.emit_success t('pf2e.player_added', :player => char.name, :section => section)
          return
        end

        permissions[section] = granted + [ char.name ]
        enactor.update(pf2_viewsheet: permissions)

        client.emit_success t('pf2e.player_added', :player => char.name, :section => section)
      end

    end
  end
end
