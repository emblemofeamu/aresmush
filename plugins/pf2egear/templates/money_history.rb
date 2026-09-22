module AresMUSH
  module Pf2egear

    class PF2MoneyHistoryTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :paginator, :client

      def initialize(char, paginator, client)
        @char = char
        @paginator = paginator
        @client = client

        super File.dirname(__FILE__) + "/money_history.erb"
      end

      def textline(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def title
        t('pf2egear.money_history_title', :char => @char.name)
      end

      def page_items
        @paginator.page_items
      end

      def page_footer
        @paginator.page_footer
      end

      def header_line
        "%b%b#{item_color}#{left("Date", 18)}%b%b#{left("From", 14)}%b%b#{left("Amount", 11)}%b%b#{left("Purse", 11)}%b%b#{left("Reason", 24)}"
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
        item.amount.to_i.positive? ? "+#{item.amount} cp" : "#{item.amount} cp"
      end

      # What the purse held after this line, so one line explains itself.
      def running_total(item)
        "#{item.balance_after} cp"
      end

      def reason(item)
        item.reason
      end


    end
  end
end
