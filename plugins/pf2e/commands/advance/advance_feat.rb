module AresMUSH
  module Pf2e

    # Spends one of the feat slots this level handed out.
    #
    # The slot mechanics are Advancement::Feats and everything gaining a feat implies is
    # Advancement::FeatGain - which is also what a choice handing over a feat goes through, so
    # the two cannot drift apart again. What is left here is the four questions that need the
    # live sheet rather than the draft.
    class PF2AdvanceFeatCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :type, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.type = downcase_arg(args.arg1)
        self.value = downcase_arg(args.arg2)
      end

      def required_args
        [ self.type, self.value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        state = Pf2e::CharState.of(enactor)

        found = resolve_feat
        return unless found

        fname, fdetails = found

        # The draft's questions first, so the most specific complaint wins.
        failure = Pf2e::Advancement::Feats.check_slot(state, self.type, self.value, fdetails)
        return if Pf2e::CharState.emit_error!(client, failure)

        failure = check_against_sheet(fname, fdetails)
        if failure
          client.emit_failure failure
          return
        end

        outcome = Pf2e::Advancement::Feats.spend_slot(state, self.type, fname)
        return if Pf2e::CharState.emit_error!(client, outcome)

        # From here the draft hashes are handed to FeatGain to add to, then written once.
        to_assign = outcome.state['to_assign']
        advancement = enactor.pf2_advancement

        result = Pf2e::Advancement::FeatGain.apply(enactor, fname, fdetails,
          :bucket => self.type,
          :to_assign => to_assign,
          :advancement => advancement,
          :client => client)

        enactor.pf2_to_assign = to_assign
        enactor.pf2_advancement = advancement
        enactor.save

        client.emit_success t('pf2e.adv_feat_selected', :feat => fname, :type => self.type.gsub("charclass", "class"))

        Pf2e::Advancement::FeatGain.emit!(client, result[:messages])

        # Work that had to wait for the draft to be written - staging an auto-resolved choice
        # re-reads and saves the character.
        result[:after_save].each { |deferred| Pf2e::Advancement::FeatGain.emit!(client, deferred.call) }
      end

      private

      # [ name, details ], or nil having already told the player what was wrong.
      def resolve_feat
        found = Pf2e.get_feat_details(self.value)

        return found unless found.is_a?(String)

        if found == 'ambiguous'
          client.emit_failure t('pf2e.multiple_feat_matches',
            :options => Pf2e.get_feat_match_options(self.value).join(", "))
        else
          client.emit_failure t('pf2e.bad_feat_name', :name => self.value)
        end

        nil
      end

      # The questions only the live sheet can answer, in the order they were asked before.
      # Each returns a rendered message or nil, because these helpers already render.
      def check_against_sheet(fname, fdetails)
        if Pf2e::Advancement::FeatGain.dedication?(fdetails) && !Pf2e.dedication_archetype_ready?(enactor)
          return t('pf2e.adv_dedication_requires_archetype_feats')
        end

        # No double-dipping on the base class or an archetype already held, per Paizo RAW.
        return t('pf2e.does_not_qualify') unless Pf2e.dedication_allowed?(enactor, fdetails)

        # Already held, and if so may it be taken again at the level being gained?
        repeat = Pf2e.feat_repeat_block(enactor, fname, fdetails, nil, enactor.pf2_level + 1)
        return repeat if repeat

        prereqs = fdetails['prereq']

        return nil unless prereqs
        return nil if Pf2e.meets_prereqs?(enactor, prereqs, enactor.pf2_level + 1)

        Pf2e.explain_feat_block(enactor, fdetails) || t('pf2e.feat_fails_prereq')
      end

    end
  end
end
