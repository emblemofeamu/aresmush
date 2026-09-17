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

      key_str == 'cantrip' || key_str == Pf2emagic::ANY_RANK || key_str.match?(/\A-?\d+\z/)
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

    def self.stage_feat_magic_stats(char, feat_name, feat_details, to_assign, advancement)
      return [] if !feat_details.is_a?(Hash)

      magic_stats = feat_details['magic_stats']

      return [] if !magic_stats.is_a?(Hash) || magic_stats.empty?
      return [] if !AresMUSH.const_defined?("Pf2emagic")

      magic_stats = resolve_caster_type_stats(char, magic_stats)

      return [] if magic_stats.empty?

      base_class_key = char.pf2_base_info['charclass']
      assessed = PF2Magic.assess_magic_stats(char, magic_stats)

      advancement['magic_stats'] ||= {}
      wrap_adv_magic_stats(advancement, base_class_key)

      stats = assessed['magic_stats'] || {}
      feat_stats, class_stats = split_feat_magic(stats, FEAT_KEYED_MAGIC_STATS)

      advancement['magic_stats'][feat_name] = feat_stats unless feat_stats.empty?

      unless class_stats.empty?
        advancement['magic_stats'][base_class_key] =
          merge_magic_stats(advancement['magic_stats'][base_class_key], class_stats)
      end

      magic_options = assessed['magic_options'] || {}

      magic_options.each_pair do |option, slots|
        wrap_magic_assign(to_assign, option, base_class_key)
        to_assign[option] ||= {}

        if FEAT_KEYED_MAGIC_OPTIONS.include?(option.to_s)
          to_assign[option][feat_name] = slots
        else
          to_assign[option][base_class_key] =
            merge_spell_slots(to_assign[option][base_class_key], slots)
        end
      end

      magic_options.keys.sort
    end

    FEAT_KEYED_MAGIC_STATS = %w(innate_spell)
    FEAT_KEYED_MAGIC_OPTIONS = %w(innate)

    def self.split_feat_magic(stats, feat_keys)
      feat_stats = stats.select { |key, _value| feat_keys.include?(key.to_s) }
      class_stats = stats.reject { |key, _value| feat_keys.include?(key.to_s) }

      [ feat_stats, class_stats ]
    end

    def self.merge_magic_stats(existing, added)
      return added unless existing.is_a?(Hash)
      return existing unless added.is_a?(Hash)

      added.each_with_object(existing.dup) do |(key, value), merged|
        current = merged[key]

        merged[key] = if current.is_a?(Hash) && value.is_a?(Hash)
          current.merge(value)
        elsif current.is_a?(Array) && value.is_a?(Array)
          current + value
        else
          value
        end
      end
    end

    def self.merge_spell_slots(existing, added)
      return added if existing.nil?
      return existing if added.nil?

      if existing.is_a?(Hash) && added.is_a?(Hash)
        added.each_with_object(existing.dup) do |(level, slots), merged|
          merged[level] = Array(merged[level]) + Array(slots)
        end
      elsif existing.is_a?(Array) && added.is_a?(Array)
        existing + added
      else
        added
      end
    end

    def self.magic_option_messages(options)
      innate, rest = Array(options).map(&:to_s).uniq.partition { |option| option.casecmp?('innate') }

      msg = []
      msg << t('pf2e.adv_item_magic', :options => rest.sort.join(" and ")) unless rest.empty?
      msg << t('pf2e.adv_item_innate_spells') unless innate.empty?

      msg
    end

    def self.archetype_key?(key)
      archetypes = Global.read_config('pf2e_archetype')&.keys || []
      archetypes.any? { |arch| arch.to_s.casecmp?(key.to_s) }
    end


    def self.open_skill_token?(value)
      token = value.to_s.strip.downcase
      token == 'open' || token == 'open lore' || token == 'open untrained' || token == 'open lore untrained'
    end

    def self.untrained_only_token?(value)
      token = value.to_s.strip.downcase
      token == 'open untrained' || token == 'open lore untrained'
    end

    def self.pending_skill_names(to_assign, advancement)
      entries = []
      entries += Array(to_assign['raise skill'])
      entries += Array(advancement['raise skill'])

      entries = entries.compact.map { |entry| entry.to_s.strip }.reject(&:empty?)
      entries.reject! { |entry| open_skill_token?(entry) }
      entries.map(&:downcase)
    end

    def self.merge_raise_skill_entries(existing, additions)
      list = if existing.is_a?(Array)
        existing.dup
      elsif existing.nil?
        []
      else
        [existing]
      end

      list += Array(additions)
      list = list.compact.map { |entry| entry.to_s.strip }.reject(&:empty?)

      seen = {}
      result = []
      list.each do |entry|
        if open_skill_token?(entry)
          result << entry
          next
        end

        key = entry.to_s.downcase
        next if seen[key]

        seen[key] = true
        result << entry
      end

      result
    end

    # Which of the four skill markers a restriction asks for. A slot can be limited to a Lore,
    # to something the character is untrained in, or both - and Advancement::Raises reads the
    # same vocabulary to decide what may spend it.
    SKILL_SLOT_TOKENS = {
      [ false, false ] => 'open',
      [ false, true ] => 'open untrained',
      [ true, false ] => 'open lore',
      [ true, true ] => 'open lore untrained'
    }.freeze

    def self.add_open_skill_slot(to_assign, advancement, lore=false, untrained_only=false)
      token = SKILL_SLOT_TOKENS[[ !!lore, !!untrained_only ]]
      delta = [ Slots.open('raise skill', :token => token) ]

      # A scalar left over from an older shape is folded into the list by Slots.open.
      to_assign.replace(Slots.apply(to_assign, delta))
      advancement.replace(Slots.apply(advancement, delta))
    end

    def self.add_training_skills(char, skills, to_assign, advancement)
      cleaned = Array(skills).map { |s| s.to_s.strip }.reject(&:empty?)
      return { assigned: [], open_count: 0, open_lore_count: 0 } if cleaned.empty?

      pending = pending_skill_names(to_assign, advancement)
      assigned = []
      open_count = 0
      open_lore_count = 0

      cleaned.each do |skill|
        normalized = skill.to_s.downcase
        already_trained = Pf2eSkills.get_skill_prof(char, skill).to_s.downcase != 'untrained'
        already_pending = pending.include?(normalized)

        if already_trained || already_pending
          if lore_skill?(skill)
            open_lore_count += 1
          else
            open_count += 1
          end
          next
        end

        assigned << skill
        pending << normalized
      end

      if assigned.any?
        to_assign['raise skill'] = merge_raise_skill_entries(to_assign['raise skill'], assigned)
        advancement['raise skill'] = merge_raise_skill_entries(advancement['raise skill'], assigned)
      end

      open_count.times { add_open_skill_slot(to_assign, advancement, false, true) }
      open_lore_count.times { add_open_skill_slot(to_assign, advancement, true, true) }

      { assigned: assigned, open_count: open_count, open_lore_count: open_lore_count }
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
        when "feat_choice", "grant_choice"
          # Handled once after this loop, since granted_choice_names reads both keys off the
          # whole entry and a level carrying both would otherwise open every slot twice.
        when "magic_stats"
          assess_magic = PF2Magic.assess_magic_stats(char, value)

          advancement[key] = assess_magic['magic_stats']
          magic_options = assess_magic['magic_options']

          if magic_options
            # Merge is acting funky, so we brute force.
            magic_options.each_pair do |k,v|
              to_assign[k] = v
            end
            return_msg.concat(magic_option_messages(magic_options.keys))
          end
        when "raise"
          # Value is an array of all the things you can choose to raise.
          # In this case, we put into to_assign what is to be raised as a key with an empty value.

          value.each do |item|
            to_assign["raise #{item}"] = item == "ability" ? Array.new(4, "open") : [ "open" ]
            return_msg << t('pf2e.adv_item_raise', :item => item)
          end
        when "choose", "charclass_choice"
          name = value['choice_name']
          options = value['options']
          to_choose = to_assign['class option'] || {}
          to_choose[name] = options.is_a?(Hash) ? options : Array(options)

          display_options = options.is_a?(Hash) ? options.keys : Array(options)
          return_msg << t('pf2e.adv_item_choose', :name => name, :options => display_options.sort.join(", "))

          to_assign['class option'] = to_choose
        when "charclass_feature"
          advancement[key] = value
        else
          advancement[key] = value
        end
      end

      # Feat choices this level opens.
      granted_choice_names(info).each do |name|
        open_feat_choice(to_assign, name)

        block = find_choice_block(char, name)
        summary = block ? choice_summary(block) : 'eligible option'

        return_msg << t('pf2e.adv_item_feat_choice', :choice => name, :summary => with_article(summary))
      end

      # Fold in anything an earlier feat choice deferred to this level, such as Canny Acumen.
      new_level = char.pf2_level + 1

      deferred_choice_grants(char, new_level).each do |choice_name, label, grants|
        next unless grants.is_a?(Hash)

        advancement['grants'] ||= {}
        advancement['grants']["#{choice_name} (#{label})"] = grants

        return_msg << t('pf2e.adv_deferred_choice', :choice => "#{choice_name} (#{label})", :level => new_level)
      end

      # Level clauses on feats they already hold, such as Weapon Proficiency going to expert at 11.
      deferred_feat_grants(char, new_level).each do |feat, lvl, grants|
        next unless grants.is_a?(Hash)

        advancement['grants'] ||= {}
        advancement['grants']["#{feat} (level #{lvl})"] = grants

        return_msg << t('pf2e.adv_deferred_feat', :feat => feat, :level => lvl)
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
          # Every stat key update_magic understands has to be listed: an unlisted one makes the
          # whole block look class-keyed, and each stat then gets dispatched as if it were a class.
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
            restricted_slots
            restricted_spellbook
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
          # The score moves so the draft sheet shows it, and the count is recorded so
          # `commit_level_up!` can diff it into `boost_ability` grants - which is what lets a
          # rollback take the boost back.
          boosts = char.pf2_boosts

          value.each do |ability|
            Pf2eAbilities.update_base_score(char, ability)
            boosts[ability] = boosts[ability].to_i + 1
          end

          char.pf2_boosts = boosts
        when "languages"
          char_languages = Array(char.pf2_lang)
          char_languages.concat(Array(value))
          char.pf2_lang = char_languages.uniq
        when "raise skill"
          Array(value).each do |skill_name|
            next if skill_name.to_s.strip.empty?
            next if open_skill_token?(skill_name)

            skill = Pf2eSkills.find_skill(skill_name, char)
            return nil if !skill

            new_prof = Pf2eSkills.get_next_prof(char, skill_name)
            skill.update(prof_level: new_prof)
          end
        when "raise skill choice"
          Array(value).each do |skill_name|
            next if skill_name.to_s.strip.empty?
            next if open_skill_token?(skill_name)

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
          # Draft only. The ledger is written once, at the end of do_advancement, against the
          # level actually being gained - syncing here would attribute it to the level the
          # character is still on.
          char.pf2_feats = char_feats
        when "charclass_feature option"
          value.each_pair do |feature, option|
            features = char.pf2_features
            features['charclass_features'] ||= []
            feature_label = "#{feature} (#{option})"
            features['charclass_features'] << feature_label unless features['charclass_features'].include?(feature_label)
            char.pf2_features = features

            case feature
            when "Path to Perfection", "Second Path to Perfection", "Third Path to Perfection"
              combat = char.combat
              saves = combat.saves
              path = saves['Path to Perfection'] || []

              already_chosen = path.any? { |s| s.to_s.casecmp?(option.to_s) }

              # Second must be a different save; Third must be one of the earlier two.
              if feature == "Third Path to Perfection" && !already_chosen
                client.emit_failure t('pf2e.path_perfection_needs_earlier', :option => option)
                next
              elsif feature != "Third Path to Perfection" && already_chosen
                client.emit_failure t('pf2e.path_perfection_needs_new', :option => option)
                next
              end

              rank = (feature == "Third Path to Perfection") ? 'legendary' : 'master'

              path << option unless already_chosen

              saves[option] = rank
              saves['Path to Perfection'] = path

              combat.update(saves: saves)
            when "Fighter Weapon Mastery"
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
            when "Divine Ally"
              # Divine Ally is recorded in charclass features; no extra automation yet.
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
        when "archetype_sanctification"
          faith_info = char.pf2_faith
          faith_info['sanctification'] = value
          char.pf2_faith = faith_info

          traits = char.pf2_traits.dup
          traits.reject! { |tr| tr.casecmp?('holy') || tr.casecmp?('unholy') }
          unless value.blank? || value.casecmp?('Unsanctified')
            traits << value.downcase
            traits = traits.uniq.sort
          end
          char.pf2_traits = traits
        when "grants"
          value.each_pair do |feat, info|
            do_feat_grants(char, info, charclass, client)
          end
        when "innate"
          # Innate spells are granted by the magic_stats entry that opened the slot, which records the
          # chosen spell as its name. Older advancements that stashed the filled slots here too need
          # no second pass.
        when "repertoire_swap"
          # Already applied during advance/spellswap; no additional work needed here.
        else
          client.emit_ooc "Unknown key #{key} in do_advancement. Please put in a request to code staff."
        end
      end

      # The level this advancement completes.
      new_level = char.pf2_level + 1

      # Record what was chosen against the level it was chosen at.
      to_assign = char.pf2_to_assign

      entry = { 'advancement' => to_process }
      entry['archetype'] = to_assign['archetype'] if to_assign['archetype']
      entry['archetype_specialty'] = to_assign['archetype_specialty'] if to_assign['archetype_specialty']
      entry['archetype_specialty_choice'] = to_assign['archetype specialty choice'] if to_assign['archetype specialty choice']

      if to_assign['feat_choices'].is_a?(Hash) && !to_assign['feat_choices'].empty?
        entry['feat_choices'] = to_assign['feat_choices']
      end

      tracker = char.pf2_level_tracker || {}
      tracker[new_level.to_s] = (tracker[new_level.to_s] || {}).merge(entry)
      char.pf2_level_tracker = tracker

      # Update level.
      char.pf2_level = new_level

      # Record everything and kick out of advancement mode.
      char.pf2_to_assign = {}
      char.pf2_advancement = {}
      char.advancing = false

      char.save

      # The single commit point for a level-up: everything this advancement produced becomes
      # one level_up transaction attributed to the level just gained, XP spend included.
      Pf2e::Ledger.commit_level_up!(char, new_level)

      return nil
    end

    # What the review screen says is still outstanding, and the gate advance/done checks.
    #
    # Which picks are open is Advancement::Outstanding's table; this renders what it returns. One
    # message needs the character to describe itself - the summary of what a feat's choice may be
    # drawn from - so that lookup happens here rather than in the pure table.
    def self.advancement_messages(char)
      # Only the draft and the config, not a folded sheet: this runs on every review screen and at
      # every advance/done, and Outstanding reads nothing else.
      state = CharState.build({ 'to_assign' => char.pf2_to_assign, 'advancement' => char.pf2_advancement })

      msg = Advancement::Outstanding.messages(state).map do |(key, args)|
        args = args.merge('summary' => choice_pending_summary(char, args['choice'])) if args.key?('choice')

        t(key, **args.reject { |k, _v| k == 'choice' }.transform_keys(&:to_sym))
      end

      return nil if msg.empty?

      msg
    end

    # What a feat's open choice is drawn from, in words: "a skill", "a lore". Falls back to a
    # neutral phrase for a choice whose block cannot be found, so the player is still told they
    # owe a pick.
    def self.choice_pending_summary(char, name)
      block = find_choice_block(char, name)

      with_article(block ? choice_summary(block) : 'eligible option')
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

    # Kept for callers outside the advance/option path. The rule itself lives in
    # Advancement::Options, so the gate and the apply side cannot drift apart again.
    def self.valid_class_option?(char, feature, option)
      saves = (char.combat && char.combat.saves) || {}

      Advancement::Options.allowed?({ 'saves' => saves }, feature, option)
    end

  end
end
