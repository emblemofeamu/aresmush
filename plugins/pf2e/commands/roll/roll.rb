module AresMUSH
  module Pf2e

    class PF2RollCommand
      include CommandHandler

      attr_accessor :mods, :dc, :string

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_optional_arg2)

        # Make command return sanely even if you forget args.
        self.string = trim_arg(args.arg1)
        self.mods = trimmed_list_arg(args.arg1&.gsub("-", "+-")&.gsub("--","-"),"+")
        self.dc = args.arg2 ? args.arg2.to_i : nil
      end

      def required_args
        [ self.string ]
      end

      def check_valid_dc
        return nil if !self.dc
        if self.dc.between?(5,50)
          return nil
        else
          return t('pf2e.dc_must_be_integer')
        end
      end

      def handle

        roll = Pf2e.parse_roll_string(enactor,self.mods)
        list = roll['list']
        result = roll['result']
        total = roll['total']

        # Determine degree of success if DC is given
        degree = self.dc ? Pf2e.get_degree(list, result, total, self.dc) : ""

        dc_string = self.dc ? "against DC #{self.dc} " : ""

        roll_msg = t('pf2e.die_roll',
                  :roller => "%xh#{enactor.name}%xn",
                  :string => self.string,
                  :dc => dc_string,
                  :parsed => result.join(" + "),
                  :result => total,
                  :degree => degree
                )

        if cmd.switch == "me"
          client.emit "(%xgPRIVATE%xn) " + roll_msg
        else
          # Send it to the room, and to the room scene if there is one.
          enactor_room.emit roll_msg

          scene = enactor_room.scene
          if scene
            Scenes.add_to_scene(scene, roll_msg)

            # Add to the encounter, if in an active encounter in the scene.
            active_encounter = PF2Encounter.scene_active_encounter(scene)
            if active_encounter
              PF2Encounter.send_to_encounter(active_encounter, roll_msg)
            end
          end

          # Send to the roll channel if one is defined.
          channel = Global.read_config("pf2e", "roll_channel")
          if (channel)
            Channels.send_to_channel(channel, roll_msg)
          end



        end

        Global.logger.info "PF2 ROLL: #{roll_msg}"
      end

    end
  end
end
