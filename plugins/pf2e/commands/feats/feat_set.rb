module AresMUSH
  module Pf2e
    class PF2FeatSetCmd
      include CommandHandler

      attr_accessor :feat_type, :feat_name, :gate

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        if args.arg1
          find_gate = args.arg1.split("/")
          self.feat_type = downcase_arg(find_gate[0])
          self.gate = downcase_arg(find_gate[1])
        else
          self.feat_type = nil
          self.gate = nil
        end

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
        feat_types = [ "general", "skill", "archetype", "dedication", "charclass", "ancestry", "special" ]

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

        if self.feat_type == 'special' && self.gate == "deity's domain"
          handle_deity_domain
          return
        end

        if self.feat_type == 'special' && self.gate == 'canny acumen'
          to_assign = enactor.pf2_to_assign
          gate_options = to_assign['special feat'] || []

          unless gate_options.map(&:downcase).include?(self.gate)
            client.emit_failure t('pf2e.no_such_gate', :gate => self.gate)
            return
          end

          choice = self.feat_name.to_s.downcase
          choice_label = case choice
          when 'fortitude'
            'Fortitude'
          when 'reflex'
            'Reflex'
          when 'will'
            'Will'
          when 'perception'
            'Perception'
          else
            nil
          end

          unless choice_label
            client.emit_failure t('pf2e.canny_acumen_invalid')
            return
          end

          added_stats = if choice == 'perception'
            { 'perception' => 'expert' }
          else
            { 'saves' => { choice => 'expert' } }
          end

          current_stats = {}
          combat = enactor.combat
          current_stats['saves'] = combat.saves if combat&.saves
          current_stats['perception'] = combat.perception if combat&.perception
          merged_stats = Pf2e.merge_combat_stats(current_stats, added_stats)
          Pf2eCombat.update_combat_stats(enactor, merged_stats)

          new_gated_list = gate_options.reject { |g| g.to_s.casecmp?(self.gate) }
          to_assign['special feat'] = new_gated_list
          to_assign.delete('special feat') if to_assign['special feat'].empty?

          enactor.update(pf2_to_assign: to_assign)

          client.emit_success t('pf2e.adv_gate_selected', :gate => 'Canny Acumen', :choice => choice_label)
          return
        end

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

        # If feat_type is special, the feat_name specified will not be of that type, so skip this check.
        unless feat_type_list.include? self.feat_type or self.feat_type.include? "special"
          client.emit_failure t('pf2e.bad_feat_type', :type => self.feat_type, :keys => feat_type_list.sort.join(", "))
          return
        end

        # Does the enactor already have this feat?

        feat_list = enactor.pf2_feats

        if feat_list.include?(fname)
          client.emit_failure t('pf2e.already_has', :item => 'feat')
          return nil
        end

        # Does the enactor have one of the requested feat type free to select?

        to_assign = enactor.pf2_to_assign

        key = self.feat_type + " feat"

        # Special feats or 'gated feats' are feats granted by other feats that have specific limits
        # on what you can take.

        if key == 'special feat'
          # If it's a special feat, you have to specify which special.

          gate_options = to_assign[key]

          unless self.gate
            client.emit_failure t('pf2e.must_specify_gate', :options => gate_options.sort.join(", "))
            return
          end

          # Does that option exist in the list?
          Global.logger.debug "#{gate_options}"
          if !gate_options.nil?
            has_gate_option = gate_options.map(&:downcase).include? self.gate
          else
            has_gate_option = false
          end

          unless has_gate_option
            client.emit_failure t('pf2e.no_such_gate', :gate => self.gate)
            return
          end

          # These feats have an additional qualify check based on the specific gate.
          qualify = Pf2e.can_take_gated_feat?(enactor, fname, self.gate)
        else
          unless (to_assign[key] && to_assign[key].include?('open'))
            client.emit_failure t('pf2e.no_free', :element => key)
            return
          end

          qualify = Pf2e.can_take_feat?(enactor, fname)
        end

        # Does the enactor qualify to take this feat?

        unless qualify
          client.emit_failure t('pf2e.does_not_qualify')
          return nil
        end

        ##### VALIDATION SECTION END #####

        # Add to the feat list. Special feats again get their own processing.

        if key == 'special feat'
          use_ftype = fdeets['feat_type'].first.downcase

          sublist = feat_list[use_ftype] || []

          sublist << fname

          feat_list[use_ftype] = sublist

          new_gated_list = gate_options.reject { |g| g.to_s.casecmp?(self.gate) }
  
          to_assign[key] = new_gated_list
        else
          sublist = feat_list[self.feat_type] || []

          sublist << fname

          feat_list[self.feat_type] = sublist
          to_assign[key] = fname
        end

        # If they used their last special feat, remove that key.

        if to_assign.key?('special feat') && to_assign['special feat'].empty?
          to_assign.delete('special feat')
        end

        # Save the changes

        enactor.update(pf2_to_assign: to_assign)

        enactor.update(pf2_feats: feat_list)



        client.emit_success t('pf2e.feat_set_ok', :name => fname, :type => self.feat_type)

        # If a feat is a gated feat, serve a message that alerts them to look at cg/review.
        if fdeets['grants'] && fdeets['grants']['gated_feat']
          client.emit_ooc t('pf2e.cg_feat_grants_addl', :element => 'item')
        end

        # Feat-specific messages.
        if fname == "Deity's Domain"
          deity = enactor.pf2_faith['deity']
          deity_info = Global.read_config('pf2e_deities')[deity]
          domains = Array(deity_info ? deity_info['domains'] : []).compact

          if deity && !domains.empty?
            client.emit_ooc t('pf2e.deity_domain_select', :deity => deity, :domains => domains.sort.join(", "))
          end
        end

        # Some feats grant other things. Handle those here.

        granted_by_feat = fdeets['grants']

        charclass = fdeets['assoc_charclass'] ? fdeets['assoc_charclass'] : enactor.pf2_base_info['charclass']

        if granted_by_feat
          grant_message = Pf2e.do_feat_grants(enactor, granted_by_feat, charclass, client)
          grant_message.each {|msg| client.emit_ooc msg }
        end

        Pf2e.apply_init_magic_feat(enactor, fname, fdeets, client)

      end

      def handle_deity_domain
        to_assign = enactor.pf2_to_assign
        gate_options = to_assign['special feat'] || []

        unless self.gate && gate_options.map { |g| g.downcase }.include?(self.gate)
          client.emit_failure t('pf2e.no_such_gate', :gate => self.gate)
          return
        end

        deity = enactor.pf2_faith['deity']
        deity_info = Global.read_config('pf2e_deities')[deity]

        unless deity_info
          client.emit_failure "Your deity is not configured with domains."
          return
        end

        deity_domains = Array(deity_info['domains']).compact
        domain = deity_domains.find { |d| d.casecmp?(self.feat_name) }

        unless domain
          options = deity_domains.sort.join(", ")
          client.emit_failure "That is not one of your deity's domains. Domain options: #{options}."
          return
        end

        domains = Global.read_config('pf2e_magic')['domains']
        domain_info = domains[domain]

        unless domain_info && domain_info['initial']
          client.emit_failure "That domain is missing its initial domain spell."
          return
        end

        focus_type_by_class = Global.read_config('pf2e_magic')['focus_type_by_class']
        focus_type = focus_type_by_class[enactor.pf2_base_info['charclass']] || 'devotion'

        magic = PF2Magic.get_create_magic_obj(enactor)
        focus_spells = magic.focus_spells
        focus_list = focus_spells[focus_type] || []

        if focus_list.any? { |s| s && s.casecmp?(domain_info['initial']) }
          client.emit_failure "You already have that domain spell."
          return
        end

        focus_list << domain_info['initial']
        focus_spells[focus_type] = focus_list
        magic.update(focus_spells: focus_spells)

        new_gated_list = gate_options.reject { |g| g.casecmp?(self.gate) }
        to_assign['special feat'] = new_gated_list
        to_assign.delete('special feat') if to_assign['special feat'].empty?

        enactor.update(pf2_to_assign: to_assign)

        client.emit_success "Domain selected: #{domain}."
      end

    end

  end

end
