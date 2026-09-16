module AresMUSH
  module Pf2e
    class PF2FeatSetCmd
      include CommandHandler

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
        if enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def check_valid_feat_type
        feat_types = [ "general", "skill", "archetype", "dedication", "charclass", "ancestry" ]

        return nil if feat_types.include?(self.feat_type)

        return t('pf2e.bad_feat_type', :type => self.feat_type, :keys => feat_types.sort.join(", "))
      end

      def check_feat_type_present
        return nil if self.feat_type

        return t('pf2e.feat_type_missing')
      end

      def check_skill_lock
        return t('pf2e.lock_skills_first') unless enactor.pf2_skills_locked
        return nil
      end

      def handle
        ##### VALIDATION SECTION START #####
        # Is this actually a feat?

        feat_check = Pf2e.get_feat_details(self.feat_name)

        if feat_check.is_a?(String)
          if feat_check == 'ambiguous'
            options = Pf2e.get_feat_match_options(self.feat_name)
            msg = t('pf2e.multiple_feat_matches', :options => options.join(", "))
          else
            msg = t('pf2e.bad_feat_name', :name => self.feat_name)
          end

          client.emit_failure msg
          return
        end

        fname = feat_check[0]
        fdeets = feat_check[1]

        # Is that feat of the type they asked for?
        feat_type_list = fdeets['feat_type'].map { |f| f.downcase }

        unless feat_type_list.include? self.feat_type
          client.emit_failure t('pf2e.bad_feat_type', :type => self.feat_type, :keys => feat_type_list.sort.join(", "))
          return
        end

        # Does the enactor already have this feat, and if so may they take it again?

        feat_list = enactor.pf2_feats

        repeat_block = Pf2e.feat_repeat_block(enactor, fname, fdeets)

        if repeat_block
          client.emit_failure repeat_block
          return nil
        end

        # Does the enactor have one of the requested feat type free to select?

        to_assign = enactor.pf2_to_assign

        key = self.feat_type + " feat"

        unless (to_assign[key] && to_assign[key].include?('open'))
          client.emit_failure t('pf2e.no_free', :element => key)
          return
        end

        # Does the enactor qualify to take this feat?

        unless Pf2e.can_take_feat?(enactor, fname)
          client.emit_failure Pf2e.explain_feat_block(enactor, fdeets) || t('pf2e.does_not_qualify')
          return nil
        end

        ##### VALIDATION SECTION END #####

        # Add to the feat list.

        sublist = feat_list[self.feat_type] || []

        sublist << fname

        feat_list[self.feat_type] = sublist
        to_assign[key] = fname

        # Save the changes

        enactor.update(pf2_to_assign: to_assign)

        enactor.update(pf2_feats: feat_list)




        client.emit_success t('pf2e.feat_set_ok', :name => fname, :type => self.feat_type)

        # A feat carrying its own choice opens it for the player to resolve with cg/option.
        choice_block = Pf2e.feat_choice_def(fdeets)
        instance = Pf2e.feat_taken_count(enactor, fname)

        choice_block = nil unless Pf2e.feat_choice_opens_at?(choice_block, instance)

        if choice_block && Pf2e.auto_choice?(choice_block)
          # For automatic choices
          auto_label = Pf2e.auto_choice_label(enactor, choice_block)

          if auto_label
            choice_assign = enactor.pf2_to_assign
            Pf2e.open_feat_choice(choice_assign, fname)
            enactor.update(pf2_to_assign: choice_assign)

            Pf2e.apply_feat_choice(enactor, fname, choice_block, auto_label, client).each { |msg| client.emit_ooc msg }

            client.emit_ooc t('pf2e.choice_auto_resolved', :choice => fname, :value => auto_label)
          else
            client.emit_ooc t('pf2e.choice_auto_none', :choice => fname)
          end
        elsif choice_block
          choice_assign = enactor.pf2_to_assign
          Pf2e.open_feat_choice(choice_assign, fname)
          enactor.update(pf2_to_assign: choice_assign)

          client.emit_ooc t('pf2e.choice_opened',
            :choice => fname,
            :summary => Pf2e.choice_summary(choice_block),
            :cmd => Pf2e.choice_info_cmd(enactor))
        end

        # Some feats grant other things. Handle those here.

        granted_by_feat = fdeets['grants']

        charclass = fdeets['assoc_charclass'] ? fdeets['assoc_charclass'] : enactor.pf2_base_info['charclass']

        if granted_by_feat
          grant_message = Pf2e.do_feat_grants(enactor, granted_by_feat, charclass, client)
          grant_message.each {|msg| client.emit_ooc msg }
        end

        # Level clauses the character already qualifies for. Chargen is normally level 1, so this only fires for a respec, where the character rebuilds at their existing level.
        Pf2e.feat_at_level_catch_up(fdeets, enactor.pf2_level).each do |lvl, payload|
          Pf2e.do_feat_grants(enactor, payload, charclass, client).each { |msg| client.emit_ooc msg }

          client.emit_ooc t('pf2e.feat_level_clause_applied', :feat => fname, :level => lvl)
        end

        # Feats that grant magic carry a magic_stats block of their own rather than nesting it under 'grants', so it needs the same handling to reach the character's magic object.
        magic_message = Pf2e.do_feat_magic_stats(enactor, fdeets, charclass, client)
        magic_message.each {|msg| client.emit_ooc msg }

        Pf2e.apply_init_magic_feat(enactor, fname, fdeets, client)

      end

    end

  end

end
