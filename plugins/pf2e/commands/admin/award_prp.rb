module AresMUSH
  module Pf2e
    class PF2AwardPRPCmd
      include CommandHandler

      attr_accessor :target_list, :prp_type, :target_type

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.target_list = trimmed_list_arg(args.arg3)
        self.prp_type = downcase_arg(args.arg1)
        self.target_type = downcase_arg(args.arg2)
      end

      def required_args
        [ self.target_list, self.prp_type, self.target_type ]
      end

      def check_can_award
        return nil if enactor.has_permission?('award_xp')
        return t('dispatcher.not_allowed')
      end

      def check_valid_prp_type
        types = [ 'standard', 'dc']

        return nil if types.include? self.prp_type
        return t('pf2e.bad_prp_type')
      end

      def check_valid_target_type
        types = ['player', 'runner']

        return nil if types.include? self.target_type
        return t('pf2e.bad_target_type')
      end

      def handle
        string = self.prp_type + "_" + self.target_type

        reward_list = Global.read_config('pf2e_rewards', 'prp_reward_types', string)

        reward_hash = Global.read_config('pf2e_rewards', reward_list)

        # Find all the character objects and warn the admin if any not found.

        targets = self.target_list.map { |c| Pf2e.get_character(c, enactor) }

        targets = targets.compact

        targets.each do |t|
          level = t.pf2_level

          rewards = reward_hash[level]

          xp = rewards["xp"]
          money = rewards['money']

          # Both of these record the transaction and move the total together, so the award is
          # attributed to whoever ran the PRP rather than to System.
          Pf2e.award_xp(t, xp, enactor.name, "PRP Award")
          Pf2egear.pay_player(t, money, enactor.name, "PRP Award")
        end

        ttype = self.target_type == "player" ? self.target_type + "s" : self.target_type
        ptype = self.prp_type == "dc" ? self.prp_type.upcase : self.prp_type
        names = targets.map { |t| t.name }.sort.join(", ")

        client.emit_success t('pf2e.prp_rewarded_ok',
          :targets => names,
          :ptype => ptype,
          :ttype => ttype
          )


      end

    end
  end
end
