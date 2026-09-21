module AresMUSH
  module Pf2e

    class PF2AdvanceInfoCmd
      include CommandHandler

      attr_accessor :element, :filter

      def parse_args
        self.element, self.filter = Pf2e.split_info_filter(cmd.args)
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        # No element given, so list what they currently have outstanding.
        if self.element.blank?
          show_pending
          return
        end

        # Advancement-specific elements first, then the shared vocabulary.
        found = class_option_element || Pf2e.info_options(enactor, self.element)

        unless found
          client.emit_failure t('pf2e.bad_option', :element => "advance/info", :options => pending_elements.join(", "))
          return
        end

        display = Pf2e.info_option_display(found[0], found[1], cmd.page, self.filter)

        if display[:error]
          client.emit_failure display[:error]
        else
          client.emit display[:text]
        end
      end

      # What is still outstanding is one pure query over the draft - see
      # Pf2e::Advancement::Outstanding - so this command, the review template and any
      # completeness check cannot disagree about what is left to do.
      def outstanding
        @outstanding ||= Pf2e::CharState.of(enactor)
      end

      # A class feature option awaiting a pick, as [ title, options ].
      def class_option_element
        Pf2e::Advancement::Outstanding.class_option(outstanding, self.element)
      end

      # Everything the character could usefully ask about right now.
      def pending_elements
        Pf2e::Advancement::Outstanding.labels(outstanding)
      end

      def show_pending
        elements = pending_elements

        if elements.empty?
          client.emit_ooc t('pf2e.info_nothing_pending')
          return
        end

        client.emit t('pf2e.info_pending', :elements => elements.join(", "))
      end

    end
  end
end
