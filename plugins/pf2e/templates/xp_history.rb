module AresMUSH
  module Pf2e

    class PF2XPHistoryTemplate < ErbTemplateRenderer
      include CommonTemplateFields
      
      attr_accessor :char, :paginator, :client

      def initialize(char, paginator, client)
        @char = char
        @paginator = paginator
        @client = client

        super File.dirname(__FILE__) + "/xp_history.erb"
      end

      def textline(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def title
        t('pf2e.xp_history_title', :char => @char.name)
      end

      def page_items
        @paginator.page_items
      end

      def page_footer
        @paginator.page_footer
      end

      def header_line
        "%b%b#{item_color}#{left("Date", 18)}%b%b#{left("Awarder", 14)}%b%b#{left("Award", 8)}%b%b#{left("Total", 8)}%b%b#{left("Reason", 30)}"
      end

      # An out-of-bounds page hands the template a message string instead of entries.
      def entry?(item)
        item.is_a?(AresMUSH::Pf2eLedgerEntry)
      end

      def time(item)
        OOCTime.local_short_timestr(@char, Time.at(item.at.to_i))
      end

      def awarded_by(item)
        item.by
      end

      def award(item)
        item.amount.to_i.positive? ? "+#{item.amount}" : item.amount.to_s
      end

      # The total this line produced, so one line explains itself without adding up the ones
      # before it.
      def running_total(item)
        item.balance_after.to_s
      end

      def reason(item)
        item.reason
      end

    end
  end
end
