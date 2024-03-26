module AresMUSH
  module Pf2emagic
    class PF2CastSpellsCmd
      include CommandHandler

      attr_accessor :charclass, :level, :spell, :target

      def parse_args
        if cmd.args
          args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)

          classlevel = trimmed_list_arg(args.arg1, "/")
          self.charclass = classlevel ? titlecase_arg(classlevel[0]) : nil
          self.level = classlevel ? classlevel[1]: nil

          self.spell = trim_arg(args.arg2)
          self.target = titlecase_list_arg(args.arg3, ",") || []
        end
      end

      def required_args
        [ self.charclass, self.spell ]
      end

      def check_is_approved
        return nil if enactor.is_approved?
        return t('dispatcher.not_allowed')
      end

      def handle
        # If the cast is successful, it passes a hash to the template.

        msg = Pf2emagic.cast_spell(enactor, self.charclass, self.spell, self.target, self.level, cmd.switch)

        if msg.is_a? String
          client.emit_failure msg
          return
        else
          template = PF2CastSpellTemplate.new(enactor, msg, client)

          cast_msg = template.render

          enactor_room.emit cast_msg
          scene = enactor_room.scene

          if scene
            Scenes.add_to_scene(scene, cast_msg)

            # Add to the encounter, if in an active encounter in the scene.
            active_encounter = PF2Encounter.scene_active_encounter(scene)
            if active_encounter
              PF2Encounter.send_to_encounter(active_encounter, cast_msg)
            end
          end

        end

      end

    end
  end
end
