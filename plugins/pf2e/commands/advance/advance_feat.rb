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

        if fdetails['feat_type']&.include?('Dedication') && !Pf2e.dedication_archetype_ready?(enactor)
          client.emit_failure t('pf2e.adv_dedication_requires_archetype_feats')
          return
        end

        # Is the feat actually of the type they are filling?
        feat_types = Array(fdetails['feat_type']).compact.map { |f| f.to_s.downcase }

        unless feat_types.include?(self.type)
          client.emit_failure t('pf2e.bad_feat_type', :type => self.type, :keys => feat_types.sort.join(", "))
          return
        end

        # No double-dipping on base class / dedication, per Paizo RAW.
        unless Pf2e.dedication_allowed?(enactor, fdetails)
          client.emit_failure t('pf2e.does_not_qualify')
          return
        end

        # Do they already have it, and if so, may they take it again? 
        repeat_block = Pf2e.feat_repeat_block(enactor, fname, fdetails, nil, enactor.pf2_level + 1)

        if repeat_block
          client.emit_failure repeat_block
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
            client.emit_failure Pf2e.explain_feat_block(enactor, fdetails) || t('pf2e.feat_fails_prereq')
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
                  result = Pf2e.add_training_skills(enactor, [divine_skill], to_assign, advancement)
                  if result[:assigned].any?
                    client.emit_ooc t('pf2e.adv_archetype_deity_skill_assigned', :deity => existing_deity, :skill => divine_skill)
                  end
                  if result[:open_count].to_i > 0 || result[:open_lore_count].to_i > 0
                    client.emit_ooc t('pf2e.adv_duplicate_skill_open', :item => 'deity')
                  end
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
              result = Pf2e.add_training_skills(enactor, archetype_skills, to_assign, advancement)
              if result[:assigned].any?
                client.emit_ooc t('pf2e.adv_archetype_skills_assigned', :skills => result[:assigned].join(", "))
              end
              if result[:open_count].to_i > 0 || result[:open_lore_count].to_i > 0
                client.emit_ooc t('pf2e.adv_duplicate_skill_open', :item => 'archetype')
              end
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
                Pf2e.magic_option_messages(magic_options.keys).each { |msg| client.emit_ooc msg }
              end
            end
            # Handle archetype features, if present.
            archetype_features = Array(archetype_features_info['archetype_feature']).compact.map { |f| f.to_s.strip }.reject(&:empty?)
            if !archetype_features.empty?
              features = enactor.pf2_features
              held = features['archetype_features'] ||= []

              added = archetype_features.reject { |f| held.any? { |h| h.to_s.casecmp?(f.to_s) } }

              held.concat(added)
              enactor.pf2_features = features

              advancement['archetype_features'] = Array(advancement['archetype_features']) + added unless added.empty?

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

            # Handle sanctification for Champion Archetype and Cleric Archetype.
            if archetype == 'Champion Archetype' || archetype == 'Cleric Archetype'
              current_sanctification = enactor.pf2_faith['sanctification']

              if archetype == 'Champion Archetype'
                if base_class_key.casecmp?('Cleric')
                  # Clerics can't change their sanctification via archetype.
                  client.emit_ooc t('pf2e.adv_archetype_sanctification_locked', :charclass => base_class_key)
                else
                  archetype_allowed = Array(Global.read_config('pf2e_archetype', archetype, 'allowed_sanctifications'))
                  if !current_sanctification.blank? && archetype_allowed.any? { |s| s.casecmp?(current_sanctification) }
                    to_assign['archetype_sanctification'] = current_sanctification
                    advancement['archetype_sanctification'] = current_sanctification
                    client.emit_ooc t('pf2e.adv_archetype_sanctification_auto', :sanctification => current_sanctification, :archetype => archetype)
                  else
                    to_assign['archetype_sanctification'] = 'open'
                    client.emit_ooc t('pf2e.adv_archetype_sanctification_select', :archetype => archetype, :options => archetype_allowed.join(", "))
                  end
                end
              elsif archetype == 'Cleric Archetype'
                if base_class_key.casecmp?('Champion')
                  # Champions taking Cleric Archetype must sanctify as Holy.
                  if !current_sanctification.blank? && current_sanctification.casecmp?('Holy')
                    to_assign['archetype_sanctification'] = 'Holy'
                    advancement['archetype_sanctification'] = 'Holy'
                    client.emit_ooc t('pf2e.adv_archetype_sanctification_auto', :sanctification => 'Holy', :archetype => archetype)
                  else
                    to_assign['archetype_sanctification'] = 'open'
                    client.emit_ooc t('pf2e.adv_archetype_sanctification_champion_cleric')
                  end
                else
                  deity = to_assign['archetype deity']
                  deity = nil if deity.blank? || deity.to_s.casecmp?('open')
                  if !deity.blank?
                    allowed_from_deity = Array(Global.read_config('pf2e_deities', deity, 'allowed_sanctifications'))
                    if !current_sanctification.blank? && allowed_from_deity.any? { |s| s.casecmp?(current_sanctification) }
                      to_assign['archetype_sanctification'] = current_sanctification
                      advancement['archetype_sanctification'] = current_sanctification
                      client.emit_ooc t('pf2e.adv_archetype_sanctification_auto', :sanctification => current_sanctification, :archetype => archetype)
                    else
                      to_assign['archetype_sanctification'] = 'open'
                      client.emit_ooc t('pf2e.adv_archetype_sanctification_select', :archetype => archetype, :options => allowed_from_deity.join(", "))
                    end
                  else
                    to_assign['archetype_sanctification'] = 'open'
                    client.emit_ooc t('pf2e.adv_archetype_sanctification_needs_select', :archetype => archetype)
                  end
                end
              end
            end
          end
        end

        # Check the new feat for any grants.
        has_grants = fdetails['grants']

        if has_grants
          grants = to_assign['grants']  || {}
          adv_grants = advancement['grants'] || {}

          assess = Pf2e.assess_feat_grants(has_grants)
          feat_adv_grants = assess['advance'] unless assess['advance'].empty?
          feat_grants = assess['assign'] unless assess['assign'].empty?

          if feat_adv_grants && feat_adv_grants['skill']
            skill_grants = feat_adv_grants['skill']
            result = Pf2e.add_training_skills(enactor, skill_grants, to_assign, advancement)
            if result[:open_count].to_i > 0 || result[:open_lore_count].to_i > 0
              client.emit_ooc t('pf2e.adv_duplicate_skill_open', :item => "#{fname} feat")
            end

            feat_adv_grants = feat_adv_grants.dup
            feat_adv_grants.delete('skill')
            feat_adv_grants = nil if feat_adv_grants.empty?
          end

          if feat_grants || feat_adv_grants
            client.emit_ooc t('pf2e.advancement_feat_grants_addl', :element => 'item')
          end

          if has_grants['cantrip_expansion']
            base_class = enactor.pf2_base_info['charclass']
            caster_type = Pf2emagic.get_caster_type(base_class)
            if caster_type == 'spontaneous'
              to_assign['repertoire'] ||= {}
              rep_container = to_assign['repertoire']
              if rep_container.is_a?(Hash) && rep_container.keys.any? { |k| !Pf2e.level_key?(k) }
                rep_container[base_class] ||= {}
                rep_target = rep_container[base_class]
              else
                rep_target = rep_container
              end

              cantrip_key = rep_target.keys.find { |k| k.to_s.downcase == 'cantrip' } || 'cantrip'
              rep_target[cantrip_key] = Array(rep_target[cantrip_key]) + ['open', 'open']
              if rep_target != rep_container
                rep_container[base_class] = rep_target
                to_assign['repertoire'] = rep_container
              else
                to_assign['repertoire'] = rep_target
              end
            end
          end

          grants[fname] = feat_grants if feat_grants
          adv_grants[fname] = feat_adv_grants if feat_adv_grants

          to_assign['grants'] = grants unless grants.empty?
          advancement['grants'] = adv_grants unless adv_grants.empty?
        end

        # Feats that grant magic keep it in their own magic_stats block, outside 'grants'.
        if fdetails['magic_stats']
          magic_options = Pf2e.stage_feat_magic_stats(enactor, fname, fdetails, to_assign, advancement)

          if magic_options.empty?
            client.emit_ooc t('pf2e.feat_grants_magic')
          else
            Pf2e.magic_option_messages(magic_options).each { |msg| client.emit_ooc msg }
          end
        end

        # Level clauses the character already qualifies for, including one keyed to the level being advanced into.
        Pf2e.feat_at_level_catch_up(fdetails, enactor.pf2_level + 1).each do |lvl, payload|
          adv_grants = advancement['grants'] || {}
          adv_grants["#{fname} (level #{lvl})"] = payload
          advancement['grants'] = adv_grants

          client.emit_ooc t('pf2e.feat_level_clause_applied', :feat => fname, :level => lvl)
        end

        # A feat carrying its own choice opens it for the player to resolve with advance/option.
        choice_block = Pf2e.feat_choice_def(fdetails)
        instance = Pf2e.feat_taken_count(enactor, fname) + 1

        choice_block = nil unless Pf2e.feat_choice_opens_at?(choice_block, instance)

        # An auto-resolved choice is decided by current state, so work the label out now, against the staged advancement as well as the sheet.
        auto_choice = choice_block && Pf2e.auto_choice?(choice_block)
        auto_label = auto_choice ? Pf2e.auto_choice_label(enactor, choice_block, advancement) : nil

        # Nothing to open when the auto resolver has nothing left to give.
        Pf2e.open_feat_choice(to_assign, fname) if choice_block && (!auto_choice || auto_label)

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save

        client.emit_success t('pf2e.adv_feat_selected', :feat => fname, :type => key.gsub("charclass", "class"))

        if auto_choice
          # stage_feat_choice re-reads and saves the character, so it runs after the save above.
          if auto_label
            Pf2e.stage_feat_choice(enactor, fname, choice_block, auto_label, client).each { |msg| client.emit_ooc msg }

            client.emit_ooc t('pf2e.choice_auto_resolved', :choice => fname, :value => auto_label)
          else
            client.emit_ooc t('pf2e.choice_auto_none', :choice => fname)
          end
        elsif choice_block
          client.emit_ooc t('pf2e.choice_opened',
            :choice => fname,
            :summary => Pf2e.choice_summary(choice_block),
            :cmd => Pf2e.choice_info_cmd(enactor))
        end

        # Display notification about archetype if the user selects a Dedication feat.
        if fdetails['feat_type']&.include?('Dedication')
          assoc_archetypes = fdetails['assoc_archetype']
          if assoc_archetypes && !assoc_archetypes.empty?
            client.emit_ooc t('pf2e.adv_archetype_assigned', :archetype => assoc_archetypes.first)
          end
        end
      end

    end
  end
end
