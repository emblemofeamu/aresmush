module AresMUSH
  module Pf2emagic
    class PF2CastSpellsCmd
      include CommandHandler

      attr_accessor :charclass, :level, :spell, :target

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        classlevel = trimmed_list_arg(args.arg1, "/")
        self.charclass = titlecase_arg(classlevel[0])
        self.level = classlevel[1]

        spelltarget = trimmed_list_arg(args.arg2, "at")
        self.spell = spelltarget[0]
        self.target = spelltarget[1] ? spelltarget[1].split : []
      end

      def required_args
        [ self.charclass, self.spell ]
      end

      def check_is_approved
        return nil if enactor.is_approved?
        return t('dispatcher.not_allowed')
      end

      def handle

        msg = Pf2emagic.cast_spell(enactor, self.charclass, self.spell, self.target, self.level, cmd.switch)

        if msg.is_a? String
          client.emit_failure msg
          return
        else
          client.emit msg
        end

      end

    end
  end
end
