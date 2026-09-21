module AresMUSH
  module Pf2e

    # Spends one of the feat slots chargen handed out.
    #
    # The same three pieces as `advance/feat`: Advancement::Feats for whether the feat may go in
    # the slot, Advancement::FeatGain for everything gaining it implies, and four questions that
    # need the live sheet rather than the draft. The two commands differ in which level a
    # prerequisite is measured against, and in nothing else.
    class PF2FeatSetCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :feat_type, :feat_name

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.feat_type = downcase_arg(args.arg1)
        self.feat_name = upcase_arg(args.arg2)
      end

      def required_args
        [ self.feat_type, self.feat_name ]
      end

      def check_chargen_or_advancement
        return t('pf2e.only_in_chargen') if enactor.chargen_locked || enactor.is_admin?
        return t('chargen.not_started') if !Pf2e.in_chargen?(enactor)

        nil
      end

      def check_feat_type_present
        return nil if self.feat_type

        t('pf2e.feat_type_missing')
      end

      def check_skill_lock
        return nil if enactor.pf2_skills_locked

        t('pf2e.lock_skills_first')
      end

      def handle
        found = resolve_feat
        return unless found

        fname, fdetails = found
        state = Pf2e::CharState.of(enactor)

        failure = Pf2e::Advancement::Feats.check_slot(state, self.feat_type, self.feat_name, fdetails)
        return if Pf2e::CharState.emit_error!(client, failure)

        repeat = Pf2e.feat_repeat_block(enactor, fname, fdetails)
        if repeat
          client.emit_failure repeat
          return
        end

        unless Pf2e.can_take_feat?(enactor, fname)
          client.emit_failure Pf2e.explain_feat_block(enactor, fdetails) || t('pf2e.does_not_qualify')
          return
        end

        outcome = Pf2e::Advancement::Feats.spend_slot(state, self.feat_type, fname)
        return if Pf2e::CharState.emit_error!(client, outcome)

        to_assign = outcome.state['to_assign']
        advancement = enactor.pf2_advancement

        result = Pf2e::Advancement::FeatGain.apply(enactor, fname, fdetails,
          :bucket => self.feat_type,
          :to_assign => to_assign,
          :advancement => advancement,
          :client => client)

        enactor.pf2_to_assign = to_assign
        enactor.pf2_advancement = advancement
        enactor.save

        client.emit_success t('pf2e.feat_set_ok', :name => fname, :type => self.feat_type)

        Pf2e::Advancement::FeatGain.emit!(client, result[:messages])
        result[:after_save].each { |deferred| Pf2e::Advancement::FeatGain.emit!(client, deferred.call) }
      end

      private

      # [ name, details ], or nil having already told the player what was wrong.
      def resolve_feat
        found = Pf2e.get_feat_details(self.feat_name)

        return found unless found.is_a?(String)

        client.emit_failure Pf2e.feat_lookup_failure(self.feat_name, found)

        nil
      end
    end
  end
end
