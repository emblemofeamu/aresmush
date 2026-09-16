module AresMUSH
  module Pf2e

    class PF2DisplaySheetCmd
      include CommandHandler

      attr_accessor :section, :target

      def parse_args
        self.section = cmd.switch ? downcase_arg(cmd.switch) : "all"
        self.target = trim_arg(cmd.args)
      end

      def handle
        char = Pf2e.get_character(self.target, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        # Whether this viewer may see it, and whether the section exists at all, are both
        # Pf2e::Sheet's business - including the grants `sheet/show` writes, which nothing used
        # to read.
        outcome = Pf2e::Sheet.viewable?(enactor, char, self.section)
                    .and_then { Pf2e::Sheet.available(char, self.section) }

        if outcome.err?
          client.emit_failure t(outcome.key, outcome.args.transform_keys(&:to_sym))
          return
        end

        template = Pf2eSheetTemplate.new(char, outcome.state, client, char.pf2_base_info, char.pf2_faith)

        client.emit template.render
      end

    end

  end
end
