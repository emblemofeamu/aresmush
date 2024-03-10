module AresMUSH
  module Pf2e
    class PF2CGInfoTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :paginator, :option_list, :title

      def initialize(paginator, option_list, title)
        @paginator = paginator
        @title = title

        super File.dirname(__FILE__) + "/cg_info.erb"
      end

      def title
        @title
      end

      def cg_info_list

      end

      def format_cginfo_options(item, i)
        linebreak = i % 3 == 0 ? "%r" : ""

        "#{linebreak}#{left(item, 25)}%b"
      end

    end
  end
end
