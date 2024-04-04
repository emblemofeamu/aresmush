module AresMUSH
  module Pf2e
    class PF2AwardXPCmd
      include CommandHandler

      attr_accessor :target, :award, :reason

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2_slash_optional_arg3)

        self.target = trim_arg(args.arg1)
        self.award = integer_arg(args.arg2)
        self.reason = trim_arg(args.arg3).slice(0,50) if args.arg3
      end

      def required_args
        [ self.target, self.award ]
      end

      def check_can_award
        return nil if enactor.has_permission?('award_xp')
        return t('dispatcher.not_allowed')
      end

      def check_valid_award
        return nil unless self.award.zero?
        return t('pf2e.bad_value', :item => 'XP award')
      end

      def handle
        awardee = Pf2e.get_character(self.target, enactor)

        if !awardee
          client.emit_failure t('pf2e.not_found')
          return
        end

        Pf2e.award_xp(awardee, self.award)

        Pf2e.record_xp_history(awardee, enactor.name, self.award, self.reason)

        client.emit_success t('pf2e.xp_awarded', :awardee => awardee.name, :award => self.award)
      end

    end
  end
end
