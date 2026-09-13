module AresMUSH
  module Pf2e

    class PF2TakeTenCommand
      include CommandHandler

      attr_accessor :skill, :dc

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_optional_arg2)

        self.skill = trim_arg(args.arg1)
        self.dc = args.arg2 ? args.arg2.to_i : nil
      end

      def required_args
        [ self.skill ]
      end

      def check_valid_dc
        return nil if !self.dc
        return nil if self.dc.between?(5,50)

        t('pf2e.dc_must_be_integer')
      end

      def handle
        matches = Pf2e.match_char_skills(enactor, self.skill)

        if matches.empty?
          client.emit_failure t('pf2e.take_ten_no_skill', :skill => self.skill)
          return
        end

        if matches.size > 1
          client.emit_failure t('pf2e.take_ten_ambiguous', :skill => self.skill, :options => matches.join(", "))
          return
        end

        skill_name = matches.first

        if !Pf2e.take_ten_feat(enactor, skill_name)
          assurance = Pf2e.assurance_skills(enactor)

          if assurance.empty?
            client.emit_failure t('pf2e.take_ten_no_feat', :skill => skill_name)
          else
            client.emit_failure t('pf2e.take_ten_not_chosen', :skill => skill_name, :options => assurance.join(", "))
          end

          return
        end

        bonus = Pf2e.take_ten_bonus(enactor, skill_name)
        total = 10 + bonus

        degree = self.dc ? Pf2e.get_degree([ 'taketen' ], [], total, self.dc) : ""

        dc_string = self.dc ? "against DC #{self.dc} " : ""

        roll_msg = t('pf2e.take_ten_roll',
                  :roller => "%xh#{enactor.name}%xn",
                  :string => skill_name,
                  :dc => dc_string,
                  :bonus => bonus,
                  :result => total,
                  :degree => degree
                )

        Pf2e.broadcast_roll(enactor_room, roll_msg)

        Global.logger.info "PF2 ROLL: #{roll_msg}"
      end

    end
  end
end
