module AresMUSH
  module Pf2emagic

    class PF2DisplayOneSpellTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :spell, :client

      def initialize(spell, client)
        @spell = spell
        @client = client

        @details = Global.read_config('pf2e_spells', spell)

        super File.dirname(__FILE__) + "/spell_display_one.erb"
      end

      def textline(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def spell
        @spell
      end

      def actions
        @details["actions"]
      end

      def traits
        @details["traits"].sort.join(", ")
      end

      def cast
        @details["cast"].join(", ")
      end

      def area
        @details["area"]
      end

      def range
        @details["range"]
      end

      def duration
        @details["duration"]
      end

      def heighten
        string = @details["heighten"]

        return nil if !string

        h = []

        if string.is_a?(Hash)
          string.each_pair do |k,v|
            h << "#{k}: #{v}"
          end
        else
          string.each_with_index do |v,i|
            h << "#{i + base_level.to_i}: #{v}"
          end
        end

        h.join("%r")

      end

      def base_level
        @details["base_level"]
      end

      def trads
        t = @details["tradition"]

        return nil unless t

        t.sort.join(", ")
      end

      def effect
        @details["effect"]
      end

      def save
        @details["save"]
      end

    end
  end
end
