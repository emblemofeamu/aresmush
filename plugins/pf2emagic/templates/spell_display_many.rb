module AresMUSH
  module Pf2emagic

    class PF2DisplayManySpellTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :spell_list, :client

      def initialize(spell_list, client)
        @spell_list = spell_list
        @client = client

        super File.dirname(__FILE__) + "/spell_display_many.erb"
      end

      def textline(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def matching_spells
        list = []

        @spell_list.sort.each_with_index do |spell, i|
          list << format_matching_spells(spell, i)
        end

        list
      end

      def multiple_matches_msg
        t('pf2emagic.multiple_matches', :item => "spell")
      end

      def format_matching_spells(spell, i)
        linebreak = i % 3 == 0 ? "%r" : ""
        "#{linebreak}#{left(spell,26)}"

      end

    end
  end
end
