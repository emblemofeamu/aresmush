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
      find_feat = Pf2e.get_feat_details(feat)

      # This will come back as a string if the feat name is bad or not unique.
      return false if find_feat.is_a? String

      # Pass the canonical name rather than what the caller typed, so the multiclass feat
      # lists below match.
      can_take_feat_details?(char, find_feat[0], find_feat[1])
    end

    # Eligibility check for a feat whose details the caller already has.
    def self.can_take_feat_details?(char, feat, details, effective_level = nil, ignore_charclass = false)
      return false if !details

      msg = []

      # Ancestry and character class checks
      # Dedication check for class feats is not done in this function.

      cinfo = char.pf2_base_info
      feat_type = details['feat_type']

      return false if !feat_type

      # Lineage feats are explicitly for select heritages and can only be taken at level 1.
      
      if feat_type.include? 'Lineage'

        heritage = cinfo['heritage'].downcase
        traits = details['traits']

        msg << 'lineage' unless traits.include?(heritage) && (char.pf2_level == 1)
      end

      if feat_type.include? 'Charclass'
        charclass = cinfo['charclass']
        allowed_charclasses = details['assoc_charclass']

        # Dedication and archetype feats are typed Charclass but deliberately carry no
        # assoc_charclass, so that feat/search class=Fighter returns fighter class feats
        # rather than fighter archetype ones. Who may take them is handled by assoc_class in
        # dedication_allowed?, and by their prereq chain back to the dedication feat.
        unless ignore_charclass
          msg << 'charclass' if allowed_charclasses && !allowed_charclasses.include?(charclass)
        end
      elsif feat_type.include? 'Ancestry'
        ancestry = []

        ancestry << cinfo['ancestry']

        # # Add allowances for Silyara and Ghaluch
        ancestry << "Sildanyar" if cinfo['heritage'] == "Silyara"
        ancestry << "Oruch" if cinfo['heritage'].include? "Ghaluch"

        allowed_ancestry = details['assoc_ancestry']

        if allowed_ancestry.intersection(ancestry).empty?
          # An adopted ancestry is handled separately from the ones the character was born
          # with, because it opens only that ancestry's adopted_feats rather than its whole
          # list.
          adopted = adopted_ancestries(char).any? do |a|
            allowed_ancestry.include?(a) && adopted_feat?(a, feat)
          end

          msg << 'ancestry' unless adopted
        end
      end

      # No double-dipping on base class / dedication, per Paizo RAW.
      msg << 'dedication' unless dedication_allowed?(char, details)

      # Prereq check, prerequisites includes level

      prereqs = details["prereq"]

      if prereqs
        cl = effective_level || effective_char_level(char)

        meets_prereqs = Pf2e.meets_prereqs?(char, prereqs, cl)
      else
        meets_prereqs = true
      end

      msg << "prerequisites" if !meets_prereqs

      return true if msg.empty?
      return false
    end

    # Every subclass the character counts as having for prerequisite purposes: the one from
    # their own class, plus one per archetype they have taken.
    def self.held_specialties(char)
      info = char.pf2_archetypeinfo || {}

      held = (1..4).map { |i| info["archetype_specialty#{i}"] }
      held << char.pf2_base_info['specialize']

      if char.advancing
        pending = (char.pf2_to_assign || {})['archetype_specialty']
        held << pending unless pending.blank? || pending.to_s.casecmp?('open')
      end

      held.compact.map { |s| s.to_s.strip.upcase }.reject(&:empty?)
    end

    # Every focus spell the character knows, across all focus types, spells and cantrips
    # alike. Names only -- the type a focus spell is filed under is not what prereqs ask about.
    def self.held_focus_spells(char)
      magic = char.magic
      return [] unless magic

      lists = Array(magic.focus_spells&.values) + Array(magic.focus_cantrips&.values)

      lists.flatten.compact.map { |s| s.to_s.strip }.reject(&:empty?)
    end

    # A more useful reason than "you do not meet the prerequisites", where one exists.
    # Returns nil when there is nothing better to say and the generic message should stand.
    def self.explain_feat_block(char, details)
      prereqs = details.is_a?(Hash) ? details['prereq'] : nil
      return nil unless prereqs.is_a?(Hash)

      return t('pf2e.needs_divine_font') if prereqs['divine_font'] && char.magic&.divine_font.blank?
      return t('pf2e.needs_caster') if prereqs['caster'] && !character_is_caster?(char)

      nil
    end

    def self.meets_prereqs?(char, prereqs, cl)
      msg = []

      prereqs.each_pair do |ptype, required|
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
          Array(required).each_with_index do |entry, i|
            skill_name, minimum_prof = entry.to_s.split("/")

            skill_prof = char.advancing ? Pf2e.preview_skill_prof(char, skill_name) : Pf2eSkills.get_skill_prof(char, skill_name)
            char_prof = Pf2e.get_prof_bonus(char, skill_prof)
            min_prof = Pf2e.get_prof_bonus(char, minimum_prof)

            msg << "skill#{i}" if char_prof < min_prof
          end
        when "specialize"
          held = held_specialties(char)

          wanted = Array(required).compact.map { |r| r.to_s.strip }.reject(&:empty?)
          banned, allowed = wanted.partition { |r| r.start_with?('!') }

          msg << ptype if banned.any? { |r| held.include?(r.delete('!').upcase) }
          msg << ptype if allowed.any? && allowed.none? { |r| held.include?(r.upcase) }
        when "focus_spell"
          # Focus spells are filed under whatever granted them -- devotion, revelation, qi --
          # and the prereq names only the spell, so the type is flattened away. Cantrips are
          # stored separately from spells but a prereq naming one should still match.
          held = held_focus_spells(char)

          wanted = Array(required).compact.map { |s| s.to_s.strip }.reject(&:empty?)

          msg << "focus_spell" if wanted.any? && wanted.none? { |s| held.any? { |h| h.casecmp?(s) } }
        when "divine_font"
          font = char.magic&.divine_font

          if font.blank?
            msg << "divine_font"
          else
            msg << "divine_font" unless Array(required).any? { |f| f.to_s.casecmp?(font.to_s) }
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
        when "caster"
          # "ability to cast spells" / "ability to cast cantrips". Both are the same test
          # here -- casting through a spellcasting class -- with the value ('spells' or
          # 'cantrips') kept only for readability in config.
          msg << "caster" unless character_is_caster?(char)
        when "heritage"
          held = char.pf2_base_info["heritage"].to_s.strip.upcase
          wanted = required.to_s.strip

          if wanted.start_with?('!')
            msg << "heritage" if wanted.delete_prefix('!').strip.upcase == held
          else
            msg << "heritage" if wanted.upcase != held
          end
        when "special"
          # Takes one special or a list, and a list means all of them, the same way the skill
          # and feat prereqs above do.
          held = Array(char.pf2_special).map { |s| s.to_s.strip.upcase }
          wanted = Array(required).compact.map { |s| s.to_s.strip.upcase }.reject(&:empty?)

          msg << "special" unless wanted.all? { |s| held.include?(s) }
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
          factor, minimum = required.to_s.split("/")

          passes_check = true

          case factor
          when "Perception"
            prof = Pf2e.get_prof_bonus(char, combat.perception)
            min = Pf2e.get_prof_bonus(char, minimum)

            passes_check = min > prof ? false : true
          else
            Global.logger.error "Unhandled combat_stats prereq '#{required}'."
          end

          msg << "combat_stats" unless passes_check
        when "oralign"
          alignment = char.pf2_faith["alignment"]
          
          msg << "alignment" unless required.include? alignment
        when "ordeity"
          deity = char.pf2_faith["deity"]

          if char.advancing
            pending = (char.pf2_advancement || {})['archetype_deity']
            deity = pending unless pending.blank?
          end

          if deity.blank?
            msg << "deity"
          else
            msg << "deity" unless Array(required).any? { |d| d.to_s.casecmp?(deity.to_s) }
          end
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
        when "anyskills"
          # "At least N skills at rank X or better", for feats whose prereq names no
          # particular skill - Skill Mastery's "trained in at least one skill and expert in
          # at least one skill". Entries are "rank/count" strings.
          progression = Global.read_config('pf2e', 'prof_progression') || []

          skill_names = char.skills.map { |s| s.name }

          if char.advancing
            advancement = char.pf2_advancement || {}
            pending = Array(advancement['raise skill']) + Array(advancement['raise skill choice'])
            pending = pending.reject { |s| s.to_s.strip.empty? || Pf2e.open_skill_token?(s) }

            skill_names = (skill_names + pending).uniq { |s| s.to_s.downcase }
          end

          char_ranks = skill_names.map do |s|
            prof = char.advancing ? Pf2e.preview_skill_prof(char, s) : Pf2eSkills.get_skill_prof(char, s)
            progression.index(prof) || 0
          end

          Array(required).each_with_index do |entry, i|
            rank, count = entry.to_s.split("/")
            min_rank = progression.index(rank.to_s.strip.downcase) || 0
            needed = count.nil? ? 1 : count.to_i

            msg << "anyskills#{i}" if char_ranks.count { |r| r >= min_rank } < needed
          end
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

    # How many times this feat may be taken in total. Infinity when uncapped.
    def self.feat_repeat_max(details)
      return 1 unless details.is_a?(Hash)

      spec = details['repeatable']

      return 1 if spec.nil? || spec == false
      return Float::INFINITY if spec == true
      return spec.to_i if spec.is_a?(Integer)
      return spec['max'] ? spec['max'].to_i : Float::INFINITY if spec.is_a?(Hash)

      1
    end

    def self.feat_repeatable?(details)
      feat_repeat_max(details) > 1
    end

    # Minimum character level for the nth taking.
    def self.feat_repeat_level(details, nth)
      return nil unless details.is_a?(Hash)

      spec = details['repeatable']
      return nil unless spec.is_a?(Hash)

      levels = Array(spec['levels'])
      return nil if levels.empty?

      levels[nth - 1]
    end

    # How many times the character has already holds this feat.
    def self.feat_taken_count(char, feat_name)
      char.pf2_feats.values.flatten.count { |f| f.to_s.casecmp?(feat_name.to_s) }
    end

    # Whether another instance may be taken. Returns nil when allowed, or a failure message.
    def self.feat_repeat_block(char, feat_name, details, taken = nil, level = nil)
      taken ||= feat_taken_count(char, feat_name)
      return nil if taken.zero?

      max = feat_repeat_max(details)

      return t('pf2e.already_has', :item => 'feat') if max <= 1
      return t('pf2e.feat_repeat_maxed', :feat => feat_name, :max => max.to_i) if taken >= max

      required = feat_repeat_level(details, taken + 1)
      cl = level || char.pf2_level

      if required && cl < required.to_i
        return t('pf2e.feat_repeat_too_low', :feat => feat_name, :level => required)
      end

      nil
    end

    # feat_name => times held, upcased, for loops that would otherwise re-flatten per feat.
    def self.feat_tally(char)
      tally = Hash.new(0)
      char.pf2_feats.values.flatten.each { |f| tally[f.to_s.upcase] += 1 }

      tally
    end

    # How many picks one taking of a feat's choice resolves: 1 for an ordinary choice, more
    # when it chains further picks with then_choose (Adapted Cantrip: a tradition, then a
    # cantrip). Feats with no choice count as 1.
    def self.choice_sequence_depth(feat_name)
      block = feat_choice_block_for(feat_name)
      depth = 0

      while block.is_a?(Hash)
        depth += 1
        block = block['then_choose']
      end

      [ depth, 1 ].max
    end

    # Expands a stored feat list into display names, one entry per instance, with each
    # instance's recorded choice in parentheses.
    #
    # A repeatable feat is stored once per taking, so Assurance taken for Nature and then
    # Athletics reads as "Assurance (Nature), Assurance (Athletics)" rather than collapsing
    # to a single entry. A then_choose feat records several picks for one taking, so those
    # are shown together, slash-joined: "Adapted Cantrip (Primal/Electric Arc)".
    def self.feat_display_list(char, feat_names)
      names = Array(feat_names).compact.map(&:to_s)
      labels = []

      names.uniq.each do |name|
        count = names.count { |n| n.casecmp?(name) }
        depth = choice_sequence_depth(name)

        # choice_labels_for is flat; a then_choose feat contributes `depth` labels per
        # taking, so slice it back into one run per instance.
        runs = choice_labels_for(char, name).each_slice(depth).first(count)

        runs.each { |run| labels << "#{name} (#{run.join('/')})" }

        remaining = count - runs.size
        next if remaining.zero?

        labels << (remaining > 1 ? "#{name} (x#{remaining})" : name)
      end

      labels
    end

    # Full detail blocks for a list of feats.
    def self.generate_list_details(featlist, char = nil)

      feat_list=featlist

      @details = Global.read_config('pf2e_feats').select { |k,v| feat_list.include? k }

      list = []
      @details.each_pair do |feat, details|
        list << format_feat(feat_detail_heading(char, feat), details)
      end

      list.sort

    end

    def self.feat_detail_heading(char, feat)
      return feat unless char

      choices = choice_labels_for(char, feat)
      return "#{feat} (#{choices.join(', ')})" unless choices.empty?

      count = feat_taken_count(char, feat)
      count > 1 ? "#{feat} (x#{count})" : feat
    end

    def self.get_feat_options(char, type)
      ftype = type.capitalize

      # experimental feat lookup fix
      feats = Global.read_config('pf2e_feats') || {}

      list = []

      # Tallied once rather than rebuilt inside the loop by has_feat?. A repeatable feat
      # stays in the list until it is actually maxed out.
      tally = feat_tally(char)

      feats.each_pair do |name, details|
        # Cheap filters first, so most candidates never reach the eligibility check.
        next unless Array(details['feat_type']).include? ftype
        next if feat_repeat_block(char, name, details, tally[name.to_s.upcase])

        list << name if can_take_feat_details?(char, name, details)
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

          # Set by keys whose plural is not the label plus an "s".
          skip_plural = false

          if k == 'orfeat'
            key_display = 'One of the following feat'
          elsif k == 'orskill'
            key_display = 'One of the following skill'
          elsif k == 'oralign'
            key_display = 'One of the following alignment'
          elsif k == 'ordeity'
            key_display = Array(v).length > 1 ? 'One of the following deities' : 'One of the following deity'
            skip_plural = true
          elsif k == 'innate_tradition'
            key_display = 'Innate spell tradition'
          elsif k == 'caster'
            key_display = 'Ability to cast'
          elsif k == 'anyskills'
            # Stored as "rank/count", which is not something to show a player as-is.
            key_display = 'Skill requirement'

            v = Array(v).map do |entry|
              rank, count = entry.to_s.split("/")
              num = count.nil? ? 1 : count.to_i

              "#{num} skill#{num == 1 ? '' : 's'} at #{rank} or better"
            end
          end

          if v.is_a?(Array)
            key_display = key_display + "s" if v.length > 1 && !skip_plural
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

      pending_feat_choices(char).each_pair do |name, slots|
        next unless Array(slots).include?('open')

        msgs << t('pf2e.unassigned_feat_choice', :choice => name)
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
        when "assign", "grant_choice"
          assign[k] = v
        else
          advance[k] = v
        end
      end

      hash['assign'] = assign
      hash['advance'] = advance

      hash
    end

    OPEN_SKILL_VALUES = %w(open choice)

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
              "innate #{Pf2emagic.ordinal_level(level_label)}-rank spell (#{tradition_label})"
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
              level_text = is_cantrip ? 'cantrip' : "#{Pf2emagic.ordinal_level(level_label)}-rank spell"
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
          Array(value).each do |entry|
            parsed = granted_feat_entry(entry)
            next unless parsed

            fname, label, source, filter = parsed
            found = get_feat_details(fname)

            if found.is_a?(String)
              Global.logger.error "A feat grant names '#{fname}', which did not resolve (#{found})."
              next
            end

            unless can_take_feat_details?(char, found[0], found[1])
              Global.logger.warn "#{char.name} was granted '#{found[0]}' but does not qualify for it."
              next
            end

            label = granted_choice_label(char, source) if source.present?

            return_msg.concat(add_granted_feat(char, found[0], found[1], charclass, client))
            return_msg.concat(resolve_granted_choice(char, found[0], found[1], label, client, filter))
          end
        when 'grant_choice'
          to_assign = char.pf2_to_assign

          Array(value).compact.each { |name| open_feat_choice(to_assign, name.to_s) }

          char.update(pf2_to_assign: to_assign)
        when 'grant_choice_once'
          to_assign = char.pf2_to_assign

          Array(value).compact.each do |name|
            key = name.to_s

            next if Array((to_assign['feat choice'] || {})[key]).include?('open')
            next if choice_labels_for(char, key).any?

            open_feat_choice(to_assign, key)
          end

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
            open_choice = OPEN_SKILL_VALUES.include?(skill.to_s.downcase)
            has_skill = open_choice || Pf2eSkills.get_skill_prof(char, skill) != 'untrained'

            if has_skill
              if (char.advancing || !char.is_approved?)
                to_assign = char.pf2_to_assign
                open_skills = to_assign['open skills'] || []
                open_skills << 'open'
                to_assign['open skills'] = open_skills
                char.update(pf2_to_assign: to_assign)

                return_msg << if open_choice
                  "This feat grants a skill of your choice. Your skills have been unlocked. Assign it using 'skill/set free=<skill>', then enter 'commit featskills' to lock your skills again. You may take other feats that grant skills first."
                else
                  "You already had a skill granted by this feat, so you have another free skill to assign. Your skills have been unlocked. Assign it using 'skill/set free=<skill>', then enter 'commit featskills' to lock your skills again. You may take other feats that grant skills first."
                end

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
        when 'raise_skill'
          Array(value).compact.each do |skill_name|
            next if skill_name.to_s.strip.empty?

            Pf2eSkills.create_skill_for_char(skill_name, char) unless Pf2eSkills.find_skill(skill_name, char)

            skill = Pf2eSkills.find_skill(skill_name, char)
            next unless skill

            new_prof = Pf2eSkills.get_next_prof(char, skill_name)
            next if new_prof.blank? || new_prof.to_s.casecmp?(skill.prof_level.to_s)

            skill.update(prof_level: new_prof)
            return_msg << "Your proficiency in #{skill_name} increases to #{new_prof}."
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

    CASTER_TYPE_STAT_KEYS = %w(prepared spontaneous)

    def self.resolve_caster_type_stats(char, magic_stats)
      return magic_stats unless magic_stats.is_a?(Hash)
      return magic_stats unless magic_stats.keys.any? { |k| CASTER_TYPE_STAT_KEYS.include?(k.to_s.downcase) }

      caster_type = Pf2emagic.get_caster_type(char.pf2_base_info['charclass'])

      unconditional = magic_stats.reject { |k, _v| CASTER_TYPE_STAT_KEYS.include?(k.to_s.downcase) }
      matched = magic_stats.find { |k, _v| k.to_s.casecmp?(caster_type.to_s) }

      matched && matched[1].is_a?(Hash) ? unconditional.merge(matched[1]) : unconditional
    end

    def self.do_feat_magic_stats(char, feat_details, charclass, client)
      # Feats keep their magic in a top-level magic_stats block instead of under 'grants', so route it
      # through the same handler the 'grants' path uses. Returns the messages for the caller to emit.
      return [] if !feat_details.is_a?(Hash)

      magic_stats = feat_details['magic_stats']

      return [] if !magic_stats.is_a?(Hash) || magic_stats.empty?
      return [] if !AresMUSH.const_defined?("Pf2emagic")

      magic_stats = resolve_caster_type_stats(char, magic_stats)

      return [] if magic_stats.empty?

      do_feat_grants(char, { 'magic_stats' => magic_stats }, charclass, client)
    end

    def self.apply_init_magic_feat(char, feat_name, feat_details, client)
      return unless feat_details && feat_details['init_magic']

      spell_result = Pf2emagic.get_spell_details(feat_name)
      return if spell_result.is_a?(String)

      spell_name, spell_details = spell_result
      focus_type_by_source = Global.read_config('pf2e_magic', 'focus_type_by_source')
      focus_type = focus_type_by_source[char.pf2_base_info['charclass']] || 'devotion'

      key = spell_details['base_level'].to_i.zero? ? 'focus_cantrip' : 'focus_spell'
      spell_info = { key => { focus_type => [ spell_name ] } }

      PF2Magic.update_magic(char, char.pf2_base_info['charclass'], spell_info, client)
    end

    def self.feat_choice_def(feat_details)
      return nil unless feat_details.is_a?(Hash)

      block = feat_details['feat_choice']
      return nil unless block.is_a?(Hash)

      block
    end

    def self.feat_has_choice?(feat_details)
      !feat_choice_def(feat_details).nil?
    end

    # Pulls the name => block map off a class, subclass, or specialty level entry.
    def self.level_feat_choices(info)
      return {} unless info.is_a?(Hash)

      block = info['feat_choice']
      return {} unless block.is_a?(Hash)

      block.select { |_name, definition| definition.is_a?(Hash) }
    end

    def self.choice_summary(block)
      return 'eligible option' unless block.is_a?(Hash)

      (block['summary'] || 'eligible option').to_s
    end

    def self.choice_options(char, choice_name, block)
      return [] unless block.is_a?(Hash)

      options = if block['options'].is_a?(Hash)
        block['options'].keys.select { |label| choice_option_allowed?(char, block['options'][label]) }.sort
      elsif block['from_feats'].is_a?(Hash)
        choice_feat_pool(char, block['from_feats'])
      elsif block['from_skills'].is_a?(Hash)
        choice_skill_pool(char, block['from_skills'])
      elsif block['from_weapons'].is_a?(Hash)
        choice_weapon_pool(char, block['from_weapons'])
      elsif block['from_spells'].is_a?(Hash)
        choice_spell_pool(char, block['from_spells'], choice_name)
      elsif block.key?('from_lores')
        choice_lore_pool(char, block['from_lores'])
      elsif block['from']
        choice_dynamic_options(char, block['from'], block)
      else
        []
      end

      options = narrow_choice_options(char, choice_name, options)

      return options if block['allow_duplicates']

      taken = choice_labels_for(char, choice_name)
      return options if taken.empty?

      options.reject { |option| taken.any? { |t| t.to_s.casecmp?(option.to_s) } }
    end

    def self.match_choice_option(char, choice_name, block, label)
      return nil if label.blank?

      choice_options(char, choice_name, block).find { |option| option.to_s.casecmp?(label.to_s) }
    end

    def self.choice_option_allowed?(char, option_info)
      return true unless option_info.is_a?(Hash)

      prereq = option_info['prereq']
      return true unless prereq

      cl = char.pf2_level
      cl = cl + 1 if char.advancing

      meets_prereqs?(char, prereq, cl)
    end

    def self.choice_grants_feat?(block)
      block.is_a?(Hash) && block['from_feats'].is_a?(Hash)
    end

    # The option hash for a resolved label, or nil if the block has no enumerated options.
    def self.choice_option_def(block, label)
      return nil unless block.is_a?(Hash)

      options = block['options']
      return nil unless options.is_a?(Hash)

      key = options.keys.find { |o| o.to_s.casecmp?(label.to_s) }
      return nil unless key && options[key].is_a?(Hash)

      options[key]
    end

    # The grants payload for a resolved choice. choice_name is the pending choice's key,
    # needed by pool filters and grants that read an earlier pick in the same sequence.
    def self.choice_grants(char, block, label, choice_name = nil)
      option = choice_option_def(block, label)
      return option['grants'] if option

      return { 'skill' => [ label ] } if block.is_a?(Hash) && block.key?('from_lores')

      if block.is_a?(Hash) && block['from_spells'].is_a?(Hash)
        focus_type = block['from_spells']['focus_type']

        return { 'magic_stats' => { 'focus_spell' => { focus_type.to_s => [ label ] } } } if focus_type.present?

        return adapted_spell_grant(char, block, label, choice_name) if block['adapted']
      end

      return choice_dynamic_grants(char, block['from'], label, block) if block.is_a?(Hash) && block['from']

      nil
    end

    ARMOR_LADDER = %w(light medium heavy)

    def self.auto_choice?(block)
      block.is_a?(Hash) && !block['auto'].to_s.empty?
    end

    def self.auto_choice_label(char, block, advancement = nil)
      return nil unless auto_choice?(block)

      case block['auto'].to_s.downcase
      when 'subclass_spell'
        found = archetype_subclass_spell(char, block['archetype'], block['tier'])

        found && found[1]
      when 'next_armor_category'
        next_armor_category(char, advancement)
      else
        Global.logger.error "Unknown feat_choice auto source '#{block['auto']}'."
        nil
      end
    end

    def self.effective_armor_prof(char, advancement = nil)
      profs = (char.combat && char.combat.armor_prof) ? char.combat.armor_prof.dup : {}

      advancement = char.pf2_advancement if advancement.nil? && char.advancing
      return profs unless advancement.is_a?(Hash)

      staged = [ advancement.dig('combat_stats', 'armor_prof') ]

      grants = advancement['grants']

      if grants.is_a?(Hash)
        grants.each_value do |payload|
          staged << payload.dig('combat_stats', 'armor_prof') if payload.is_a?(Hash)
        end
      end

      staged.compact.each { |added| profs = merge_combat_stats(profs, added) }

      profs
    end

    def self.next_armor_category(char, advancement = nil)
      profs = effective_armor_prof(char, advancement)

      found = ARMOR_LADDER.find { |category| prof_rank(profs[category]).to_i.zero? }

      found && found.capitalize
    end

    # Grants implied by a dynamically sourced choice.
    def self.choice_dynamic_grants(char, source, value, block = nil)
      case source.to_s.downcase
      when 'subclass_spell'
        found = archetype_subclass_spell(char, block.is_a?(Hash) ? block['archetype'] : nil, block.is_a?(Hash) ? block['tier'] : nil)
        return nil unless found

        { 'magic_stats' => { 'focus_pool' => 1, 'focus_spell' => { found[0] => [ found[1] ] } } }
      when 'deity_domains'
        # Choosing a domain grants that domain's initial spell as a focus spell.
        domain_info = Global.read_config('pf2e_magic', 'domains', value)
        return nil unless domain_info && domain_info['initial']

        focus_type_by_source = Global.read_config('pf2e_magic', 'focus_type_by_source') || {}
        focus_type = focus_type_by_source[char.pf2_base_info['charclass']] || 'devotion'

        { 'magic_stats' => { 'focus_spell' => { focus_type => [ domain_info['initial'] ] } } }
      when 'devotion_spells'
        { 'magic_stats' => { 'focus_spell' => { 'devotion' => [ value ] } } }
      when 'traditions', 'other_traditions'
        nil
      else
        nil
      end
    end

    THE_TRADITIONS = %w(arcane divine occult primal)

    def self.own_traditions(char)
      magic = char.magic
      return [] unless magic

      (magic.tradition || {}).reject { |k, _| k.to_s.strip.casecmp?('innate') }
        .values
        .map { |entry| Array(entry).first.to_s.downcase }
        .reject(&:empty?)
        .uniq
    end

    # Whether the character can cast at all through a spellcasting class -- the "ability to
    # cast spells / cantrips" prerequisite.
    def self.character_is_caster?(char)
      return true if own_traditions(char).any?

      !(char.magic&.innate_spells || {}).empty?
    end

    def self.resolve_tradition_spec(char, spec, choice_name = nil)
      case spec
      when nil
        nil
      when Array
        spec.map { |t| t.to_s.downcase }
      when Hash
        src = spec['from_feat_choice']
        return [] unless src

        trad = adapted_source_tradition(char, src)
        trad ? [ trad.to_s.downcase ] : []
      else
        case spec.to_s.downcase
        when 'own'
          own_traditions(char)
        when 'not_own'
          THE_TRADITIONS - own_traditions(char)
        when 'from_prior_choice'
          prior = choice_labels_for(char, choice_name).last.to_s.downcase
          prior.empty? ? [] : [ prior ]
        else
          [ spec.to_s.downcase ]
        end
      end
    end

    def self.adapted_source_tradition(char, source)
      spells = char.magic&.adapted_spells || {}

      entry = spells.values.find { |e| e.is_a?(Hash) && e['source'].to_s.casecmp?(source.to_s) }
      entry && entry['tradition']
    end

    def self.adapted_spell_grant(char, block, spell_name, choice_name = nil)
      return nil unless AresMUSH.const_defined?("Pf2emagic")

      spell = Pf2emagic.get_spell_details(spell_name)
      return nil if spell.is_a?(String)

      name, details = spell
      base_level = details['base_level'].to_s.downcase == 'cantrip' ? 0 : details['base_level'].to_i
      level_key = base_level.zero? ? 'cantrip' : base_level.to_s

      spec = block['from_spells'].is_a?(Hash) ? block['from_spells']['tradition'] : nil
      allowed = Array(resolve_tradition_spec(char, spec, choice_name))
      spell_trads = Array(details['tradition']).compact.map { |t| t.to_s.downcase }
      tradition = (allowed & spell_trads).first || allowed.first || spell_trads.first

      entry = {
        'name'       => name,
        'tradition'  => tradition,
        'base_level' => base_level,
        'source'     => choice_name
      }
      # Adaptive Adept: a 1st-rank (or higher) pick is fixed at its base rank. A cantrip
      # heightens by the normal rules regardless, so the flag only bites above rank 0.
      entry['no_heighten'] = true if block['no_heighten'] && base_level.positive?

      stats = { 'adapted_spell' => entry }

      if Pf2emagic.get_caster_type(char.pf2_base_info['charclass']) == 'spontaneous'
        stats['addrepertoire'] = { level_key => [ name ] }
      end

      { 'magic_stats' => stats }
    end

    # Entries owed on advancing into a level, as [ level, payload ].
    def self.at_level_due(at_level, level)
      return [] unless at_level.is_a?(Hash)

      # YAML gives these integer keys; Redis hands them back as strings. Compare numerically.
      at_level.keys
              .select { |k| k.to_s.to_i == level.to_i }
              .map { |k| [ k.to_s.to_i, at_level[k] ] }
    end

    # Entries owed on acquiring something at a level, as [ level, payload ], lowest first.
    def self.at_level_caught_up(at_level, level)
      return [] unless at_level.is_a?(Hash)

      at_level.keys
              .select { |k| k.to_s.to_i <= level.to_i }
              .sort_by { |k| k.to_s.to_i }
              .map { |k| [ k.to_s.to_i, at_level[k] ] }
    end

    # The at_level map on a feat itself, beside its grants.
    def self.feat_at_level(details)
      details.is_a?(Hash) ? details['at_level'] : nil
    end

    def self.choice_option_at_level(block, label)
      option = choice_option_def(block, label)
      return option['at_level'] if option && option['at_level']

      block.is_a?(Hash) ? block['at_level'] : nil
    end

    CHOSEN_LABEL_SENTINEL = 'chosen'

    def self.substitute_choice_label(payload, label)
      case payload
      when Hash
        payload.each_with_object({}) { |(k, v), h| h[k] = substitute_choice_label(v, label) }
      when Array
        payload.map { |v| substitute_choice_label(v, label) }
      when String
        payload.casecmp?(CHOSEN_LABEL_SENTINEL) ? label.to_s : payload
      else
        payload
      end
    end

    # The single payload a resolved choice owes on advancing into a level, or nil.
    def self.choice_at_level(block, label, level)
      due = at_level_due(choice_option_at_level(block, label), level)

      due.empty? ? nil : substitute_choice_label(due.first[1], label)
    end

    # Level clauses on held feats that come due at the given level, as [ feat, level, payload ].
    def self.deferred_feat_grants(char, level)
      feats = Global.read_config('pf2e_feats') || {}

      char.pf2_feats.values.flatten.uniq.flat_map do |name|
        key = feats.keys.find { |k| k.to_s.casecmp?(name.to_s) }
        next [] unless key

        at_level_due(feat_at_level(feats[key]), level).map { |lvl, payload| [ name, lvl, payload ] }
      end
    end

    # Level clauses a feat owes immediately on acquisition, as [ level, payload ].
    def self.feat_at_level_catch_up(details, level)
      at_level_caught_up(feat_at_level(details), level)
    end

    CHOICE_INLINE_LIMIT = 20

    # A choice block declared on a feat, which is named after that feat.
    def self.feat_choice_block_for(choice_name)
      details = get_feat_details(choice_name.to_s)
      return nil if details.is_a?(String)

      feat_choice_def(details[1])
    end

    # A choice block declared on a class, subclass, or specialty entry, named by the key it
    # appears under there.
    def self.class_choice_block_for(char, choice_name)
      blocks = class_choice_blocks(char)
      match = blocks.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }

      match ? blocks[match] : nil
    end

    def self.find_choice_block(char, choice_name, source = nil)
      feat_block = source.to_s != 'charclass' && feat_choice_block_for(choice_name)

      if feat_block
        return advance_choice_steps(feat_block, feat_choice_step(char, choice_name))
      end

      return nil if source.to_s == 'feat'

      class_choice_block_for(char, choice_name)
    end

    def self.advance_choice_steps(block, steps)
      steps.to_i.times do
        nxt = block.is_a?(Hash) && block['then_choose']
        break unless nxt.is_a?(Hash)

        block = nxt
      end

      block
    end

    def self.feat_choice_step(char, choice_name)
      choices = (char.pf2_to_assign || {})['feat choice']
      return 0 unless choices.is_a?(Hash)

      key = choices.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      Array(key && choices[key]).count { |slot| slot.to_s.strip.downcase != 'open' }
    end

    def self.choice_source_entries(char)
      entries = []

      charclass = char.pf2_base_info['charclass']

      unless charclass.blank?
        class_info = Global.read_config('pf2e_class', charclass) || {}

        entries << [ charclass, class_info ]
        entries << [ charclass, class_info['chargen'] ]
        entries.concat(class_info['advance'].values.map { |v| [ charclass, v ] }) if class_info['advance'].is_a?(Hash)

        specialize = char.pf2_base_info['specialize']

        unless specialize.blank?
          spec_info = Global.read_config('pf2e_specialty', charclass, specialize) || {}

          if spec_info.is_a?(Hash)
            entries << [ charclass, spec_info ]
            entries << [ charclass, spec_info['chargen'] ]
            entries.concat(spec_info['advance'].values.map { |v| [ charclass, v ] }) if spec_info['advance'].is_a?(Hash)

            specialize_info = char.pf2_base_info['specialize_info']

            unless specialize_info.blank?
              option_info = spec_info.dig('choose', 'options', specialize_info)

              if option_info.is_a?(Hash)
                entries << [ charclass, option_info ]
                entries << [ charclass, option_info['chargen'] ]
                entries.concat(option_info['advance'].values.map { |v| [ charclass, v ] }) if option_info['advance'].is_a?(Hash)
              end
            end
          end
        end
      end

      held_archetypes(char).each do |archetype|
        entries << [ archetype, Global.read_config('pf2e_archetype', archetype) ]

        mirrored = Global.read_config('pf2e_class', mirrored_class(archetype))
        entries << [ archetype, mirrored ] if mirrored
      end

      entries.reject { |_source, info| info.nil? }
    end

    def self.held_archetypes(char)
      info = char.pf2_archetypeinfo || {}

      (1..4).map { |i| info["archetype#{i}"] }.compact.map(&:to_s).reject(&:empty?).uniq
    end

    # The class an archetype draws its features from, where it draws them from one at all.
    def self.mirrored_class(archetype)
      archetype.to_s.sub(/\s*Archetype\z/i, '')
    end

    def self.class_choice_blocks(char)
      choice_source_entries(char).each_with_object({}) do |(_source, info), hash|
        hash.merge!(level_feat_choices(info))
      end
    end

    def self.choice_caster_source(char, choice_name)
      entry = choice_source_entries(char).find do |_source, info|
        level_feat_choices(info).keys.any? { |k| k.to_s.casecmp?(choice_name.to_s) }
      end

      entry ? entry[0] : char.pf2_base_info['charclass']
    end

    def self.granted_choice_names(info)
      return [] unless info.is_a?(Hash)

      names = level_feat_choices(info).keys
      names.concat(Array(info['grant_choice']).compact.map { |n| n.to_s })

      names.uniq
    end

    def self.pending_feat_choices(char)
      to_assign = char.pf2_to_assign || {}

      stored = to_assign['feat choice']
      return {} unless stored.is_a?(Hash)

      stored.each_with_object({}) { |(name, slots), pending| pending[name] = Array(slots) }
    end

    def self.open_feat_choice(to_assign, choice_name, count = 1)
      choices = to_assign['feat choice'] || {}
      slots = Array(choices[choice_name])

      count.times { slots << 'open' }

      choices[choice_name] = slots
      to_assign['feat choice'] = choices

      to_assign
    end

    def self.fill_feat_choice(to_assign, choice_name, value)
      choices = to_assign['feat choice'] || {}
      key = choices.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      return false unless key

      slots = Array(choices[key])
      index = slots.index('open')
      return false unless index

      slots[index] = value
      choices[key] = slots
      to_assign['feat choice'] = choices

      # A narrowing only applies while the slot it was opened for is still open.
      clear_choice_filter(to_assign, key) unless slots.include?('open')

      true
    end

    def self.store_choice_filter(to_assign, choice_name, filter)
      return to_assign unless filter.is_a?(Hash) && !filter.empty?

      filters = to_assign['feat choice filter'] || {}
      filters[choice_name] = filter
      to_assign['feat choice filter'] = filters

      to_assign
    end

    def self.clear_choice_filter(to_assign, choice_name)
      filters = to_assign['feat choice filter']
      return to_assign unless filters.is_a?(Hash)

      key = filters.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      filters.delete(key) if key

      to_assign['feat choice filter'] = filters

      to_assign
    end

    def self.stored_choice_filter(char, choice_name)
      filters = (char.pf2_to_assign || {})['feat choice filter']
      return nil unless filters.is_a?(Hash)

      key = filters.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }
      key && filters[key]
    end

    def self.narrow_choice_options(char, choice_name, options)
      filter = stored_choice_filter(char, choice_name)
      return options unless filter.is_a?(Hash)

      allowed = if filter['options']
        Array(filter['options']).compact
      elsif filter['from']
        choice_dynamic_options(char, filter['from'])
      elsif filter['same_as']
        choice_labels_for(char, filter['same_as'])
      end

      return options unless allowed

      options.select { |o| allowed.any? { |a| a.to_s.casecmp?(o.to_s) } }
    end

    def self.validate_feat_choice(char, choice_name, source = nil)
      pending = pending_feat_choices(char)
      key = pending.keys.find { |k| k.to_s.casecmp?(choice_name.to_s) }

      return t('pf2e.no_such_choice', :choice => choice_name) unless key
      return t('pf2e.choice_already_resolved', :choice => key) unless Array(pending[key]).include?('open')

      block = find_choice_block(char, key, source)

      unless block
        if source.present? && find_choice_block(char, key)
          actual = feat_choice_block_for(key) ? 'feat' : 'charclass'

          return t('pf2e.choice_wrong_source',
            :choice => key,
            :source => source,
            :actual => actual,
            :cmd => choice_option_cmd(char))
        end

        return t('pf2e.choice_not_configured', :choice => key)
      end

      [ key, block ]
    end

    # The command that lists a choice's options in full, which differs by mode.
    def self.choice_info_cmd(char)
      char.advancing ? 'advance/info' : 'cg/info'
    end

    # The command that resolves a choice, which differs by mode the same way.
    def self.choice_option_cmd(char)
      char.advancing ? 'advance/option' : 'cg/option'
    end

    # What the player may pick, as a message. Large pools are not dumped inline; they are
    # left to the info command, which paginates.
    def self.describe_choice_options(char, choice_name, block)
      options = choice_options(char, choice_name, block)

      return t('pf2e.choice_no_options', :choice => choice_name) if options.empty?

      if options.size > CHOICE_INLINE_LIMIT
        return t('pf2e.choice_too_many_options',
          :choice => choice_name,
          :count => options.size,
          :cmd => choice_info_cmd(char))
      end

      t('pf2e.choice_options', :choice => choice_name, :options => options.join(", "))
    end

    def self.describe_bad_choice_option(char, choice_name, block)
      options = choice_options(char, choice_name, block)

      return t('pf2e.choice_no_options', :choice => choice_name) if options.empty?

      if options.size > CHOICE_INLINE_LIMIT
        return t('pf2e.choice_bad_option_many',
          :choice => choice_name,
          :count => options.size,
          :cmd => choice_info_cmd(char))
      end

      t('pf2e.choice_bad_option', :choice => choice_name, :options => options.join(", "))
    end

    # Feats matching a from_feats filter that the character does not already have.
    def self.choice_feat_pool(char, filter)
      feats = Global.read_config('pf2e_feats') || {}

      # Tallied once rather than rebuilt inside the loop by has_feat?. A repeatable feat
      # stays selectable until it is actually maxed out.
      tally = feat_tally(char)

      list = feats.keys.select do |name|
        next false if feat_repeat_block(char, name, feats[name], tally[name.to_s.upcase])

        choice_feat_match?(char, name, feats[name], filter)
      end

      list.sort
    end

    def self.choice_feat_match?(char, feat_name, details, filter)
      return false unless details.is_a?(Hash)
      return false unless filter.is_a?(Hash)

      feat_types = Array(details['feat_type']).compact.map { |f| f.to_s.downcase }
      return false if feat_types.empty?

      # No double-dipping on base class / dedication, per Paizo RAW.
      return false unless dedication_allowed?(char, details)

      if filter['feat_type']
        wanted = Array(filter['feat_type']).compact.map { |f| f.to_s.downcase }
        return false unless wanted.any? { |w| feat_types.include?(w) }
      end

      cap = filter['max_level'] ? choice_level_cap(char, filter['max_level']) : nil

      if cap
        prereq_level = details.dig('prereq', 'level')
        return false if prereq_level.nil?
        return false if prereq_level.to_i > cap
      end

      if filter['traits']
        wanted = Array(filter['traits']).compact.map { |t| t.to_s.downcase }
        traits = Array(details['traits']).compact.map { |t| t.to_s.downcase }
        return false unless wanted.any? { |w| traits.include?(w) }
      end

      # Narrows a lineage-feat pool to the lineage matching the character's own heritage
      if filter['trait_matches_heritage']
        heritage = char.pf2_base_info['heritage'].to_s.downcase
        traits = Array(details['traits']).compact.map { |t| t.to_s.downcase }
        return false unless traits.include?(heritage)
      end

      if filter['assoc_charclass']
        wanted = Array(filter['assoc_charclass']).compact.map { |c| c.to_s.downcase }
        assoc = Array(details['assoc_charclass']).compact.map { |c| c.to_s.downcase }
        return false unless wanted.any? { |w| assoc.include?(w) }
      end

      if filter['own_charclass']
        base_class = char.pf2_base_info['charclass'].to_s
        assoc = Array(details['assoc_charclass']).compact
        return false unless assoc.any? { |c| c.to_s.casecmp?(base_class) }
      end

      # Restricts the pool to feats that are open only because of an adopted ancestry
      if filter['adopted_only']
        assoc = Array(details['assoc_ancestry'])

        opened = adopted_ancestries(char).any? do |a|
          assoc.include?(a) && adopted_feat?(a, feat_name)
        end

        return false unless opened
      end

      # Narrows to the skill feats hanging off one named skill
      if filter['assoc_skill']
        wanted = Array(filter['assoc_skill']).compact.map { |s| s.to_s.downcase }
        skills = Array(details['assoc_skill']).compact.map { |s| s.to_s.downcase }

        return false unless wanted.any? { |w| skills.include?(w) }
      end

      if filter['skill_key_abil']
        wanted = Array(filter['skill_key_abil']).compact.map { |a| a.to_s.downcase }
        skills = Global.read_config('pf2e_skills') || {}
        assoc_skills = Array(details['assoc_skill']).compact

        return false if assoc_skills.empty?

        matches = assoc_skills.any? do |skill_name|
          key = skills.keys.find { |s| s.to_s.casecmp?(skill_name.to_s) }
          key && wanted.include?(skills[key]['key_abil'].to_s.downcase)
        end

        return false unless matches
      end

      return true if filter['qualify'] == false

      can_take_feat_details?(char, feat_name, details, cap, filter['ignore_charclass'])
    end

    def self.choice_level_cap(char, value)
      return effective_char_level(char) / 2 if value.to_s == 'half_level'

      value.to_i
    end

    def self.effective_char_level(char)
      char.advancing ? char.pf2_level + 1 : char.pf2_level
    end

    def self.choice_skill_pool(char, filter)
      filter = {} unless filter.is_a?(Hash)

      min_rank = prof_rank(filter['min_prof'] || 'trained') || 1

      list = char.skills.select do |skill|
        rank = prof_rank(skill.prof_level)
        rank && rank >= min_rank
      end.map { |skill| skill.name }

      if filter['key_abil']
        wanted = Array(filter['key_abil']).compact.map { |a| a.to_s.downcase }
        skills = Global.read_config('pf2e_skills') || {}

        list = list.select do |name|
          key = skills.keys.find { |s| s.to_s.casecmp?(name.to_s) }
          key && wanted.include?(skills[key]['key_abil'].to_s.downcase)
        end
      end

      list.sort
    end

    def self.choice_spell_pool(char, filter, choice_name = nil)
      filter = {} unless filter.is_a?(Hash)

      spells = Global.read_config('pf2e_spells') || {}

      wanted = Array(filter['traits']).compact.map { |t| t.to_s.downcase }

      ranks = if filter.key?('base_level')
        Array(filter['base_level']).map { |r| r.to_s.downcase == 'cantrip' ? 0 : r.to_i }
      end

      allowed_trads = filter.key?('tradition') ? resolve_tradition_spec(char, filter['tradition'], choice_name) : nil

      list = spells.keys.select do |name|
        details = spells[name]
        next false unless details.is_a?(Hash)

        if ranks
          spell_rank = details['base_level'].to_s.downcase == 'cantrip' ? 0 : details['base_level'].to_i
          next false unless ranks.include?(spell_rank)
        end

        traits = Array(details['traits']).compact.map { |t| t.to_s.downcase }
        next false unless wanted.all? { |w| traits.include?(w) }

        if allowed_trads
          spell_trads = Array(details['tradition']).compact.map { |t| t.to_s.downcase }
          next false unless allowed_trads.any? { |t| spell_trads.include?(t) }
        end

        true
      end

      held = Array(char.magic&.focus_spells&.dig(filter['focus_type'].to_s)).map { |s| s.to_s.downcase }

      list.reject { |name| held.include?(name.to_s.downcase) }.sort
    end

    def self.choice_lore_pool(char, filter)
      filter = {} unless filter.is_a?(Hash)

      skills = Global.read_config('pf2e_skills') || {}

      list = skills.keys.select do |name|
        details = skills[name]

        lore_skill?(name, details) && !(details.is_a?(Hash) && details['hidden'])
      end

      if filter['group']
        wanted = Array(filter['group']).compact.map { |g| g.to_s.downcase }

        list = list.select do |name|
          groups = Array(skills[name]['lore_groups']).compact.map { |g| g.to_s.downcase }

          wanted.any? { |w| groups.include?(w) }
        end
      end

      trained = char.skills.reject { |s| s.prof_level.to_s.casecmp?('untrained') }.map { |s| s.name.to_s.downcase }

      list.reject { |name| trained.include?(name.to_s.downcase) }.sort
    end

    # Whether a skill entry is a Lore subcategory rather than one of the sixteen base skills.
    def self.lore_skill?(name, details = nil)
      return true if details.is_a?(Hash) && !Array(details['lore_groups']).empty?

      name.to_s.strip =~ /\bLore\z/i ? true : false
    end

    # Weapons matching a from_weapons filter, drawn from pf2e_weapons.yml.
    def self.choice_weapon_pool(char, filter)
      filter = {} unless filter.is_a?(Hash)

      weapons = Global.read_config('pf2e_weapons') || {}

      list = weapons.keys.select do |name|
        details = weapons[name]
        next false unless details.is_a?(Hash)

        if filter['category']
          wanted = Array(filter['category']).compact.map { |c| c.to_s.downcase }
          next false unless wanted.include?(details['category'].to_s.downcase)
        end

        if filter['group']
          wanted = Array(filter['group']).compact.map { |g| g.to_s.downcase }
          next false unless wanted.include?(details['group'].to_s.downcase)
        end

        true
      end

      list.sort
    end

    # Weapon names the character has chosen through any feat whose choice draws from the
    # weapon list, such as Weapon Proficiency.
    def self.chosen_weapons(char)
      recorded_choices(char).filter_map do |name, label, _level|
        block = find_choice_block(char, name)
        next unless block.is_a?(Hash) && block['from_weapons']

        label
      end.uniq
    end

    # Ancestries the character has taken on through any feat whose choice draws from the
    # ancestry list, such as Adopted Ancestry.
    def self.adopted_ancestries(char)
      recorded = recorded_choices(char)
      legacy = char.pf2_base_info['adopted ancestry']

      return [] if recorded.empty? && legacy.blank?

      feats = Global.read_config('pf2e_feats') || {}

      adopted = recorded.filter_map do |name, label, _level|
        block = feat_choice_def(feats[name])
        next unless block.is_a?(Hash) && block['from'].to_s.casecmp?('ancestries')

        label
      end

      # Kept for sheets that were set directly rather than through the feat.
      adopted << legacy if legacy.present?

      adopted.uniq
    end

    # Whether an adopted ancestry opens this particular feat.
    def self.adopted_feat?(ancestry, feat_name)
      list = Global.read_config('pf2e_ancestry', ancestry, 'adopted_feats')

      Array(list).any? { |f| f.to_s.casecmp?(feat_name.to_s) }
    end

    # Whether a feat's choice opens on this taking.
    def self.feat_choice_opens_at?(block, instance)
      return false unless block.is_a?(Hash)

      from = block['from_instance']
      return true unless from

      instance.to_i >= from.to_i
    end

    # The subclass a character holds for one archetype, and the initial focus spell it grants.
    def self.archetype_subclass_spell(char, archetype, tier = nil)
      if archetype.blank?
        cls = char.pf2_base_info['charclass']
        subclass = char.pf2_base_info['specialize']
      else
        info = char.pf2_archetypeinfo || {}
        slot = (1..4).find { |i| info["archetype#{i}"].to_s.casecmp?(archetype.to_s) }
        return nil unless slot

        cls = mirrored_class(archetype)
        subclass = info["archetype_specialty#{slot}"]
      end

      return nil if cls.blank? || subclass.blank?

      spec = Global.read_config('pf2e_specialty', cls.to_s, subclass)
      return nil unless spec.is_a?(Hash)

      focus = if tier.to_s.casecmp?('advanced')
        spec['advanced_focus_spell']
      else
        spec.dig('chargen', 'magic_stats', 'focus_spell')
      end

      return nil unless focus.is_a?(Hash)

      focus_type, spells = focus.first
      spell = Array(spells).first

      spell.blank? ? nil : [ focus_type, spell ]
    end

    def self.choice_dynamic_options(char, source, block = nil)
      case source.to_s.downcase
      when 'subclass_spell'
        found = archetype_subclass_spell(char, block.is_a?(Hash) ? block['archetype'] : nil, block.is_a?(Hash) ? block['tier'] : nil)

        found ? [ found[1] ] : []
      when 'deity_domains'
        deity = char.pf2_faith['deity']
        return [] if deity.blank?

        deity_info = (Global.read_config('pf2e_deities') || {})[deity]
        return [] unless deity_info

        Array(deity_info['domains']).compact.sort
      when 'devotion_spells'
        options = [ 'Shields of the Spirit' ]

        deity = char.pf2_faith['deity']

        if deity.blank? && char.advancing
          pending = (char.pf2_to_assign || {})['archetype deity']
          deity = pending unless pending.blank? || pending.to_s.casecmp?('open')
        end

        fonts = deity.blank? ? [] : Array(Global.read_config('pf2e_deities', deity, 'magic_stats', 'divine_font'))

        options << 'Lay on Hands' if fonts.any? { |f| f.to_s.casecmp?('heal') }
        options << 'Touch of the Void' if fonts.any? { |f| f.to_s.casecmp?('harm') }

        options.sort
      when 'lineage planes'
        # Nephilim Lore.
        case char.pf2_base_info['heritage'].to_s
        when /\AAesa\z/i
          [ 'City of Bells Lore', 'Elysian Fields Lore', 'Shining Peak Lore' ]
        when /\ANiasa\z/i
          [ 'Iron Hells Lore', 'The Abyss Lore', 'The Null Lore' ]
        else
          []
        end
      when 'ancestries'
        # Adopted Ancestry. Their own is excluded, since the feat is about taking on
        # another one, and duplicate exclusion handles any they have already adopted.
        own = char.pf2_base_info['ancestry'].to_s

        (Global.read_config('pf2e_ancestry') || {}).keys
          .reject { |a| a.to_s.casecmp?(own) }
          .sort
      when 'traditions'
        THE_TRADITIONS.map(&:capitalize)
      when 'other_traditions'
        # Adapted Cantrip: the magical traditions the character does not already cast as.
        own = own_traditions(char)

        THE_TRADITIONS.reject { |t| own.include?(t) }.map(&:capitalize).sort
      else
        Global.logger.error "Unknown feat_choice source '#{source}'."
        []
      end
    end

    DEFERRED_CHOICE_SOURCES = [ 'skill choice' ]

    def self.deferred_choice_source?(source)
      DEFERRED_CHOICE_SOURCES.include?(source.to_s.downcase)
    end

    def self.granted_feat_entry(entry)
      return [ entry.to_s, nil, nil, nil ] unless entry.is_a?(Hash)

      name = entry['name'].to_s
      return nil if name.empty?

      [ name, entry['choice'], entry['choice_from'], entry['choice_filter'] ]
    end

    def self.granted_choice_label(char, source)
      case source.to_s.downcase
      when 'skill choice'
        choice = (char.pf2_to_assign || {})['bg skill choice']
        return nil unless choice.is_a?(Hash)

        selected = choice['selected']
        return nil if selected.blank? || selected.to_s == 'open'

        selected
      when 'divine skill'
        deity_config(char)&.fetch('divine_skill', nil)
      when 'related lore'
        deity_config(char)&.fetch('related_lore', nil)
      when 'divine ability'
        deity_config(char)&.fetch('divine_ability', nil)
      else
        Global.logger.error "Unknown choice_from source '#{source}'."
        nil
      end
    end

    def self.config_skills(char, source)
      return [] unless source.is_a?(Hash)

      Array(source['skills']).filter_map do |entry|
        next entry unless entry.is_a?(Hash)

        label = granted_choice_label(char, entry['from'])

        if label.blank?
          Global.logger.error "Config skill 'from: #{entry['from']}' resolved to nothing for #{char.name}."
          next nil
        end

        label
      end
    end

    def self.config_abl_boosts(char, source)
      return [] unless source.is_a?(Hash)

      Array(source['abl_boosts']).filter_map do |entry|
        next entry unless entry.is_a?(Hash)

        label = granted_choice_label(char, entry['from'])

        if label.blank?
          Global.logger.error "Config boost 'from: #{entry['from']}' resolved to nothing for #{char.name}."
          next nil
        end

        options = Array(label)

        options.size > 1 ? options : options.first
      end
    end

    # The character's deity entry, or nil when they have no deity set.
    def self.deity_config(char)
      deity = (char.pf2_faith || {})['deity']
      return nil if deity.blank?

      Global.read_config('pf2e_deities', deity)
    end

    def self.feat_bucket(details)
      Array(details['feat_type']).first.to_s.downcase
    end

    def self.add_granted_feat(char, fname, details, charclass, client)
      feats = char.pf2_feats
      bucket = feat_bucket(details)

      list = feats[bucket] || []
      list << fname
      feats[bucket] = list

      char.update(pf2_feats: feats)
      Pf2e::Ledger.sync!(char, { 'feats' => feats }, :source_type => 'class_feature', :source_ref => fname, :effective_level => char.pf2_level)

      msgs = []
      msgs.concat(do_feat_grants(char, details['grants'], charclass, client)) if details['grants']
      msgs.concat(do_feat_magic_stats(char, details, charclass, client))
      apply_init_magic_feat(char, fname, details, client)

      msgs
    end

    def self.resolve_granted_choice(char, fname, details, label, client, filter = nil)
      block = feat_choice_def(details)
      return [] unless block
      return [] unless feat_choice_opens_at?(block, feat_taken_count(char, fname))

      to_assign = char.pf2_to_assign
      open_feat_choice(to_assign, fname)

      store_choice_filter(to_assign, fname, filter)
      char.update(pf2_to_assign: to_assign)

      option = label.blank? ? nil : match_choice_option(char, fname, block, label)

      unless option
        if label.present?
          Global.logger.error "Granted feat '#{fname}' names choice '#{label}', which is not an available option for #{char.name}."
        end

        return [ t('pf2e.choice_opened',
          :choice => fname,
          :summary => choice_summary(block),
          :cmd => choice_info_cmd(char)) ]
      end

      msgs = apply_feat_choice(char, fname, block, option, client)
      msgs << t('pf2e.choice_granted', :choice => fname, :value => option)

      msgs
    end

    def self.apply_feat_choice(char, choice_name, block, value, client)
      msgs = []

      if choice_grants_feat?(block)
        feat = get_feat_details(value)
        return [ t('pf2e.bad_feat_name', :name => value) ] if feat.is_a?(String)

        fname = feat[0]
        fdetails = feat[1]
        charclass = fdetails['assoc_charclass'] || char.pf2_base_info['charclass']

        feats = char.pf2_feats
        ftype = Array(fdetails['feat_type']).first.to_s.downcase
        list = feats[ftype] || []
        list << fname
        feats[ftype] = list
        char.update(pf2_feats: feats)
        Pf2e::Ledger.sync!(char, { 'feats' => feats }, :source_type => 'class_feature', :source_ref => fname, :effective_level => char.pf2_level)

        msgs.concat(do_feat_grants(char, fdetails['grants'], charclass, client)) if fdetails['grants']
        msgs.concat(do_feat_magic_stats(char, fdetails, charclass, client))
        apply_init_magic_feat(char, fname, fdetails, client)

        nested = feat_choice_def(fdetails)
        nested = nil unless feat_choice_opens_at?(nested, feat_taken_count(char, fname))

        if nested
          nested_assign = char.pf2_to_assign
          open_feat_choice(nested_assign, fname)
          char.update(pf2_to_assign: nested_assign)

          msgs << t('pf2e.choice_opened', :choice => fname, :summary => choice_summary(nested), :cmd => choice_info_cmd(char))
        end

        value = fname
      else
        grants = choice_grants(char, block, value, choice_name)

        msgs.concat(do_feat_grants(char, grants, choice_caster_source(char, choice_name), client)) if grants
      end

      at_level_caught_up(choice_option_at_level(block, value), char.pf2_level).each do |lvl, payload|
        payload = substitute_choice_label(payload, value)

        msgs.concat(do_feat_grants(char, payload, char.pf2_base_info['charclass'], client))
        msgs << t('pf2e.choice_level_clause_applied', :choice => choice_name, :value => value, :level => lvl)
      end

      # Re-read, because do_feat_grants writes to_assign itself.
      to_assign = char.pf2_to_assign
      fill_feat_choice(to_assign, choice_name, value)
      char.update(pf2_to_assign: to_assign)

      record_choice(char, choice_name, value)

      msgs.concat(open_chained_choice(char, choice_name, block))

      msgs
    end

    # Advancement: staged into pf2_advancement, applied by do_advancement at advance/done.
    def self.stage_feat_choice(char, choice_name, block, value, client)
      msgs = []
      advancement = char.pf2_advancement
      to_assign = char.pf2_to_assign

      if choice_grants_feat?(block)
        feat = get_feat_details(value)
        return [ t('pf2e.bad_feat_name', :name => value) ] if feat.is_a?(String)

        fname = feat[0]
        fdetails = feat[1]

        feats_to_do = advancement['feats'] || {}
        ftype = Array(fdetails['feat_type']).first.to_s.downcase
        list = feats_to_do[ftype] || []
        list << fname
        feats_to_do[ftype] = list
        advancement['feats'] = feats_to_do

        if fdetails['grants']
          adv_grants = advancement['grants'] || {}
          adv_grants[fname] = fdetails['grants']
          advancement['grants'] = adv_grants
        end

        if fdetails['magic_stats']
          magic_options = stage_feat_magic_stats(char, fname, fdetails, to_assign, advancement)
          msgs.concat(magic_option_messages(magic_options))
        end

        # Staged rather than stored until advance/done, so the instance is one past the count.
        nested = feat_choice_def(fdetails)
        nested = nil unless feat_choice_opens_at?(nested, feat_taken_count(char, fname) + 1)

        if nested
          open_feat_choice(to_assign, fname)
          msgs << t('pf2e.choice_opened', :choice => fname, :summary => choice_summary(nested), :cmd => choice_info_cmd(char))
        end

        value = fname
      else
        grants = choice_grants(char, block, value, choice_name)

        if grants
          adv_grants = advancement['grants'] || {}
          adv_grants["#{choice_name} (#{value})"] = grants
          advancement['grants'] = adv_grants
        end
      end

      new_level = char.pf2_level + 1

      at_level_caught_up(choice_option_at_level(block, value), new_level).each do |lvl, payload|
        adv_grants = advancement['grants'] || {}
        adv_grants["#{choice_name} (#{value}, level #{lvl})"] = substitute_choice_label(payload, value)
        advancement['grants'] = adv_grants

        msgs << t('pf2e.choice_level_clause_applied', :choice => choice_name, :value => value, :level => lvl)
      end

      fill_feat_choice(to_assign, choice_name, value)

      choices = to_assign['feat_choices'] || {}
      existing = Array(choices[choice_name])
      existing << value
      choices[choice_name] = existing.uniq
      to_assign['feat_choices'] = choices

      msgs.concat(open_chained_choice(char, choice_name, block, to_assign))

      char.pf2_advancement = advancement
      char.pf2_to_assign = to_assign
      char.save

      msgs
    end

    def self.open_chained_choice(char, choice_name, block, to_assign = nil)
      nxt = block.is_a?(Hash) && block['then_choose']
      return [] unless nxt.is_a?(Hash)

      if to_assign
        open_feat_choice(to_assign, choice_name)
      else
        chained = char.pf2_to_assign
        open_feat_choice(chained, choice_name)
        char.update(pf2_to_assign: chained)
      end

      [ t('pf2e.choice_opened',
        :choice => choice_name,
        :summary => choice_summary(nxt),
        :cmd => choice_info_cmd(char)) ]
    end

  end
end
