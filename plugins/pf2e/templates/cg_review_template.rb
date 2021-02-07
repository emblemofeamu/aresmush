module AresMUSH
  module Pf2e

    class PF2CGReviewDisplay < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :client

      def initialize(char, client)
        @char = char
        @client = client

        super File.dirname(__FILE__) + "/cg_review.erb"
      end
  
      def elements
        base_info = @char.pf2_base_info
        @ancestry = base_info['ancestry']
        @heritage = base_info['heritage']
        @background = base_info['background']
        @charclass = base_info['charclass']
        @subclass = base_info['specialize']

        @ancestry_info = @ancestry.blank? ? {} : Global.read_config('pf2e_ancestry', @ancestry)
        @heritage_info = @heritage.blank? ? {} : Global.read_config('pf2e_heritage', @heritage)
        @background_info = @background.blank? ? {} : Global.read_config('pf2e_background', @background)
        @charclass_info = @charclass.blank? ? {} : Global.read_config('pf2e_class', @charclass)
        @faith_info = @char.pf2_faith

        super File.dirname(__FILE__) + "/cg_review.erb"
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def name
        @char.name
      end

      def ancestry
        @ancestry
      end

      def heritage
        @heritage
      end

      def background
        @background
      end

      def charclass
        @charclass
      end

      def subclass
        @subclass
      end

      def faith
        @faith_info['faith']
      end

      def deity
        @faith_info['deity']
      end

      def alignment
        @faith_info['alignment']
      end

      def hp
        ancestry_hp = @ancestry_info["HP"] ? @ancestry_info["HP"] : 0
        class_hp = @charclass_info["HP"] ? @charclass_info["HP"] : 0

        ancestry_hp + class_hp
      end

      def size
        @ancestry_info["Size"] ? @ancestry_info["Size"] : "M"
      end

      def speed
        @ancestry_info["Speed"] ? @ancestry_info["Speed"] : "?"
      end

      def traits
        a_traits = @ancestry_info["traits"] ? @ancestry_info["traits"] : []
        h_traits = @heritage_info["traits"] ? @heritage_info["traits"] : []
        c_traits = @charclass ? [ @charclass.downcase ] : []

        a_traits + h_traits + c_traits.uniq.sort.join(", ")
      end

      def ancestry_boosts
        @ancestry_info["abl_boosts"] ? @ancestry_info["abl_boosts"] : "?"
      end

      def free_ancestry_boosts
        @ancestry_info["abl_boosts_open"] ? @ancestry_info["abl_boosts_open"] : 0
      end

      def background_boosts
        list = self.background_info["req_abl_boosts"]
        list.empty? ? "None required." : list.join(" or ")
      end

      def charclass_boosts
        list = self.charclass_info["key_score"]
        list.join("or")
      end

      def specials
        specials = @ancestry_info["special"] + @heritage_info["special"] + @background_info["special"].flatten
        if Pf2e.character_has?(@ancestry_info["special"], "Low-Light Vision") && @heritage_info["change_vision"]
          specials = specials.delete_at specials.index("Low-Light Vision") + [ "Darkvision" ]
        end
        specials.empty? ? "No special abilities or senses." : specials.sort.join(", ")
      end

      def messages
        msgs = Pf2e.chargen_messages(@ancestry, @heritage, @background, @charclass, @subclass, @char.pf2_faith)
        msgs ? msgs : t('pf2e.cg_options_ok')
      end
    end
  end
end
