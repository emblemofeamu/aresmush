module AresMUSH
  module Pf2egear
    class PF2ListMoneyCmd
      include CommandHandler

      attr_accessor :character

      def parse_args
        self.character = upcase_arg(cmd.args)
      end

      def check_permissions
        # Any character may view their own; only people who can see alts can see others'.

        return nil if !self.character
        return nil if enactor.has_permission?('manage_alts')
        return t('dispatcher.not_allowed')
      end

      def handle

        char = Pf2e.get_character(self.character, enactor)

        history = char.pf2_money_history.reverse
        items_per_page = 10
        total_pages = (history.count / items_per_page)
        total_pages = total_pages + 1 if (history.count % items_per_page != 0)

        page = cmd.page
        page_index_from_end = [ total_pages - page, 0 ].max
        offset = page_index_from_end * items_per_page
        page_batch = history[offset, items_per_page]

        paginator = PaginateResults.new(page, total_pages, page_batch, offset)
        if (paginator.out_of_bounds?)
          client.emit_failure paginator.out_of_bounds_msg
          return
        end

        template = PF2MoneyHistoryTemplate.new(char, paginator, client)

        client.emit template.render

      end

    end
  end
end
