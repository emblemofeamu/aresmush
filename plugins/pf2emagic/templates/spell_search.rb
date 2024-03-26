module AresMUSH
  module Pf2emagic
    class PF2SpellSearchResults < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :paginator, :title

      def initialize(paginator, title)
        @paginator = paginator
        @title = title

        super File.dirname(__FILE__) + "/spell_search.erb"
      end

      def title
        @title
      end

    end
  end
end
