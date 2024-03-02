module AresMUSH
  module Pf2emagic

    class PF2ChargenSpellsCmd
      include CommandHandler

      attr_accessor :caster_class, :spell_level, :new_spell, :old_spell

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.caster_class = titlecase_arg(args.arg1)
        self.spell_level = integer_arg(args.arg2)

        spells = trimmed_list_arg(args.arg3, "/")

        if spells[1]
          self.new_spell = spells[1]
          self.old_spell = spells[0]
        else
          self.new_spell = spells[0]
          self.old_spell = false
        end
      end

      def required_args
        [ self.caster_class, self.spell_level, self.new_spell]
      end

      def handle

        level = self.spell_level.zero? ? "cantrip" : self.spell_level

        msg = Pf2emagic.select_spell(char, self.caster_class, level, self.old_spell, self.new_spell, true)

        if msg
          client.emit_failure msg
          return
        end

        client.emit_success t('pf2emagic.cg_spell_select_ok')

      end

    end

  end
end
