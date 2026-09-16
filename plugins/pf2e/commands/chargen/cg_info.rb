module AresMUSH
  module Pf2e

    class PF2ChargenInfoCmd
      include CommandHandler

      attr_accessor :element

      def parse_args
        self.element = downcase_arg(cmd.args)
      end

      def handle
        # A base info element - what each one needs first and where its options come from is
        # Pf2e::ChargenInfo's table.
        outcome = Pf2e::ChargenInfo.options(enactor, self.element)

        if outcome.ok?
          show outcome.state['title'], outcome.state['options']
          return
        end

        # Not a base info element at all. It may still be a pending feat choice or a feat slot
        # type, which cg/info and advance/info share.
        shared = Pf2e.info_options(enactor, self.element)

        if shared
          show shared[0], shared[1]
          return
        end

        # A real element that is not answerable yet keeps its own message; anything else gets the
        # list of what can be asked about.
        if outcome.code == :no_cginfo_available
          client.emit_ooc t(outcome.key, outcome.args.transform_keys(&:to_sym))
        else
          client.emit_failure t(outcome.key, outcome.args.transform_keys(&:to_sym))
        end
      end

      def show(title, options)
        display = Pf2e.info_option_display(title, options, cmd.page)

        if display[:error]
          client.emit_failure display[:error]
        else
          client.emit display[:text]
        end
      end

    end
  end
end
