module AresMUSH
  module Pf2emagic
    class PF2PrepareSpellCmd
      include CommandHandler

      attr_accessor :caster_class, :spell_level, :spell_name

      def parse_args
        # One of the most annoying limitations of Faraday's arg parser is its out-and-out bad
        # handling when cmd.args is nil.
        if cmd.args
          args = cmd.parse_args(ArgParser.arg1_equals_arg2)

          parse_arg_1 = args.arg1.split("/")

          self.caster_class = trim_arg(parse_arg_1[0])
          self.spell_level = integer_arg(parse_arg_1[1])
          self.spell_name = titlecase_arg(args.arg2)
        end
      end

      def required_args
        [ self.caster_class, self.spell_name ]
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        # Arcane Evolution Check

        if cmd.switch == "evo"
          if character_has?(enactor.pf2_feats.values.flatten, "Arcane Evolution")
            use_arcane_evo = true
          else
            client.emit_failure t('pf2e.does_not_have', :item => 'feat')
          end
        else
          use_arcane_evo = false
        end

        # A spell level is either a cantrip or a number. Validate and normalize spell level expression.

        level = self.spell_level.zero? ? "cantrip" : self.spell_level.to_s

        msg = Pf2emagic.prepare_spell(self.spell_name, enactor, self.caster_class, level, use_arcane_evo)

        # If the prepare succeeded, msg will be a hash, if failure, it'll be a string.
        if msg.is_a?(String)
          client.emit_failure msg
          return
        end

       if msg["is_signature"]
        client.emit_success t('pf2emagic.spell_prepare_as_signature_ok',
          :name => msg["name"],
          :level => msg["level"]
          )
       else
        client.emit_success t('pf2emagic.spell_prepare_ok',
          :name => msg["name"],
          :level => msg["level"],
          :as => msg["caster class"]
          )
       end
      end

    end
  end
end
