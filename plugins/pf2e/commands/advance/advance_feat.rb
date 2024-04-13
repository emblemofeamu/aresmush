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
        feats_to_assign = to_assign['feats']

        key = self.type

        # Do they get one of that feat type this level?
        feat_slot = feats_to_assign[key]

        unless feat_slot
          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        # Do they have an open slot?

        open_slot = feat_slot.index("open")

        unless open_slot
          client.emit_failure t('pf2e.no_free', :element => key + " feat")
          return
        end

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

        # Do the thing.

        # Assignment hash.
        feat_slot.delete_at open_slot
        feat_slot << fname
        feats_to_assign[key] = feat_slot
        to_assign['feats'] = feats_to_assign

        # Advancement hash.
        feats_to_do = advancement['feats'] || {}
        type_feats_to_do = feats_to_do[key] || []
        type_feats_to_do << fname

        feats_to_do[key] = type_feats_to_do
        advancement['feats'] = feats_to_do

        # Check the new feat for any grants.
        has_grants = fdetails['grants']

        if has_grants
          client.emit_ooc t('pf2e.feat_grants_addl', :element => 'item. Check advance/review for details')
          grants = to_assign['grants']  || {}
          adv_grants = advancement['grants'] || {}

          assess = Pf2e.assess_feat_grants(has_grants)
          feat_adv_grants = assess['advance'] unless assess['advance'].empty?
          feat_grants = assess['assign'] unless assess['assign'].empty?

          grants[fname] = feat_grants if feat_grants
          adv_grants[fname] = feat_adv_grants if feat_adv_grants

          to_assign['grants'] = grants unless adv_grants.empty?
          advancement['grants'] = adv_grants unless adv_grants.empty?
        end

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save

        client.emit_success t('pf2e.adv_feat_selected', :feat => fname, :type => key)

      end

    end
  end
end
