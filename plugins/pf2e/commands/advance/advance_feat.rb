module AresMUSH
  module Pf2e

    class PF2AdvanceFeatCmd
      include CommandHandler

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
        # Do they have one of that feat type to select?
        to_assign = enactor.pf2_to_assign

        key = self.type + " feat"

        # Available type is either "open" or something they already chose.
        feat_slot = to_assign[key]

        unless feat_slot
          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        # I do not check to see if they have an open one, and that is intentional here, because they should be able to replace it freely.

        # Qualification checks for all kinds of stuff, including whether the feat in question exists.

        qualifies = Pf2e.can_take_gated_feat?(enactor, self.value, self.type)

        unless qualifies
          client.emit_failure t('pf2e.feat_fails_gate')
          return
        end

        advancement = enactor.pf2_advancement

        # Check for grants.
        feat = Pf2e.get_feat_details(self.value)
        fname = feat[0]
        fdetails = feat[1]

        grants = to_assign[fname]  || {}
        adv_grants = advancement[fname] || {}

        # Check the new feat for any grants.
        has_grants = fdetails['grants']

        if has_grants
          client.emit_ooc t('pf2e.feat_grants_addl', :element => 'item. Check advance/review for details')
          assess = Pf2e.assess_feat_grants(has_grants)
          adv_grants = assess['advance'] unless assess['advance'].empty?
          grants = assess['assign'] unless assess['assign'].empty?
        end

        # Remove any old stuff and update the hashes.

        unless grants.empty?
          to_assign.delete feat_slot if to_assign.has_key? feat_slot
        end

        unless adv_grants.empty?
          advancement.delete feat_slot if advancement.has_key? feat_slot
        end

        to_assign[key] = fname
        advancement[key] = fname

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save

        client.emit_success t('pf2e.adv_feat_selected', :feat => fname, :type => key)

      end

    end
  end
end
