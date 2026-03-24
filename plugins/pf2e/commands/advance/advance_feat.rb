module AresMUSH
  module Pf2e

    class PF2AdvanceFeatCmd
      include CommandHandler

      attr_accessor :type, :value, :gate

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        if args.arg1
          find_gate = args.arg1.split("/")
          self.type = downcase_arg(find_gate[0])
          self.gate = downcase_arg(find_gate[1])
        else
          self.type = nil
          self.gate = nil
        end

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
        if self.type == 'special'
          handle_gated_feat
          return
        end

        if self.type == 'class'
          client.emit_failure t('pf2e.adv_dont_use_class_for_class_feats', :feat => self.value) 
          return
        end

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

        advancement = enactor.pf2_advancement

        # Check for grants.
        feat = Pf2e.get_feat_details(self.value)

        if feat.is_a?(String)
          if feat == 'ambiguous'
            options = Pf2e.get_feat_match_options(self.value)
            msg = t('pf2e.multiple_feat_matches', :options => options.join(", "))
          else
            msg = t('pf2e.bad_feat_name', :name => self.value)
          end

          client.emit_failure msg
          return
        end

        fname = feat[0]
        fdetails = feat[1]

        # Qualification checks for all kinds of stuff, including whether the feat in question exists.
        qualifies = Pf2e.can_take_gated_feat?(enactor, fname, self.type)

        unless qualifies
          client.emit_failure t('pf2e.feat_fails_gate')
          return
        end

        # Check prerequisites
        prereqs = fdetails["prereq"]

        if prereqs
          # Account for character level during advancement
          cl = enactor.pf2_level
          cl = cl + 1  # Already advancing, so +1 to level for prereq purposes

          meets_prereqs = Pf2e.meets_prereqs?(enactor, prereqs, cl)

          unless meets_prereqs
            client.emit_failure t('pf2e.feat_fails_prereq')
            return
          end
        end

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

        # Archetype and dedication handling begins here.
        if fdetails['feat_type']&.include?('Dedication')
          # They picked a dedication feat, so automatically assign the associated archetype.
          assoc_archetypes = fdetails['assoc_archetype']
          if assoc_archetypes && !assoc_archetypes.empty? && !to_assign['archetype']
            # Automatically assign the archetype to advancement assignment and to an open archetype slot on the character.
            archetype = assoc_archetypes.first
            to_assign['archetype'] = archetype
            archetype_slot = enactor.pf2_archetypeinfo || {}
            if !archetype_slot['archetype1'] || archetype_slot['archetype1'].empty?
              archetype_slot['archetype1'] = archetype
            elsif !archetype_slot['archetype1'].empty? && (!archetype_slot['archetype2'] || archetype_slot['archetype2'].empty?)
              archetype_slot['archetype2'] = archetype
            elsif !archetype_slot['archetype1'].empty? && !archetype_slot['archetype2'].empty? && (!archetype_slot['archetype3'] || archetype_slot['archetype3'].empty?)
              archetype_slot['archetype3'] = archetype
            elsif !archetype_slot['archetype1'].empty? && !archetype_slot['archetype2'].empty? && !archetype_slot['archetype3'].empty? && (!archetype_slot['archetype4'] || archetype_slot['archetype4'].empty?)
              archetype_slot['archetype4'] = archetype
            end
            enactor.pf2_archetypeinfo = archetype_slot
            
            archetype_info = Global.read_config('pf2e_archetype', archetype) || {}
            archetype_features_info = archetype_info['initial_dedication'] || {}
            archetype_key_abilities = Array(archetype_info['key_abil']).compact.map { |a| a.to_s.strip }.reject(&:empty?).uniq
            base_class_key = enactor.pf2_base_info['charclass']
            if archetype_info['use_deity']
              existing_deity = enactor.pf2_faith['deity']

              if !existing_deity.blank?
                to_assign['archetype deity'] = existing_deity
                advancement['archetype_deity'] = existing_deity
                client.emit_ooc t('pf2e.adv_archetype_deity_assigned', :deity => existing_deity, :archetype => archetype)

                divine_skill = Global.read_config('pf2e_deities', existing_deity, 'divine_skill')
                if divine_skill && !divine_skill.to_s.strip.empty?
                  pending_skills = Array(to_assign['raise skill'])
                  pending_skills << divine_skill
                  pending_skills = pending_skills.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq
                  to_assign['raise skill'] = pending_skills

                  pending_adv_skills = Array(advancement['raise skill'])
                  pending_adv_skills << divine_skill
                  pending_adv_skills = pending_adv_skills.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq
                  advancement['raise skill'] = pending_adv_skills

                  client.emit_ooc t('pf2e.adv_archetype_deity_skill_assigned', :deity => existing_deity, :skill => divine_skill)
                end
              else
                # If the archetype has a deity choice, open it up.
                to_assign['archetype deity'] = 'open'
                client.emit_ooc t('pf2e.adv_archetype_deity_select', :archetype => archetype)
              end
            end
            # Handle automatic skill increases from archetype, if present, and merge them with any other pending skill increases.
            archetype_skills = Array(archetype_features_info['skills']).compact.map { |s| s.to_s.strip }.reject(&:empty?)
            if !archetype_skills.empty?
              pending_skills = Array(to_assign['raise skill'])

              pending_skills += archetype_skills
              pending_skills = pending_skills.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq

              to_assign['raise skill'] = pending_skills

              pending_adv_skills = Array(advancement['raise skill'])
              pending_adv_skills += archetype_skills
              pending_adv_skills = pending_adv_skills.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq

              advancement['raise skill'] = pending_adv_skills
              client.emit_ooc t('pf2e.adv_archetype_skills_assigned', :skills => archetype_skills.join(", "))
            end
            archetype_skill_choices = Array(archetype_features_info['skill choice']).compact.map { |s| s.to_s.strip }.reject(&:empty?)
            if !archetype_skill_choices.empty?
              to_assign['raise skill choice'] ||= []
              to_assign['raise skill choice'] += archetype_skill_choices
              to_assign['raise skill choice'].uniq!
              client.emit_ooc t('pf2e.adv_archetype_open_skill_assigned', :skills => archetype_skill_choices.join(", "))
            end
            # Handle automatic feat additions from archetype, if present, and merge them with any other pending feat additions.
            archetype_feats = Array(archetype_features_info['feat']).compact.map { |f| f.to_s.strip }.reject(&:empty?)
            if !archetype_feats.empty?
              to_assign['feats'] ||= {}
              pending_feats = Array(to_assign['feats']['general'])

              pending_feats += archetype_feats
              pending_feats = pending_feats.compact.map { |f| f.to_s.strip }.reject(&:empty?).uniq

              to_assign['feats']['general'] = pending_feats

              feats_to_do = advancement['feats'] || {}
              general_feats_to_do = Array(feats_to_do['general'])
              general_feats_to_do += archetype_feats
              general_feats_to_do = general_feats_to_do.compact.map { |f| f.to_s.strip }.reject(&:empty?).uniq

              feats_to_do['general'] = general_feats_to_do
              advancement['feats'] = feats_to_do
              client.emit_ooc t('pf2e.adv_archetype_feats_assigned', :feats => archetype_feats.join(", "))
            end
            # Handle open feat choices from archetype, if present, and merge them with any other pending feat choices.
            archetype_choose_feats = Array(archetype_features_info['choose_feat']).compact.map { |f| f.to_s.strip }.reject(&:empty?)
            if !archetype_choose_feats.empty?
              to_assign['feats'] ||= {}

              archetype_choose_feats.each do |feat_type|
                feat_slots = Array(to_assign['feats'][feat_type])
                feat_slots << "open"
                to_assign['feats'][feat_type] = feat_slots
              end

              if archetype_choose_feats.include?('skill')
                client.emit_ooc t('pf2e.adv_archetype_open_skill_feat_assigned')
              end
            end
            # Handle combat_stats from archetype, if present.
            archetype_combat = (archetype_features_info['combat_stats'] || {}).dup
            if !archetype_combat.empty?
              archetype_class_dc_prof = archetype_combat.delete('archetype_class_dc')

              if archetype_class_dc_prof
                advancement['combat_stats'] ||= {}
                advancement['combat_stats']['archetype_class_dcs'] ||= {}
                advancement['combat_stats']['archetype_class_dcs'][archetype] ||= {}
                advancement['combat_stats']['archetype_class_dcs'][archetype]['prof'] = archetype_class_dc_prof

                if archetype_key_abilities.size > 1
                  to_assign['archetype key ability'] = archetype_key_abilities
                  client.emit_ooc t('pf2e.adv_archetype_key_ability_select', :archetype => archetype, :options => archetype_key_abilities.join(", "))
                else
                  selected_key_ability = archetype_key_abilities.first || enactor.combat&.key_abil
                  if selected_key_ability
                    advancement['combat_stats']['archetype_class_dcs'][archetype]['key_abil'] = selected_key_ability
                  end
                end
              end

              if !archetype_combat.empty?
              advancement['combat_stats'] ||= {}
              advancement['combat_stats'] = Pf2e.merge_combat_stats(advancement['combat_stats'], archetype_combat)
              client.emit_ooc t('pf2e.adv_archetype_combat_stats_assigned')
              end
            end
            # Handle magic_stats from archetype, if present.
            archetype_magic = archetype_features_info['magic_stats'] || {}
            if !archetype_magic.empty?
              assess_magic = PF2Magic.assess_magic_stats(enactor, archetype_magic)

              advancement['magic_stats'] ||= {}
              Pf2e.wrap_adv_magic_stats(advancement, base_class_key)
              advancement['magic_stats'][archetype] = assess_magic['magic_stats']

              magic_options = assess_magic['magic_options'] || {}
              if !magic_options.empty?
                magic_options.each_pair do |k, v|
                  Pf2e.wrap_magic_assign(to_assign, k, base_class_key)
                  to_assign[k] ||= {}
                  to_assign[k][archetype] = v
                end
                client.emit_ooc t('pf2e.adv_item_magic', :options => magic_options.keys.sort.join(" and "))
              end
            end
            # Handle archetype features, if present.
            archetype_features = Array(archetype_features_info['archetype_feature']).compact.map { |f| f.to_s.strip }.reject(&:empty?)
            if !archetype_features.empty?
              features = enactor.pf2_features
              features['archetype_features'] ||= []
              features['archetype_features'].concat(archetype_features).uniq!
              enactor.pf2_features = features
              client.emit_ooc t('pf2e.adv_archetype_features_assigned', :features => archetype_features.join(", "))
            end

            # Check if the archetype has specialties to choose from.
            archetype_specialties = Global.read_config('pf2e_archetype_specialty', archetype)
            
            if archetype_specialties && !archetype_specialties.empty?
              # If so, opens up archetype specialty selection in advancement assignment.
              to_assign['archetype_specialty'] = 'open'
              archetype_specialty_list = archetype_specialties.keys.sort.join(", ")
              client.emit_ooc t('pf2e.adv_archetype_specialty_select', :archetype => archetype, :options => archetype_specialty_list)
            end
          end
        end

        # Check the new feat for any grants.
        has_grants = fdetails['grants']

        if has_grants
          client.emit_ooc t('pf2e.advancement_feat_grants_addl', :element => 'item')
          grants = to_assign['grants']  || {}
          adv_grants = advancement['grants'] || {}

          assess = Pf2e.assess_feat_grants(has_grants)
          feat_adv_grants = assess['advance'] unless assess['advance'].empty?
          feat_grants = assess['assign'] unless assess['assign'].empty?

          grants[fname] = feat_grants if feat_grants
          adv_grants[fname] = feat_adv_grants if feat_adv_grants

          to_assign['grants'] = grants unless grants.empty?
          advancement['grants'] = adv_grants unless adv_grants.empty?
        end

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save

        client.emit_success t('pf2e.adv_feat_selected', :feat => fname, :type => key.gsub("charclass", "class"))

        # Display notification about archetype if the user selects a Dedication feat.
        if fdetails['feat_type']&.include?('Dedication')
          assoc_archetypes = fdetails['assoc_archetype']
          if assoc_archetypes && !assoc_archetypes.empty?
            client.emit_ooc t('pf2e.adv_archetype_assigned', :archetype => assoc_archetypes.first)
          end
        end
      end

      def handle_gated_feat
        to_assign = enactor.pf2_to_assign
        grants = to_assign['grants'] || {}

        gate_options = grants.values.filter_map do |grant_info|
          grant_info.is_a?(Hash) ? grant_info['gated_feat'] : nil
        end

        if gate_options.empty?
          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        unless self.gate
          client.emit_failure t('pf2e.must_specify_gate', :options => gate_options.sort.join(", "))
          return
        end

        unless gate_options.any? { |g| g.to_s.casecmp?(self.gate) }
          client.emit_failure t('pf2e.no_such_gate', :gate => self.gate)
          return
        end

        if self.gate.to_s.casecmp?('canny acumen')
          choice = self.value.to_s.downcase
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

          advancement = enactor.pf2_advancement
          advancement['combat_stats'] ||= {}
          advancement['combat_stats'] = Pf2e.merge_combat_stats(advancement['combat_stats'], added_stats)
          enactor.pf2_advancement = advancement

          grants.each_pair do |grant_feat, grant_info|
            next unless grant_info.is_a?(Hash)
            next unless grant_info['gated_feat']&.casecmp?(self.gate)

            grant_info.delete('gated_feat')
            if grant_info.empty?
              grants.delete(grant_feat)
            end
            break
          end

          if grants.empty?
            to_assign.delete('grants')
          else
            to_assign['grants'] = grants
          end

          if to_assign['gated_feat_options']
            matched_gate = to_assign['gated_feat_options'].keys.find { |g| g.to_s.casecmp?(self.gate) }
            to_assign['gated_feat_options'].delete(matched_gate) if matched_gate
            to_assign.delete('gated_feat_options') if to_assign['gated_feat_options'].empty?
          end

          enactor.pf2_to_assign = to_assign
          enactor.save

          client.emit_success t('pf2e.adv_gate_selected', :gate => 'Canny Acumen', :choice => choice_label)
          return
        end

        feat = Pf2e.get_feat_details(self.value)

        if feat.is_a?(String)
          if feat == 'ambiguous'
            options = Pf2e.get_feat_match_options(self.value)
            msg = t('pf2e.multiple_feat_matches', :options => options.join(", "))
          else
            msg = t('pf2e.bad_feat_name', :name => self.value)
          end

          client.emit_failure msg
          return
        end

        fname = feat[0]
        fdetails = feat[1]

        qualifies = Pf2e.can_take_gated_feat?(enactor, fname, self.gate)

        unless qualifies
          client.emit_failure t('pf2e.feat_fails_gate')
          return
        end

        prereqs = fdetails['prereq']
        if prereqs
          cl = enactor.pf2_level + 1
          meets_prereqs = Pf2e.meets_prereqs?(enactor, prereqs, cl)
          unless meets_prereqs
            client.emit_failure t('pf2e.feat_fails_prereq')
            return
          end
        end

        advancement = enactor.pf2_advancement
        feats_to_do = advancement['feats'] || {}
        type_key = fdetails['feat_type']&.first&.downcase || 'general'
        type_feats_to_do = feats_to_do[type_key] || []
        type_feats_to_do << fname
        feats_to_do[type_key] = type_feats_to_do
        advancement['feats'] = feats_to_do

        grants.each_pair do |grant_feat, grant_info|
          next unless grant_info.is_a?(Hash)
          next unless grant_info['gated_feat']&.casecmp?(self.gate)

          grant_info.delete('gated_feat')
          if grant_info.empty?
            grants.delete(grant_feat)
          end
          break
        end

        if grants.empty?
          to_assign.delete('grants')
        else
          to_assign['grants'] = grants
        end

        if to_assign['gated_feat_options']
          matched_gate = to_assign['gated_feat_options'].keys.find { |g| g.to_s.casecmp?(self.gate) }
          to_assign['gated_feat_options'].delete(matched_gate) if matched_gate
          to_assign.delete('gated_feat_options') if to_assign['gated_feat_options'].empty?
        end

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save

        client.emit_success t('pf2e.adv_feat_selected', :feat => fname, :type => type_key)
      end

    end
  end
end
