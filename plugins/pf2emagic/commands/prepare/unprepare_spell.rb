module AresMUSH
  module Pf2emagic
    class PF2UnprepareSpellCmd
      include CommandHandler

      attr_accessor :caster_class, :spell_level, :spell_name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        parse_arg_1 = args.arg1.split("/")

        self.caster_class = trim_arg(parse_arg_1[0])
        self.spell_level = integer_arg(parse_arg_1[1])
        self.spell_name = titlecase_arg(args.arg2)
      end

      def required_args
        [ self.caster_class, self.spell_name, self.spell_level ]
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
        return nil
      end

      def handle

        # A spell level is either a cantrip or a number. Validate and normalize spell level expression.

        level = self.spell_level.zero? ? "cantrip" : self.spell_level.to_s

        msg = Pf2emagic.unprepare_spell(self.spell_name, enactor, self.caster_class, level)

        if msg
          client.emit_failure msg
          return
        else
          client.emit_success t('pf2emagic.spell_unprepare_ok', :name => self.spell_name, :as => self.caster_class)
        end

      end

    end
  end
end
