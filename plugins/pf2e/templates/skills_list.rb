module AresMUSH
  module Pf2e
    class PF2SkillsListTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :paginator

      def initialize(paginator)
        @paginator = paginator

        super File.dirname(__FILE__) + "/skills_list.erb"
      end

      def title
        t('pf2e.skills_list_title')
      end

      def page_items
        list = []

        @paginator.page_items.each_with_index do |item, i|
          list << format_page_items(item, i)
        end

        list
      end

      def format_page_items(item, i)
        linebreak = i % 3 == 0 ? "%r" : ""
        "#{linebreak}#{left(item,26)}"
      end

    end
  end
end
