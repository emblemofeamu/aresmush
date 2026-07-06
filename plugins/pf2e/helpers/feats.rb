module AresMUSH
  module Pf2e

    include CommonTemplateFields

    def self.get_feat_details(term)
      return "no_term" unless term.is_a? String

      feats = Global.read_config('pf2e_feats')

      keys = feats.keys

      name = ""

      # Give me an array of all the feats that match the term.
      match = keys.select { |f| f.upcase.match? Regexp.escape(term.upcase) }

      return 'no_match' if match.empty?

      if match.size > 1
        # Look for an exact match, allows 'Familiar' to be taken when 'Leshy Familiar' is in the list.
        match.each do |item|
          if item.upcase == term.upcase
            name = match.find { |item| item.casecmp?(term) } || name
          end
        end

        return 'ambiguous' if name.empty?
      else
        # Pull the unique feat name out of the array so it can be used as a key to get the feat deets.
          name = match.first
      end

      # First is the name of the feat matched, the second is the details for the feat.
      return [ name, feats[name] ]
    end

    def self.get_feat_match_options(term)
      return [] unless term.is_a? String

      feats = Global.read_config('pf2e_feats')
      keys = feats.keys

      match = keys.select { |f| f.upcase.match? Regexp.escape(term.upcase) }
      return [] if match.empty?

      exact = match.find { |item| item.casecmp?(term) }
      return [] if exact

      match.sort
    end

    def self.search_feats(search_type, term, operator='=')
      feat_info = Global.read_config('pf2e_feats')

      case search_type
      when 'name'
        match = feat_info.select { |k,v| k.upcase.match? term.upcase }
      when 'traits'
        match = feat_info.select { |k,v| v['traits'].include? term.downcase }
      when 'level'
        # Invalid operator defaults to ==.
        case operator
        when '<'
          match = feat_info.select { |k,v| v['prereq']['level'] < term.to_i }
        when '>'
          match = feat_info.select { |k,v| v['prereq']['level'] > term.to_i }
        else
          match = feat_info.select { |k,v| v['prereq']['level'] == term.to_i }
        end
      when 'feat_type'
        match = feat_info.select { |k,v| v['feat_type'].include? term.capitalize }
      when 'class'
        match = feat_info.select { |k,v| v['assoc_charclass']&.include? term.capitalize }
      when 'ancestry'
        match = feat_info.select { |k,v| v['assoc_ancestry']&.include? term.capitalize }
      when 'skill'
        match = feat_info.select do |k, v|
          skills = Array(v['assoc_skill']).compact
          skills.any? { |s| s.downcase.include?(term.downcase) }
        end
      when 'description', 'desc'
        match = feat_info.select { |k,v| v['shortdesc'].upcase.match? term.upcase }
      when 'classlevel'
        feats_by_class = feat_info.select { |k,v| v['assoc_charclass']&.include? operator.capitalize }
        match = feats_by_class.select { |k,v| v['prereq']['level'] == term.to_i }
      when 'archetype'
        match = feat_info.select { |k,v| v['assoc_archetype']&.any? { |a| a.downcase.include?(term.downcase) } }
      end

      match

    end

    def self.dedication_allowed?(char, details)
      return true unless details

      feat_type = details['feat_type']
      return true unless feat_type&.include?('Dedication')

      base_class = char.pf2_base_info['charclass']
      assoc_classes = Array(details['assoc_class']).compact
      assoc_charclasses = Array(details['assoc_charclass']).compact

      return assoc_classes.any? { |c| c.to_s.casecmp?(base_class.to_s) } unless assoc_classes.empty?

      return false if assoc_charclasses.any? { |c| c.to_s.casecmp?(base_class.to_s) }

      dedication_archetype_ready?(char)
    end

    def self.dedication_archetype_ready?(char)
      feat_info = Global.read_config('pf2e_feats') || {}
      return true if feat_info.empty?

      feat_name_map = {}
      feat_info.keys.each { |name| feat_name_map[name.to_s.upcase] = name }

      feat_names = if char.advancing
        Pf2e.preview_feat_names(char)
      else
        char.pf2_feats.values.flatten.map { |f| f.to_s.upcase }
      end

      dedication_archetypes = []
      archetype_feat_counts = Hash.new(0)

      feat_names.each do |feat_name|
        details_key = feat_name_map[feat_name.to_s.upcase]
        next unless details_key

        details = feat_info[details_key]
        next unless details

        assoc_archetypes = Array(details['assoc_archetype']).compact
        next if assoc_archetypes.empty?

        if details['feat_type']&.include?('Dedication')
          dedication_archetypes << assoc_archetypes
        else
          assoc_archetypes.each do |arch|
            archetype_feat_counts[arch.to_s.downcase] += 1
          end
        end
      end

      return true if dedication_archetypes.empty?

      dedication_archetypes.all? do |archetypes|
        archetypes.any? { |arch| archetype_feat_counts[arch.to_s.downcase] >= 2 }
      end
    end

    def self.can_take_feat?(char, feat)
      msg = []

      find_feat = Pf2e.get_feat_details(feat)

      # This will come back as a string if the feat name is bad or not unique.
      return false if find_feat.is_a? String
      
      details = find_feat[1]

      if !details
        return false
      end

      # Ancestry and character class checks
      # Dedication check for class feats is not done in this function.

      cinfo = char.pf2_base_info
      feat_type = details['feat_type']

      # Lineage feats are explicitly for select heritages and can only be taken at level 1.
      
      if feat_type.include? 'Lineage'

        heritage = cinfo['heritage'].downcase
        traits = details['traits']

        msg << 'lineage' unless traits.include?(heritage) && (char.pf2_level == 1)
      end

      if feat_type.include? 'Charclass'
        charclass = cinfo['charclass']
        allowed_charclasses = details['assoc_charclass']

        msg << 'charclass' unless allowed_charclasses.include? charclass
      elsif feat_type.include? 'Ancestry'
        ancestry = []

        ancestry << cinfo['ancestry']
        ancestry << cinfo['adopted ancestry'] if cinfo['adopted ancestry']

        # # Add allowances for Silyara and Ghaluch
        ancestry << "Sildanyar" if cinfo['heritage'] == "Silyara"
        ancestry << "Oruch" if cinfo['heritage'].include? "Ghaluch"

        allowed_ancestry = details['assoc_ancestry']

        msg << 'ancestry' unless !allowed_ancestry.intersection(ancestry).empty?
      end

      # No double-dipping on base class / dedication, per Paizo RAW.
      msg << 'dedication' unless dedication_allowed?(char, details)

      # Prereq check, prerequisites includes level

      prereqs = details["prereq"]

      if prereqs
        # Some feats use non-default character level for purposes of prereq checks.
        cl = char.pf2_level
        cl = 2 if Global.read_config('pf2e','basic_mc_feats').include? feat
        cl = cl/2 if Global.read_config('pf2e','adv_mc_feats').include? feat
        cl = cl + 1 if char.advancing
        #cl = cl + 1 if !char.is_approved? || !char.chargen_locked # Allows for level 1 feats in cg

        meets_prereqs = Pf2e.meets_prereqs?(char, prereqs, cl)
      else
        meets_prereqs = true
      end

      msg << "prerequisites" if !meets_prereqs

      return true if msg.empty?
      return false
    end

    def self.meets_prereqs?(char, prereqs, cl)
      msg = []

      prereqs.each_pair do |ptype, required|

        if required.is_a?(String) && required =~ /\//
          string = required.split("/")
          factor = string[0]
          minimum = string[1]
        end

        case ptype
        when "level"
          msg << "level" if prereqs['level'] > cl
        when "ability"
          # There can be more than one ability prereq, so required is passed as an array.
          required.each_with_index do |item, i|
            string = item.split("/")
            factor = string[0]
            minimum = string[1]

            char_score = Pf2eAbilities.get_score(char, factor)
            msg << "ability#{i}" if char_score < minimum.to_i
          end
        when "skill"
          skill_prof = char.advancing ? Pf2e.preview_skill_prof(char, factor) : Pf2eSkills.get_skill_prof(char, factor)
          char_prof = Pf2e.get_prof_bonus(char, skill_prof)
          min_prof = Pf2e.get_prof_bonus(char, minimum)

          msg << "skill" if char_prof < min_prof
        when "specialize"
          if required.start_with?('!')
            banned = required.delete('!').upcase
            msg << "specialize" if banned == kit
          else
            kit = char.pf2_base_info["specialize"].upcase
            msg << "specialize" if required.upcase != kit
          end
        when "has_focus_pool"
          magic = char.magic
          msg << "focus_pool" && next unless magic

          pool = magic.focus_pool['max']
          msg << "focus_pool" if pool.zero?
        when "feat"
          feats = char.advancing ? Pf2e.preview_feat_names(char) : char.pf2_feats.values.flatten.map { |word| word.upcase }
          req = required.map { |word| word.upcase }
          

          msg << "feat" unless req.all? { |f| feats.include? f }
        when "heritage"
          if required.start_with?('!')
            banned = required.delete('!').set_upcase_name
            msg << "heritage" if banned == heritage
          else
            heritage = char.pf2_base_info["heritage"].upcase
            msg << "heritage" if required.upcase != heritage
          end
        when "special"
          char_specials = char.pf2_special.each { |s| s.upcase }
          msg << "special" unless char_specials.include?(required.upcase)
        when "tradition"
          magic = char.magic

          msg << "tradition" && next unless magic

          traditions = magic.tradition

          msg << "tradition" unless traditions.include? required
        when "innate_tradition"
          # Useful for when a feat has a prereq asking for any innate spell tradition, like Quelynos Adept.
          magic = char.magic

          msg << "innate_tradition" && next unless magic

          innate_spells = magic.innate_spells || {}
          required_traditions = Array(required).map { |t| t.to_s.downcase.strip }.reject(&:empty?)

          has_required_innate_tradition = innate_spells.values.any? do |spell_info|
            tradition = spell_info && spell_info['tradition']
            required_traditions.include?(tradition.to_s.downcase)
          end

          msg << "innate_tradition" unless has_required_innate_tradition
        when "combat_stats"
          combat = char.combat

          case factor
          when "Perception"
            prof = Pf2e.get_prof_bonus(char, combat.perception)
            min = Pf2e.get_prof_bonus(char, minimum)

            passes_check = min > prof ? false : true
          end

          msg << "combat_stats" unless passes_check
        when "oralign"
          alignment = char.pf2_faith["alignment"]
          
          msg << "alignment" unless required.include? alignment
        when "orfeat"
          feats = char.advancing ? Pf2e.preview_feat_names(char) : char.pf2_feats.values.flatten.map { |word| word.upcase }
          req = required.map { |word| word.upcase }

          msg << "feat" unless req.any? { |f| feats.include? f }
        when "orheritage"
          heritage = char.pf2_base_info["heritage"]

          msg << "heritage" unless required.include? heritage
        when "orskill"
          check = []
          required.each do |s|

          string = s.split("/")
          factor = string[0]
          minimum = string[1]

          skill_prof = char.advancing ? Pf2e.preview_skill_prof(char, factor) : Pf2eSkills.get_skill_prof(char, factor)
          char_prof = Pf2e.get_prof_bonus(char, skill_prof)
          min_prof = Pf2e.get_prof_bonus(char, minimum)

          check << char_prof - min_prof
          end

          msg << "orskill" unless check.any? { |i| i>= 0 }
        else
          msg << "missing_prereq_check #{ptype}"
        end
      end

      return true if msg.empty?
      return false
    end

    def self.has_feat?(char, feat)
      feat_list = char.pf2_feats.values.flatten.map { |f| f.upcase }

      feat_list.include?(feat.upcase)
    end

    def self.generate_list_details(featlist)

      feat_list=featlist

      @details = Global.read_config('pf2e_feats').select { |k,v| feat_list.include? k }

      list = []
      @details.each_pair do |feat, details|
        list << format_feat(feat, details)
      end

      list.sort

    end

    def self.get_feat_options(char, type)
      feats = {}
      ftype = type.capitalize
      conf_path = 'game/config/'
      
      case ftype
        when "Ancestry"
          feats.merge_yaml!(conf_path + "pf2e_feat_ancestry.yml")
          feats = feats["pf2e_feats"]
        when "Archetype"
          feats.merge_yaml!(conf_path + "pf2e_feat_dedication.yml")
          feats = feats["pf2e_feats"]
        when "Charclass"
          feats.merge_yaml!(conf_path + 'pf2e_feat_class.yml')
          feats = feats["pf2e_feats"]
        when "Dedication"
          feats.merge_yaml!(conf_path + "pf2e_feat_dedication.yml")
          feats = feats["pf2e_feats"]
        when "General"
          feats.merge_yaml!(conf_path + 'pf2e_feat_general.yml')
          feats.merge_yaml!(conf_path + 'pf2e_feat_skill.yml')
          feats = feats["pf2e_feats"]
        when "Skill"
          feats.merge_yaml!(conf_path + 'pf2e_feat_skill.yml')
          feats = feats["pf2e_feats"]
        else
          feats = Global.read_config('pf2e_feats')
        end
  
      list = []

      feats.each_pair do |name, details|
        
        can_take = can_take_feat?(char, name)
        is_of_type = details['feat_type'].include? ftype
        has_feat = has_feat?(char, name)

        list << name if (can_take && is_of_type && !has_feat)

      end

      list.sort

    end

    def self.format_feat(feat, details)

      return t('pf2e.feat_details_missing', :name => feat.upcase) if !details

      fmt_name = "%x172#{feat}%xn"
      feat_type = "%x229Feat Type:%xn #{details['feat_type'].sort.join(", ")}"

      # Depending on feat type, this may be different keys with different formats.

      if details.has_key? 'assoc_charclass'
        associated = "%x229Associated Classes:%xn #{details['assoc_charclass'].sort.join(", ")}"
      elsif details.has_key? 'assoc_archetype'
        associated = "%x229Associated Archetypes:%xn #{details['assoc_archetype'].sort.join(", ")}"
      elsif details.has_key? 'assoc_ancestry'
        associated = "%x229Associated Ancestries:%xn #{details['assoc_ancestry'].sort.join(", ")}"
      elsif details.has_key? 'assoc_skill'
        skills = Array(details['assoc_skill']).compact
        associated = "%x229Associated Skills:%xn #{skills.sort.join(", ")}"
      else
        associated = "%x229Associated With:%xn Any"
      end

      if details.has_key?('traits') && !details['traits'].empty?
        traits = "%x229Traits:%xn #{details['traits'].sort.map(&:capitalize).join(", ")}"
      else
        traits = "%x229Traits:%xn None"
      end

      # Prerequisites needs its own level of formatting.

      prereq_list = []

      if details['prereq'].is_a?(Hash)
        details['prereq'].each_pair do |k,v|
          key_display = k.capitalize

          if k == 'orfeat'
            key_display = 'One of the following feat'
          elsif k == 'orskill'
            key_display = 'One of the following skill'
          elsif k == 'oralign'
            key_display = 'One of the following alignment'
          elsif k == 'innate_tradition'
            key_display = 'Innate spell tradition'
          end
          
          if v.is_a?(Array)
            key_display = key_display + "s" if v.length > 1
            # Array: key(s): followed by bulleted items
            prereq_list << "%r%t%xh%xw#{key_display}:%xn"
            v.each do |item|
              prereq_list << "%r%t  - #{item}"
            end
          else
            # Single value: key: value on same line
            prereq_list << "%r%t%xh%xw#{key_display}:%xn #{v}"
          end
        end
      end

      prereqs = "%x229Prerequisites:%xn" + prereq_list.join()

      desc = "%x229Description:%xn #{details['shortdesc']}"

      "#{fmt_name}%r%r#{feat_type}%r#{associated}%r#{traits}%r#{prereqs}%r#{desc}"
    end

    def self.feat_messages(char)
      msgs = []
      to_assign = char.pf2_to_assign

      if to_assign['charclass feat']
        msgs << t('pf2e.unassigned_class_feat') if to_assign['charclass feat'].include? 'open'
      end

      if to_assign['general feat']
        msgs << t('pf2e.unassigned_general_feat') if to_assign['general feat'].include? 'open'
      end

      if to_assign['ancestry feat']
        msgs << t('pf2e.unassigned_ancestry_feat') if to_assign['ancestry feat'].include? 'open'
      end

      if to_assign['skill feat']
        msgs << t('pf2e.unassigned_skill_feat') if to_assign['skill feat'].include? 'open'
      end

      if to_assign['special feat']
        msgs << t('pf2e.unassigned_gated_feat', :options => to_assign['special feat'].sort.join(", "))
      end

      return nil if msgs.empty?
      return msgs
    end

    def self.assess_feat_grants(info)
      hash = {}
      assign = {}
      advance = {}

      info.each_pair do |k,v|
        case k
        when "assign", "gated_feat"
          assign[k] = v
        else
          advance[k] = v
        end
      end

      hash['assign'] = assign
      hash['advance'] = advance

      hash
    end

    def self.do_feat_grants(char, info, charclass, client)
      # Processes cases where taking a feat grants something else.

      return_msg = []
      info.each_pair do |key, value|
        case key
        when 'magic_stats'
          update = PF2Magic.update_magic(char, charclass, value, client)
          # Use core classes explicitly to avoid any constant shadowing.
          return_msg << update if update.is_a?(::String)

          source_counts = {
            'repertoire' => {},
            'spellbook' => {}
          }

          if update.is_a?(::Hash)
            update.each_pair do |update_key, v|
              next unless source_counts.key?(update_key)

              if v.is_a?(Hash)
                v.each_pair do |level, list|
                  level_label = level.to_s.downcase
                  open_count = Array(list).count { |entry| entry.to_s.downcase == 'open' }
                  next if open_count.zero?

                  source_counts[update_key][level_label] ||= 0
                  source_counts[update_key][level_label] += open_count
                end
              elsif v.is_a?(Array)
                open_count = v.count { |entry| entry.to_s.downcase == 'open' }
                next if open_count.zero?

                source_counts[update_key]['1'] ||= 0
                source_counts[update_key]['1'] += open_count
              end
            end
          end

          innate_spells = char.magic&.innate_spells || {}
          open_innate = innate_spells.select { |k, _| k.to_s.casecmp?('open') }
          open_innate_labels = open_innate.values.map do |info|
            level_label = info['level'].to_s.downcase
            is_cantrip = (level_label == 'cantrip' || level_label == '0')
            tradition = Array(info['tradition']).first
            tradition_label = tradition.to_s.empty? ? 'unknown tradition' : tradition.to_s

            if is_cantrip
              "innate cantrip (#{tradition_label})"
            else
              "innate #{Pf2emagic.ordinal_level(level_label)}-level spell (#{tradition_label})"
            end
          end

          details_parts = []

          open_innate_counts = open_innate_labels.tally
          open_innate_counts.each_pair do |label, count|
            plural_label = Pf2emagic.pluralize_label(label, count)
            details_parts << "#{count} #{plural_label} to assign"
          end

          source_counts.each_pair do |source, level_counts|
            next if level_counts.empty?

            level_counts.each_pair do |level_label, count|
              is_cantrip = (level_label == 'cantrip' || level_label == '0')
              level_text = is_cantrip ? 'cantrip' : "#{Pf2emagic.ordinal_level(level_label)}-level spell"
              level_text = Pf2emagic.pluralize_label(level_text, count)

              if source == 'spellbook'
                details_parts << "#{count} #{level_text} to add to your spellbook"
              elsif source == 'repertoire'
                details_parts << "#{count} #{level_text} to add to your repertoire"
              end
            end
          end

          if details_parts.any?
            details_text = Pf2emagic.join_with_and(details_parts)
            review_cmd = char.advancing ? 'advance/review' : 'cg/review'
            return_msg << t('pf2e.feat_grants_magic_open', :review_cmd => review_cmd, :details => details_text)
          else
            return_msg << t('pf2e.feat_grants_magic')
          end

          # Update_magic returns a hash intended to be stuffed into pf2_to_assign. Do that.
          if update.is_a?(::Hash) && !(update.empty?)
            return_msg << t('pf2e.feat_grants_addl', :element => 'magic')
            to_assign = char.pf2_to_assign.merge(update)

            char.update(pf2_to_assign: to_assign)
          end

        when 'assign'
          to_assign = char.pf2_to_assign

          value.each do |item|
            to_assign_subitem = to_assign[item] ? to_assign[item] : []
            to_assign_subitem << 'open'
            to_assign[item] = to_assign_subitem
            
            return_msg << t('pf2e.feat_grants_addl', :element => item)
          end

          char.update(pf2_to_assign: to_assign)
        when 'feat'
                    feats = char.pf2_feats
          
          value.each do |item|
            feat_info = get_feat_details(item)

            next if feat_info.is_a? String
            
            feat_type = feat_info[1]['feat_type'].first
            
            list = feats[feat_type] || []            
            
            qualify = Pf2e.can_take_feat?(char, item)            
            
            list << item if qualify            
            
            feats[feat_type] = list.sort
          end
          
          char.update(pf2_feats: feats)
        when 'gated_feat'
          to_assign = char.pf2_to_assign
          gated_feats = to_assign['special feat'] || []

          gated_feats << value
          to_assign['special feat'] = gated_feats
          char.update(pf2_to_assign: to_assign)
        when 'reagents'
          return_msg << "This feat grants reagents."
          Pf2e.update_reagents(char, value)
        when 'cantrip_expansion'
          base_class = char.pf2_base_info['charclass']
          caster_type = Pf2emagic.get_caster_type(base_class)

          magic = PF2Magic.get_create_magic_obj(char)

          if caster_type == 'prepared'
            spells_per_day = magic.spells_per_day || {}
            class_slots = spells_per_day[base_class] || {}
            cantrip_key = class_slots.keys.find { |k| k.to_s.downcase == 'cantrip' } || 'cantrip'

            class_slots[cantrip_key] = class_slots[cantrip_key].to_i + 2
            spells_per_day[base_class] = class_slots
            magic.update(spells_per_day: spells_per_day)

            return_msg << "You can prepare two additional cantrips each day."
          elsif caster_type == 'spontaneous'
            to_assign = char.pf2_to_assign
            repertoire = to_assign['repertoire'] || {}
            cantrip_key = repertoire.keys.find { |k| k.to_s.downcase == 'cantrip' } || 'cantrip'
            list = repertoire[cantrip_key] || []

            list.concat(Array.new(2, 'open'))
            repertoire[cantrip_key] = list
            to_assign['repertoire'] = repertoire
            char.update(pf2_to_assign: to_assign)

            return_msg << "This feat grants 2 cantrip choices for your repertoire."
          end
        when 'attack'
          combat = Pf2eCombat.get_create_combat_obj(char)
          unarmed_attacks = combat.unarmed_attacks

          value.each_pair do |attack, info|
            unarmed_attacks[attack] = info
          end

          combat.update(unarmed_attacks: unarmed_attacks)
          return_msg << "This feat grants an unarmed attack."
        when "skill"
          # The value of the skill subkey is an array.
          # Skills should check to see if the character already has training in that skill and grant a
          # free one if so.

          value.each do |skill|
            has_skill = Pf2eSkills.get_skill_prof(char, skill) == 'untrained' ? false : true

            if has_skill
              if (char.advancing || !char.is_approved?)
                to_assign = char.pf2_to_assign
                open_skills = to_assign['open skills'] || []
                open_skills << 'open'
                to_assign['open skills'] = open_skills
                char.update(pf2_to_assign: to_assign)
                return_msg << "You already had a skill granted by this feat, so you have another free skill to assign. Your skills have been unlocked. Please assign skills using 'skill/set free=<skill>' and then 'commit skills' when done. You may add other feats that grant skills before 'commit featskills'."
                char.update(pf2_skills_locked: false)
              else
                return_msg << "#{char.name} needs to choose a free skill."
              end
            else
              skill_obj = Pf2eSkills.find_skill(skill, char)

              Pf2eSkills.create_skill_for_char(skill, char) if !skill_obj

              Pf2eSkills.update_skill_for_char(skill, char, 'trained')
              return_msg << "This feat grants the skill #{skill}."
            end

          end
        when "combat_stats"
          # The value of the combat_stats subkey should always be a hash.
          Pf2eCombat.update_combat_stats(char, value)
          return_msg << "This feat modifies your combat proficiencies."
        else
          return_msg << "Unknown key '#{key}' in do_feat_grants. Please inform code staff."
        end

      end

      return_msg
    end

    def self.apply_init_magic_feat(char, feat_name, feat_details, client)
      return unless feat_details && feat_details['init_magic']

      spell_result = Pf2emagic.get_spell_details(feat_name)
      return if spell_result.is_a?(String)

      spell_name, spell_details = spell_result
      focus_type_by_class = Global.read_config('pf2e_magic', 'focus_type_by_class')
      focus_type = focus_type_by_class[char.pf2_base_info['charclass']] || 'devotion'

      key = spell_details['base_level'].to_i.zero? ? 'focus_cantrip' : 'focus_spell'
      spell_info = { key => { focus_type => [ spell_name ] } }

      PF2Magic.update_magic(char, char.pf2_base_info['charclass'], spell_info, client)
    end

    def self.can_take_gated_feat?(char, feat, gate)
      Global.logger.debug "#{feat} - #{gate}"
      # This function is called whenever the gated_feat key is present. It is used for any
      # feat that has specific limits on what can be taken.

      if gate.downcase == "deity's domain"
        deity = char.pf2_faith['deity']
        deity_info = Global.read_config('pf2e_deities')[deity]
        return false unless deity_info

        deity_domains = Array(deity_info['domains']).compact
        return deity_domains.any? { |d| d.casecmp?(feat) }
      end

      find_feat = Pf2e.get_feat_details(feat)
      return false if find_feat.is_a?(String) || !find_feat[1]

      fdeets = find_feat[1]
      qualifies = fdeets["feat_type"]

      # If you don't meet the prereqs for the feat, don't bother processing the gate.
      return false unless qualifies

      # Block Dedication feats for the character's own class.
      return false unless dedication_allowed?(char, fdeets)

      
      case gate.downcase
      when 'universalist'
        # This key is for the extra wizard feat universalists get at first level.
        charclass = fdeets['assoc_charclass']

        passes_gate = charclass.include? 'Wizard'
      when 'metamagic'
        # Some feats grant an extra metamagic feat. Test this gate for those.

        traits = fdeets['traits'].map {|t| t.downcase }

        passes_gate = traits.include? 'metamagic'
      when "natural ambition"
        level = fdeets['prereq']['level'] == 1

        char_base_class = char.pf2_base_info['charclass']

        feat_type = fdeets['feat_type']&.include? 'Charclass'

        feat_charclass = fdeets['assoc_charclass']&.include? char_base_class

        passes_gate = level && feat_type && feat_charclass
      when "ancestral paragon"
        feat_type = fdeets['feat_type']&.include?('Ancestry')
        prereq_level = fdeets.dig('prereq', 'level')
        level_ok = !prereq_level.nil? && prereq_level.to_i <= 1

        passes_gate = feat_type && level_ok && Pf2e.can_take_feat?(char, feat)
      when "general training"
        feat_type = fdeets['feat_type']&.include?('General')
        prereq_level = fdeets.dig('prereq', 'level')
        level_ok = !prereq_level.nil? && prereq_level.to_i <= 1

        passes_gate = feat_type && level_ok && Pf2e.can_take_feat?(char, feat)
      when "advanced general training"
        feat_type = fdeets['feat_type']&.include?('General')
        prereq_level = fdeets.dig('prereq', 'level')
        level_ok = !prereq_level.nil? && prereq_level.to_i <= 7

        passes_gate = feat_type && level_ok && Pf2e.can_take_feat?(char, feat)
      when "skillful lesson"
        skills_hash = Global.read_config('pf2e_skills')
        needed_key_abil = %w(Intelligence Wisdom Charisma)

        good_skills = skills_hash.select { |name, detail| needed_key_abil.include? detail['key_abil'] }.keys

        assoc_skill = fdeets['assoc_skill']

        if assoc_skill
          passes_gate = good_skills.include? assoc_skill
        end

      when "charclass", "ancestry", "general", "skill"
        if fdeets['feat_type']&.include?('Dedication')
          passes_gate = true
        else
          passes_gate = false
        end
        passes_gate = fdeets['feat_type']&.include?(gate.titleize)
        Global.logger.debug "#{passes_gate}"
      else
        # If it doesn't recognize the key for the gate, fail it.
        passes_gate = false
      end

      # I've already checked qualifies for truth, so now it's a matter of checking whether the
      # feat meets the gate requirements.

      passes_gate
    end

    def self.get_gated_feat_options(char, gate)
      feats = Global.read_config('pf2e_feats')

      list = []

      feats.each_pair do |name, details|

        can_take = can_take_gated_feat?(char, name, gate)
        has_feat = has_feat?(char, name)

        list << name if (can_take && !has_feat)

      end

      list.sort
    end

    def self.gated_feat_summary(gate)
      # Summaries for the advance/review screen when a gated feat is pending assignment.
      return "eligible feat" if gate.nil?

      summaries = {
        "ancestral paragon" => "1st-level ancestry feat",
        "general training" => "1st-level general feat",
        "advanced general training" => "7th-level or lower general feat",
        "natural ambition" => "1st-level class feat",
        "metamagic" => "metamagic feat",
        "universalist" => "wizard feat",
        "skillful lesson" => "skill with an Intelligence, Wisdom, or Charisma key ability",
        "deity's domain" => "deity domain",
        "canny acumen" => "Fortitude, Reflex, Will, or Perception"
      }

      summaries[gate.to_s.downcase] || "eligible feat"
    end

  end
end
