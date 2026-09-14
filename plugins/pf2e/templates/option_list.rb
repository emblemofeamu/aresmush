module AresMUSH
  module Pf2e
    # Paginated multi-column list of options.
    class PF2OptionListTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :paginator, :title, :columns

      def initialize(paginator, title = "Available Options", columns = 2)
        @paginator = paginator
        @title = title
        @columns = columns

        super File.dirname(__FILE__) + "/option_list.erb"
      end

      def option_list
        list = []

        @paginator.page_items.each_with_index do |item, i|
          list << format_option(item, i)
        end

        list
      end

      def format_option(item, i)
        # At two columns this is 37 characters, which fits every feat name in the configs
        # (the longest is 36) without truncation.
        width = (76 / @columns) - 1
        linebreak = i % @columns == 0 ? "%r" : ""

        "#{linebreak}#{left(item, width)}%b"
      end

    end
  end
end
