module AresMUSH
    module Pf2emagic
  
      class PF2SpellbookTemplate < ErbTemplateRenderer
        include CommonTemplateFields
  
        attr_accessor :char, :spellbook, :client
  
        def initialize(char, spellbook, client)
          @char = char
          @spellbook = spellbook
          @client = client
          @charclass = spellbook.keys[0] # There can be only one!
  
          super File.dirname(__FILE__) + "/spellbook.erb"
        end
  
        def title
          t('pf2emagic.spellbook_title', :charclass => @charclass, :name => @char.name)
        end
  
        def spellbook_list
          list = []
          Global.logger.debug @spellbook
          Global.logger.debug @charclass
          
          @spellbook[@charclass].each_pair do |spell_level, spell_list|
            # spells = spellbook[@charclass][spell_level].join(", ")
            spells = spell_list.join(", ")
            list << "#{item_color}#{spell_level}:%xn #{spells}"
          end
  
          list
        end
  
      end
    end
  end
  