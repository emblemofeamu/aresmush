module AresMUSH
  module Pf2e

    class PF2RollCommand
      include CommandHandler

      attr_accessor :mods, :dc, :string

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_optional_arg2)

        self.string = trim_arg(args.arg1)
        mod_list = args.arg1.gsub("-", "+-").gsub("--","-").split("+")
        self.mods = mod_list.map { |v| v.strip }

        self.dc = args.arg2 ? args.arg2.to_i : nil
      end

      def check_valid_dc
        return nil if !self.dc
        if self.dc.between?(5,50)
          return nil
        else
          return t('pf2e.dc_must_be_integer')
        end
      end

      def required_args
        [ self.mods ]
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
          Scene.emit_pose(Game.master.system_character,roll_msg,true,false,nil,true)

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
