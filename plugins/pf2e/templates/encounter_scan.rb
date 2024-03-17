module AresMUSH
  module Pf2e
    class PF2EncounterScanTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :encounter

      def initialize(encounter)
        @encounter = encounter

        super File.dirname(__FILE__) + "/encounter_scan.erb"
      end

      def title
        t('pf2e.encounter_table_title', :id => @encounter.id)
      end

      def header_line
        "%b#{item_color}#{left("Name", 18)}%b#{left("Class", 10)}%b#{left("HP", 15)}%b#{left("AC", 4)}%b#{left("Per", 4)}%b#{left("Fort", 4)}%b#{left("Ref", 4)}%b#{left("Will", 4)}%b#{left("AOO?", 4)}%xn"
      end

      def player_list
        list = []

        @encounter.characters.sort{ |a, b| a.name <=> b.name }.each do |char|
          list << format_player(char)
        end

        list

      end

      def format_player(char)
        name = char.name
        charclass = char.pf2_base_info['charclass']
        hp = Pf2eHP.display_character_hp(char)
        ac = Pf2eCombat.calculate_ac(char)
        perception = Pf2eCombat.get_perception(char)
        fortitude = Pf2eCombat.get_save_bonus(char, "fortitude")
        reflex = Pf2eCombat.get_save_bonus(char, "reflex")
        will = Pf2eCombat.get_save_bonus(char, "will")
        aoo = Pf2e.has_feat?(char, "Attack of Opportunity") ? "Y" : "N"

        "%b#{left(name, 18)}%b#{left(charclass, 10)}%b#{left(hp, 15)}%b#{left(ac, 4)}%b#{left(perception, 4)}%b#{left(fortitude, 4)}%b#{left(reflex, 4)}%b#{left(will, 4)}%b#{left(aoo, 4)}"
      end


    end
  end
end
