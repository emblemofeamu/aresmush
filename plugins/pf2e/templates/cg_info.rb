module AresMUSH
  module Pf2e
    class PF2CGInfoTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :paginator, :title

      def initialize(paginator, title)
        @paginator = paginator
        @title = title

        super File.dirname(__FILE__) + "/cg_info.erb"
      end

      def title
        @title
      end

    end
  end
end
