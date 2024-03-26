module AresMUSH
  module Pf2emagic

    class PF2CastSpellTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :caster, :spell_info, :client

      def initialize(caster, spell_info, client)
        @caster = caster
        @spell_info = spell_info
        @client = client

        super File.dirname(__FILE__) + "/cast_spell.erb"
      end

      def textline(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def caster_name
        @caster.name
      end

      def spell_name
        @spell_info['spell name']
      end

      def cast_level
        @spell_info['spell level']
      end

      def atk
        prof = @spell_info['prof_level']
        prof_bonus = Pf2e.get_prof_bonus(@caster, prof)

        abil_mod = @spell_info['modifier']

        abil_mod + prof_bonus
      end

      def dc
        atk + 10
      end

      def targets
        return nil unless @spell_info['targets']

        @spell_info['targets'].sort.join(", ")
      end

      def tradition
        @spell_info['tradition']
      end

      def spell_type
        @spell_info['spell type']
      end

      def is_focus_spell
        @spell_info['spell type'].match? 'focus'
      end

      def focus_type
        @spell_info['focus type']
      end


    end
  end
end
