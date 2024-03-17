module AresMUSH
  module Pf2emagic

    class PF2SpellbookTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :spellbook, :client

      def initialize(char, charclass, spellbook, client)
        @char = char
        @charclass = charclass
        @spellbook = spellbook
        @client = client

        super File.dirname(__FILE__) + "/spellbook.erb"
      end

      def title
        t('pf2emagic.spellbook_title', :name => @char.name)
      end

      def spellbook_list
        list = []

        @spellbook.each_pair do |key, value|
          # If they asked for just one level, value can be an array. Otherwise, it's a hash.
          if value.is_a? Array
            header = "#{title_color}#{@charclass}:%xn%r"
            data = "#{item_color}#{key}:%xn #{value.sort.join(", ")}"

            list << "#{header}#{data}"
          else
            sublist = []

            value.each_pair do |level, spell_list|
              header = "#{item_color}#{level}:%xn"
              data = "#{spell_list.sort.join(", ")}"

              sublist << "#{header} #{data}"
            end

            list << "#{title_color}#{key}:%xn%r#{sublist.sort.join("%r")}"
          end

        end

        list
      end

    end
  end
end
