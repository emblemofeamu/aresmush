module AresMUSH
  module Pf2e
    class PF2eFeatDisplay < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :paginator, :title, :page_notice

      def initialize(paginator, title, page_notice = nil)
        @paginator = paginator
        @title = title
        @page_notice = page_notice

        super File.dirname(__FILE__) + "/feat_display.erb"
      end

      def title
        @title
      end

      def page_footer
        footer = @paginator.page_footer
        return footer if @page_notice.blank?

        "#{footer}\n#{@page_notice}"
      end

    end
  end
end
