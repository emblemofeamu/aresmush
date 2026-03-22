module AresMUSH
  module Pf2e

    def self.can_advance(char)
      # Are they already advancing?
      return t('pf2e.already_advancing') if char.advancing

      # Do they have enough XP?
      xp = char.pf2_xp
      return t('pf2e.not_enough_xp') unless (xp >= 1000)

      # Are they in an active encounter?
      active_encounter = PF2Encounter.in_active_encounter? char
      return t('pf2e.already_in_encounter') if active_encounter

      # Can they level?
      level = char.pf2_level
      return t('pf2e.already_max_level') if (level == Global.read_config('pf2e', 'max_level'))

      return nil
    end

    def self.level_key?(key)
      key_str = key.to_s.downcase
      key_str == 'cantrip' || key_str.match?(/\A-?\d+\z/)
    end

    def self.wrap_magic_assign(to_assign, key, base_class_key)
      existing = to_assign[key]
      return if existing.nil?
      return if existing.is_a?(Hash) && existing.keys.any? { |k| k.to_s.casecmp?(base_class_key) }

      if existing.is_a?(Hash)
        if existing.keys.all? { |k| level_key?(k) }
          to_assign[key] = { base_class_key => existing }
        end
      else
        to_assign[key] = { base_class_key => existing }
      end
    end

    def self.wrap_adv_magic_stats(advancement, base_class_key)
      existing = advancement['magic_stats']
      return if existing.nil?
      return if existing.is_a?(Hash) && existing.keys.any? { |k| k.to_s.casecmp?(base_class_key) }

      if existing.is_a?(Hash)
        stat_keys = %w(
          spell_abil
          tradition
          spells_per_day
          repertoire
          spellbook
          signature
          signature_spells
          signature_spell
          focus_pool
          focus_spell
          focus_cantrip
          innate_spell
          addrepertoire
          addspellbook
          divine_font
        )

        if existing.keys.any? { |k| stat_keys.include?(k.to_s) }
          advancement['magic_stats'] = { base_class_key => existing }
        end
      end
    end

    def self.archetype_key?(key)
      archetypes = Global.read_config('pf2e_archetype')&.keys || []
      archetypes.any? { |arch| arch.to_s.casecmp?(key.to_s) }
    end

    def self.assess_advancement(char,info)
      # Can the character advance?
      advfail = Pf2e.can_advance(char)
      return advfail if advfail

      # Return_msg returns a list of what they need to choose as an array.
      return_msg = []

      advancement = {}
      to_assign = {}

      info.each_pair do |key, value|
        case key
        when "choose_feat"
          # Value is an array of types to choose.
          hash = to_assign['feats'] || {}
          value.each do |feat|
            hash[feat] = [ "open" ]

            return_msg << t('pf2e.adv_item_feat', :value => feat)
          end
          to_assign['feats'] = hash
        when "gated_feat"
          # Value in this case is the name of the gate.
          # Stash into to_assign as is.

          to_assign[value] = 'open'
        when "magic_stats"
          assess_magic = PF2Magic.assess_magic_stats(char, value)

          advancement[key] = assess_magic['magic_stats']
          magic_options = assess_magic['magic_options']

          if magic_options
            # Merge is acting funky, so we brute force.
            magic_options.each_pair do |k,v|
              to_assign[k] = v
            end
            return_msg << t('pf2e.adv_item_magic', :options => magic_options.keys.sort.join(" and "))
          end
        when "raise"
          # Value is an array of all the things you can choose to raise.
          # In this case, we put into to_assign what is to be raised as a key with an empty value.

          value.each do |item|
            to_assign["raise #{item}"] = item == "ability" ? Array.new(4, "open") : "open"
            return_msg << t('pf2e.adv_item_raise', :item => item)
          end
        when "choose"
          name = value['choice_name']
          options = Array(value['options'])
          to_choose = to_assign['class option'] || {}
          to_choose[name] = options

          return_msg << t('pf2e.adv_item_choose', :name => name, :options => options.sort.join(", "))

          to_assign['class option'] = to_choose
        when "charclass_feature"
          if value.is_a?(Hash) && value['choose']
            choose_info = value['choose']
            name = choose_info['choice_name']
            options = Array(choose_info['options'])

            to_choose = to_assign['class option'] || {}
            to_choose[name] = options
            to_assign['class option'] = to_choose

            return_msg << t('pf2e.adv_item_choose', :name => name, :options => options.sort.join(", "))

            remaining = value.dup
            remaining.delete('choose')
            advancement[key] = remaining unless remaining.empty?
          else
            advancement[key] = value
          end
        else
          advancement[key] = value
        end
      end

      char.update(pf2_to_assign: to_assign)
      char.update(pf2_advancement: advancement)
      char.update(advancing: true)

      return_msg
    end

    def self.do_advancement(char, client)
      # Make sure they don't have anything left to choose.
      messages = advancement_messages(char)
      return messages.join("%r") if messages

      # In advancement, to_process holds everything to be added to the sheet.
      # As with commit info, char.update is not used here generally because it would mean many separate writes, quickly.
      # Kinder to the database to make a whole bunch of changes and write the lot in one go at the end.
      charclass = char.pf2_base_info['charclass']
      archetype1 = char.pf2_archetypeinfo['archetype1'] && char.pf2_archetypeinfo['archetype_specialty1'] || []
      archetype2 = char.pf2_archetypeinfo['archetype2'] && char.pf2_archetypeinfo['archetype_specialty2'] || []
      archetype3 = char.pf2_archetypeinfo['archetype3'] && char.pf2_archetypeinfo['archetype_specialty3'] || []
      archetype4 = char.pf2_archetypeinfo['archetype4'] && char.pf2_archetypeinfo['archetype_specialty4'] || []

      to_process = char.pf2_advancement
      to_process.each_pair do |key, value|
        case key
        when "charclass_feature"
          features = char.pf2_features
          features['charclass_features'] ||= []
          features['charclass_features'].concat(Array(value)).uniq!
          char.pf2_features = features
        when "archetype_feature"
          features = char.pf2_features
          features['archetype_features'] ||= []
          features['archetype_features'].concat(Array(value)).uniq!
          char.pf2_features = features
        when "combat_stats"
          Pf2eCombat.update_combat_stats(char, value)
        when "magic_stats"
          # Ignore any return, this key only includes items that do not populate to_assign.
          stat_keys = %w(
            spell_abil
            tradition
            spells_per_day
            repertoire
            spellbook
            signature
            signature_spells
            signature_spell
            focus_pool
            focus_spell
            focus_cantrip
            innate_spell
            addrepertoire
            addspellbook
            divine_font
          )

          if value.is_a?(Hash) && value.keys.any? { |k| !stat_keys.include?(k.to_s) }
            value.each_pair do |class_key, stats|
              PF2Magic.update_magic(char, class_key, stats, client)
            end
          else
            PF2Magic.update_magic(char, charclass, value, client)
          end
        when "action"
          all_actions = char.pf2_actions
          actions = all_actions['actions']

          value.each do |item|
            actions << item
          end

          all_actions['actions'] = actions.uniq.sort
          char.pf2_actions = all_actions
        when "reaction"
          all_actions = char.pf2_actions
          reactions = all_actions['reactions']

          value.each do |item|
            reactions << item
          end

          all_actions['reactions'] = reactions.uniq.sort
          char.pf2_actions = all_actions
        when "raise ability"
          value.each do |ability|
            Pf2eAbilities.update_base_score(char, ability)
          end
        when "raise skill"
          Array(value).each do |skill_name|
            next if skill_name.to_s.strip.empty?
            next if skill_name.to_s.downcase == 'open'

            skill = Pf2eSkills.find_skill(skill_name, char)
            return nil if !skill

            new_prof = Pf2eSkills.get_next_prof(char, skill_name)
            skill.update(prof_level: new_prof)
          end
        when "raise skill choice"
          Array(value).each do |skill_name|
            next if skill_name.to_s.strip.empty?
            next if skill_name.to_s.downcase == 'open'

            skill = Pf2eSkills.find_skill(skill_name, char)
            return nil if !skill

            new_prof = Pf2eSkills.get_next_prof(char, skill_name)
            skill.update(prof_level: new_prof)
          end
        when "feats"
          char_feats = char.pf2_feats
          value.each_pair do |type, feat_list|
            char_feats[type] ||= []
            char_feats[type].concat(feat_list)

            feat_list.each do |feat_name|
              feat_info = Pf2e.get_feat_details(feat_name)
              next if feat_info.is_a?(String)

              Pf2e.apply_init_magic_feat(char, feat_info[0], feat_info[1], client)
            end
          end
          char.pf2_feats = char_feats
        when "charclass_feature option"
          value.each_pair do |feature, option|
            features = char.pf2_features
            features['charclass_features'] ||= []
            feature_label = "#{feature} (#{option})"
            features['charclass_features'] << feature_label unless features['charclass_features'].include?(feature_label)
            char.pf2_features = features

            case feature
            when "Path to Perfection"
              combat = char.combat
              saves = combat.saves
              path = saves['Path to Perfection'] || []
              value = (path.size == 2) ? 'master' : 'legendary'

              path << option

              saves[option] = value
              saves['Path to Perfection'] = path

              combat.update(saves: saves)
            when "Weapon Mastery"
              combat = Pf2eCombat.get_create_combat_obj(char)
              group_profs = combat.weapon_group_prof || {}
              group_profs[option] = {
                'simple' => 'master',
                'martial' => 'master',
                'unarmed' => 'master',
                'advanced' => 'expert'
              }
              combat.update(weapon_group_prof: group_profs)
            when "Weapon Legend"
              combat = Pf2eCombat.get_create_combat_obj(char)
              profs = combat.weapon_prof || {}
              profs['simple'] = Pf2e.higher_prof(profs['simple'], 'master')
              profs['martial'] = Pf2e.higher_prof(profs['martial'], 'master')
              profs['unarmed'] = Pf2e.higher_prof(profs['unarmed'], 'master')
              profs['advanced'] = Pf2e.higher_prof(profs['advanced'], 'expert')
              combat.update(weapon_prof: profs)

              group_profs = combat.weapon_group_prof || {}
              group_profs[option] = {
                'simple' => 'legendary',
                'martial' => 'legendary',
                'unarmed' => 'legendary',
                'advanced' => 'master'
              }
              combat.update(weapon_group_prof: group_profs)
            else
              client.emit_ooc t('pf2e.missing_charclass_option_code', :feature => feature)
              next
            end
          end
        when "spellbook"
          magic = char.magic

          csb = magic.spellbook
          class_map = if value.is_a?(Hash) && value.keys.any? { |k| !Pf2e.level_key?(k) }
            value
          else
            { charclass => value }
          end

          class_map.each_pair do |class_key, class_value|
            class_csb = csb[class_key] || {}

            if class_value.is_a?(Hash)
              class_value.each_pair do |level, spells|
                Array(spells).each do |spell|
                  splist = class_csb[level.to_s] || []
                  splist << spell
                  class_csb[level.to_s] = splist
                end
              end
            else
              Array(class_value).each do |spell|
                sp = Pf2emagic.get_spell_details(spell)
                spdeets = sp[1]

                level = spdeets['base_level'].to_s

                splist = class_csb[level] || []
                splist << spell
                class_csb[level] = splist
              end
            end

            csb[class_key] = class_csb
          end

          magic.update(spellbook: csb)
        when "repertoire"
          magic = char.magic
          repertoire = magic.repertoire
          class_map = if value.is_a?(Hash) && value.keys.any? { |k| !Pf2e.level_key?(k) }
            value
          else
            { charclass => value }
          end

          class_map.each_pair do |class_key, class_value|
            class_rep = repertoire[class_key] || {}

            if class_value.is_a?(Hash)
              class_value.each_pair do |level, spells|
                splist = (Array(class_rep[level]) + Array(spells)).sort
                class_rep[level] = splist
              end
            end

            repertoire[class_key] = class_rep
          end

          magic.update(repertoire: repertoire)
        when "signature"
          magic = char.magic
          signatures = magic.signature_spells || {}
          class_map = if value.is_a?(Hash) && value.keys.any? { |k| !Pf2e.level_key?(k) }
            value
          else
            { charclass => value }
          end

          class_map.each_pair do |class_key, class_value|
            class_sigs = signatures[class_key] || {}

            if class_value.is_a?(Hash)
              class_value.each_pair do |level, spells|
                chosen = Array(spells).reject { |s| s.to_s.strip.empty? || s.to_s.downcase == 'open' }
                next if chosen.empty?

                class_sigs[level] = chosen
              end
            end

            signatures[class_key] = class_sigs
          end

          magic.update(signature_spells: signatures)
        when "archetype_deity"
          faith_info = char.pf2_faith
          faith_info['deity'] = value
          char.pf2_faith = faith_info
        when "grants"
          value.each_pair do |feat, info|
            do_feat_grants(char, info, charclass, client)
          end
        when "repertoire_swap"
          # Already applied during advance/spellswap; no additional work needed here.
        else
          client.emit_ooc "Unknown key #{key} in do_advancement. Please put in a request to code staff."
        end
      end

      advancement = char.pf2_adv_assigned || {}
      advancement["level"] = to_process

      # Record archetype and specialty if they were selected
      to_assign = char.pf2_to_assign
      if to_assign['archetype']
        advancement['archetype'] = to_assign['archetype']
      end
      if to_assign['archetype_specialty']
        advancement['archetype_specialty'] = to_assign['archetype_specialty']
      end

      # Deduct the XP.
      xp = char.pf2_xp
      xp = xp - 1000
      char.pf2_xp = xp

      # Update level.
      level = char.pf2_level
      level = level + 1
      char.pf2_level = level

      # Record everything and kick out of advancement mode.
      char.pf2_adv_assigned = advancement
      char.pf2_to_assign = {}
      char.pf2_advancement = {}
      char.advancing = false

      char.save
      return nil
    end

    def self.advancement_messages(char)
      # Handles messages related to advancement choices in the Messages section of the advance/review screen.
      msg = []

      to_assign = char.pf2_to_assign

      to_assign.each_pair do |item, info|
        case item
        when "feats"
          info.each_pair do |k,v|
            msg << t('pf2e.adv_item_feat', :value => k.gsub("charclass", "class")) if v.include? "open"
          end
        when "class option", "charclass option"
          if info.is_a?(Hash)
            info.each_pair do |feature, options|
              next unless options.is_a?(Array) || options.is_a?(Hash)

              msg << t('pf2e.adv_item_class_option_select', :name => feature, :name_downcase => feature.to_s.downcase)
            end
          end
        when "raise skill", "raise ability"
          type = item.delete_prefix "raise "

          # Info is blank if the item has not yet been selected.
          has_open = if info.is_a?(Array)
            info.include?("open")
          else
            info == "open"
          end

          if has_open
            if type == "ability"
              msg << t('pf2e.adv_item_raise_ability')
            else
              msg << t('pf2e.adv_item_raise', :item => type)
            end
          end
        when "raise skill choice"
          needs_choice = if info.is_a?(Array)
            !info.empty?
          else
            info.to_s.downcase == 'open'
          end

          msg << t('pf2e.adv_item_skill_choice') if needs_choice
        when "spellbook", "repertoire", "innate"
          needs_open = lambda do |value|
            if value.is_a?(Hash)
              value.values.any? { |sub| needs_open.call(sub) }
            elsif value.is_a?(Array)
              value.include?("open")
            else
              value.to_s.downcase == 'open'
            end
          end

          if info.is_a?(Hash) && info.keys.any? { |k| !Pf2e.level_key?(k) }
            info.each_pair do |class_key, value|
              next unless needs_open.call(value)

              if Pf2e.archetype_key?(class_key) && (item == "spellbook" || item == "repertoire")
                locale_key = item == "spellbook" ? 'pf2e.adv_item_archetype_spellbook' : 'pf2e.adv_item_archetype_repertoire'
                msg << t(locale_key, :archetype => class_key)
              else
                msg << t('pf2e.adv_item_spells', :options => item)
              end
            end
          else
            needs_spell_choice = needs_open.call(info)
            msg << t('pf2e.adv_item_spells', :options => item) if needs_spell_choice
          end
        when "signature"
          needs_signature = false
          if info.is_a?(Hash)
            if info.keys.any? { |k| !Pf2e.level_key?(k) }
              needs_signature = info.values.any? do |v|
                if v.is_a?(Hash)
                  v.values.any? { |sub| sub.is_a?(Array) ? sub.include?("open") : sub.to_i > 0 }
                else
                  v.is_a?(Array) ? v.include?("open") : v.to_i > 0
                end
              end
            else
              needs_signature = info.values.any? do |v|
                v.is_a?(Array) ? v.include?("open") : v.to_i > 0
              end
            end
          end
          msg << t('pf2e.adv_item_signaturespells') if needs_signature
        when "archetype_specialty"
          msg << t('pf2e.adv_item_archetype_specialty') if info == "open"
        when "archetype key ability"
          needs_choice = if info.is_a?(Array)
            !info.empty?
          else
            info.to_s.downcase == 'open'
          end

          msg << t('pf2e.adv_item_archetype_key_ability') if needs_choice
        when "archetype deity"
          msg << t('pf2e.adv_item_archetype_deity') if info.to_s.downcase == 'open'
        when "special feat"
          msg << t('pf2e.unassigned_gated_feat', :options => info.sort.join(", "))
        when "grants"
          info.keys.each do |feat|
            grant_info = info[feat]
            if grant_info.is_a?(Hash) && grant_info['gated_feat']
              gate = grant_info['gated_feat']
              summary = Pf2e.gated_feat_summary(gate)
              msg << t('pf2e.adv_item_gated_feat_summary', :gate => gate, :summary => summary, :gate_underscore => gate.downcase.gsub(" ", "_"))
            else
              msg << t('pf2e.adv_item_grants', :feat => feat)
            end
          end
        else
          if info.is_a?(String) && info.downcase == 'open'
            options = Pf2e.get_gated_feat_options(char, item)
            if options && !options.empty?
              msg << t('pf2e.adv_item_gated_feat', :gate => item, :options => options.sort.join(', '))
            end
          end
        end

      end

      return nil if msg.empty?
      return msg
    end

    def self.merge_combat_stats(existing_stats, added_stats)
      existing = existing_stats || {}
      added = added_stats || {}

      merged = {}

      (existing.keys | added.keys).each do |key|
        existing_value = existing[key]
        added_value = added[key]

        merged[key] =
          if existing_value.is_a?(Hash) && added_value.is_a?(Hash)
            merge_combat_stats(existing_value, added_value)
          elsif prof_rank(existing_value) || prof_rank(added_value)
            higher_prof(existing_value, added_value)
          elsif added_value.nil?
            existing_value
          else
            added_value
          end
      end

      merged
    end

    def self.prof_rank(value)
      return nil if value.nil?

      {
        'untrained' => 0,
        'trained' => 1,
        'expert' => 2,
        'master' => 3,
        'legendary' => 4
      }[value.to_s.downcase]
    end

    def self.higher_prof(left, right)
      left_rank = prof_rank(left)
      right_rank = prof_rank(right)

      return right if left_rank.nil?
      return left if right_rank.nil?

      left_rank >= right_rank ? left.to_s.downcase : right.to_s.downcase
    end

    def self.valid_class_option?(char, feature, option)
      passes_check = true

      case feature
      when "Path to Perfection"
        valid_values = %w(fortitude reflex will)

        return false unless valid_values.include? option

        saves = char.combat.saves
        path = saves['Path to Perfection'] || []

        return true if path.empty?

        if path.size == 1
          passes_check = true unless path.include? option
        else
          passes_check = true if path.include? option
        end
      end

      passes_check
    end

  end
end
