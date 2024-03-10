module AresMUSH
  module Pf2e

    include CommonTemplateFields

    def self.get_feat_details(term)
      return "no_term" unless term.is_a? String

      feats = Global.read_config('pf2e_feats')

      keys = feats.keys

      # Give me an array of all the feats that match the term.
      match = keys.select { |f| f.upcase.match? term.upcase }

      return 'no_match' if match.empty?
      return 'ambiguous' if match.size > 1

      # Pull the unique feat name out of the array so it can be used as a key to get the feat deets.
      name = match.first

      # First is the name of the feat matched, the second is the details for the feat.
      return [ name, feats[name] ]
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
        match = feat_info.select { |k,v| v['assoc_skill']&.include? term.capitalize }
      when 'description', 'desc'
        match = feat_info.select { |k,v| v['shortdesc'].upcase.match? term.upcase }
      when 'classlevel'
        feats_by_class = feat_info.select { |k,v| v['assoc_charclass']&.include? operator.capitalize }
        match = feats_by_class.select { |k,v| v['prereq']['level'] == term.to_i }
      end

      match

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

      if feat_type.include? 'Charclass'
        charclass = cinfo['charclass']
        allowed_charclasses = details['assoc_charclass']

        msg << 'charclass' unless allowed_charclasses.include? charclass
      elsif feat_type.include? 'Ancestry'
        ancestry = []

        ancestry << cinfo['ancestry']
        ancestry << cinfo['adopted ancestry'] if cinfo['adopted ancestry']

        # # Add allowances for Half-Sil and Half-Oruch
        ancestry << "Sildanyar" if cinfo['heritage'].include? "Half-Sil"
        ancestry << "Oruch" if cinfo['heritage'].include? "Half-Oruch"

        Global.logger.debug ancestry

        allowed_ancestry = details['assoc_ancestry']

        msg << 'ancestry' unless allowed_ancestry.intersect? ancestry
      end

      # Prereq check, prerequisites includes level

      prereqs = details["prereq"]

      if prereqs
        # Some feats use non-default character level for purposes of prereq checks.
        cl = char.pf2_level
        cl = 2 if Global.read_config('pf2e','basic_mc_feats').include? feat
        cl = cl/2 if Global.read_config('pf2e','adv_mc_feats').include? feat

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

        if required =~ /\//
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
          char_prof = Pf2e.get_prof_bonus(char, Pf2eSkills.get_skill_prof(char, factor))
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
          nil
        when "feat"
          feats = char.pf2_feats.values.flatten.map { |word| word.upcase }
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
        when "combat_stats"
          combat = char.combat

          case factor
          when "Perception"
            prof = Pf2e.get_prof_bonus(char, combat.perception)
            min = Pf2e.get_prof_bonus(char, minimum)

            passes_check = min > prof ? false : true
          end

          msg << "combat_stats" unless passes_check
        when "orfeat"
          feats = char.pf2_feats.values.flatten.map { |word| word.upcase }
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

          char_prof = Pf2e.get_prof_bonus(char, Pf2eSkills.get_skill_prof(char, factor))
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
      feats = Global.read_config('pf2e_feats')
      ftype = type.capitalize

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
        associated = "%x229Associated To:%xn #{details['assoc_charclass'].sort.join(", ")}"
      elsif details.has_key? 'assoc_ancestry'
        associated = "%x229Associated To:%xn #{details['assoc_ancestry'].sort.join(", ")}"
      elsif details.has_key? 'assoc_skill'
        associated = "%x229Associated To:%xn #{details['assoc_skill']}"
      else
        associated = "%x229Associated To:%xn Any"
      end

      traits = "%x229Traits:%xn #{details['traits'].sort.join(", ")}"

      # Prerequisites needs its own level of formatting.

      prereq_list = []

      details['prereq'].each_pair do |k,v|
        prereq_list << "%r%t%xh%xw#{k.capitalize}:%xn #{v}"
      end

      prereqs = "%x229Prerequisites:%xn #{prereq_list.join()}"

      desc = "%x229Description:%xn #{details['shortdesc']}"

      "#{fmt_name}%r%r#{feat_type}%r#{associated}%r#{traits}%r#{prereqs}%r#{desc}"
    end

    def self.feat_messages(char)
      msgs = []
      to_assign = char.pf2_to_assign

      if to_assign['charclass feat']
        msgs << t('pf2e.unassigned_class_feat') if to_assign['charclass feat'].include? 'open'
      end

      if to_assign['ancestry feat']
        msgs << t('pf2e.unassigned_ancestry_feat') if to_assign['ancestry feat'].include? 'open'
      end

      if to_assign['special feat']
        msgs << t('pf2e.unassigned_gated_feat', :options => to_assign['special feat'].sort.join(", "))
      end

      return nil if msgs.empty?
      return msgs
    end

    def self.do_feat_grants(char, info, charclass, client)
      # Processes cases where taking a feat grants something else.

      return_msg = []
      info.each_pair do |key, value|
        case key
        when 'magic_stats'
          return_msg << "This feat grants magic."
          error = PF2Magic.update_magic(char, charclass, value, client)
          return_msg << error if error
        when 'assign'
          to_assign = char.pf2_to_assign

          value.each do |item|
            to_assign_subitem = to_assign[item] ? to_assign[item] : []
            to_assign_subitem << 'open'
            to_assign[item] = to_assign_subitem

            return_msg << t('pf2e.feat_grants_addl', :element => assign_key)
          end

          char.update(pf2_to_assign: to_assign)
        when 'feat'
          feats = char.pf2_feats

          value.each { |item| feats << item }

          char.update(pf2_feats: feats.sort)
        when 'gated_feat'
          to_assign = char.pf2_to_assign
          gated_feats = to_assign['special feat'] || []

          gated_feats << value
          to_assign['special feat'] = gated_feats
          char.update(pf2_to_assign: to_assign)
        when 'reagents'
          return_msg << "This feat grants reagents."
          Pf2e.update_reagents(char, value)
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
                return_msg << "You already had a skill granted by this feat, so you have another free skill to assign."
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
        else
          return_msg << "Unknown key '#{key}' in do_feat_grants. Please inform code staff."
        end

      end

      return_msg
    end

    def self.can_take_gated_feat?(char, feat, gate)
      # This function is called whenever the gated_feat key is present. It is used for any
      # feat that has specific limits on what can be taken.

      qualifies = can_take_feat?(char, feat)

      # If you don't meet the prereqs for the feat, don't bother processing the gate.
      return false unless qualifies

      find_feat = Pf2e.get_feat_details(feat)

      fdeets = find_feat[1]

      case gate.downcase
      when 'universalist'
        # This key is for the extra wizard feat universalists get at first level.
        charclass = fdeets['assoc_charclass']

        passes_gate = charclass.include? 'Wizard'
      when 'metamagic'
        # Some feats grant an extra metamagic feat. Test this gate for those.

        traits = fdeets['traits'].map {|t| t.downcase }

        passes_gate = traits.include? 'metamagic'
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

  end
end
