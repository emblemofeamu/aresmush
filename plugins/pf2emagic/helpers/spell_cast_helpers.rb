module AresMUSH
  module Pf2emagic

    def self.get_focus_casting_stat(stype)
      Global.read_config('pf2e_magic', 'focus_casting_stat', stype)
    end

    def self.cast_focus_spell(char, charclass, focus_type, spell, target_list)
      magic = char.magic

      caster_stats = get_caster_stats(char, charclass, focus_type)
      return caster_stats if caster_stats.is_a? String

      # Do they have this spell in their list for that type?
      splist = magic.focus_spells[focus_type] || []
      cantrip_list = magic.focus_cantrips[focus_type] || []

      spname = splist.select { |sp| sp.downcase.match? spell.downcase }
      cantrip_match = cantrip_list.select { |sp| sp.downcase.match? spell.downcase }

      if spname.empty? && !cantrip_match.empty?
        return t('pf2e.multiple_matches', :element => 'spell') if cantrip_match.size > 1
        return t('pf2emagic.focus_cantrip_wrong_cmd', :spell => cantrip_match.first)
      end

      return t('pf2emagic.no_match', :item => "spells") if spname.empty?
      return t('pf2e.multiple_matches', :element => 'spell') if spname.size > 1

      spname = spname.first
      spdeets = Global.read_config('pf2e_spells', spname)
      base = spdeets ? spdeets['base_level'].to_i : 0
      hlevel = get_auto_heighten_level(char)
      splevel = [ base, hlevel ].max.to_s

      # Do they have any focus points left in their pool?
      fpool = magic.focus_pool
      pool = fpool['current']

      available = (pool > 0)
      return t('pf2emagic.not_enough_focus_points') unless available

      # Do the cast.

      pool = pool - 1
      fpool['current'] = pool
      magic.update(focus_pool: fpool)

      caster_stats['focus type'] = focus_type
      caster_stats['spell level'] = splevel
      caster_stats['spell type'] = 'focus'
      caster_stats['targets'] = target_list unless target_list.empty?
      caster_stats['spell name'] = spname

      caster_stats
    end

    def self.cast_focus_cantrip(char, charclass, focus_type, spell, target_list)
      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)
      magic = char.magic

      caster_stats = get_caster_stats(char, charclass, focus_type)
      return caster_stats if caster_stats.is_a? String

      splist = magic.focus_cantrips[focus_type]

      spname = splist.select { |sp| sp.downcase.match? spell.downcase }

      return t('pf2emagic.no_match', :item => "spells") if spname.empty?
      return t('pf2e.multiple_matches', :element => 'spell') if spname.size > 1

      spname = spname.first

      hlevel = get_auto_heighten_level(char).to_s
      splevel = "cantrip/#{hlevel}"

      caster_stats['focus type'] = focus_type
      caster_stats['spell level'] = splevel
      caster_stats['spell type'] = 'focus cantrip'
      caster_stats['targets'] = target_list unless target_list.empty?
      caster_stats['spell name'] = spname

      caster_stats
    end

    def self.cast_signature_spell(char, charclass, spell, level=nil, target_list)
      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)
      magic = char.magic

      caster_stats = get_caster_stats(char, charclass)
      return caster_stats if caster_stats.is_a? String

      # Find_spell will be either an array if it found a unique match or a string if it didn't.
      find_spell = get_spell_details(spell)

      return find_spell if find_spell.is_a? String

      spname = find_spell[0]
      spdeets = find_spell[1]

      base = spdeets['base_level'].to_i

      cc_spells = magic.spells_today
      cc_spells_2day = cc_spells[charclass]
      return t('pf2emagic.no_available_slots') unless cc_spells_2day

      auto_heighten = level.nil? && base > 0

      if auto_heighten
        castable_slot_levels = cc_spells_2day.keys
                                          .map { |lv| lv.to_s.downcase == 'cantrip' ? 0 : lv.to_i }
                                          .reject(&:zero?)

        return t('pf2emagic.no_available_slots') if castable_slot_levels.empty?

        highest_level = castable_slot_levels.max
        highest_key = if cc_spells_2day.key?(highest_level.to_s)
                        highest_level.to_s
                      elsif cc_spells_2day.key?(highest_level)
                        highest_level
                      end

        highest_slots = highest_key ? cc_spells_2day[highest_key].to_i : 0
        if highest_slots <= 0
          abs_level = highest_level.to_i.abs
          suffix =  case abs_level % 10
                    when 1 then 'st'
                    when 2 then 'nd'
                    when 3 then 'rd'
                    else 'th'
                   end
          level_label = "#{highest_level}#{suffix}-level"

          return t('pf2emagic.signature_autoheighten_no_slots', :level => level_label)
        end

        splevel = highest_level.to_s
      else
        splevel = level ? level.to_i : base

        # If specified, level must be at least the base level of the spell. Level is an integer here.
        return t('pf2emagic.invalid_level') if splevel < base

        splevel = splevel.zero? ? 'cantrip' : splevel.to_s
      end

      # Signature means that you can cast that spell at the level you know it at, at its base level, or any
      # level in between.
      castable_levels = cc_spells_2day.keys
                                 .map { |lv| lv.to_s.downcase == 'cantrip' ? 0 : lv.to_i }
      max_castable_level = castable_levels.max || 0

      signature_spells = magic.signature_spells[charclass] || {}

      known_signature_levels = signature_spells.select do |_sig_level, sig_spells|
        Array(sig_spells).include?(spname)
      end.keys

      is_signature_spell = !known_signature_levels.empty?

      available = if splevel == 'cantrip'
                    is_signature_spell && base.zero?
                  else
                    slot_key = if cc_spells_2day.key?(splevel)
                                 splevel
                               elsif cc_spells_2day.key?(splevel.to_i)
                                 splevel.to_i
                               end
                    slots = slot_key ? cc_spells_2day[slot_key] : nil
                    !slots.nil? && is_signature_spell && splevel.to_i.between?(base, max_castable_level) && (slots > 0)
                  end

      unless available
        focus_msg = focus_casting_mismatch_msg(char, charclass, spell)
        return focus_msg if focus_msg

        return t('pf2emagic.invalid_signature_level')
      end

      # Do the cast and return a caster hash.

      if splevel == 'cantrip'
        hlevel = get_auto_heighten_level(char).to_s
        splevel = "cantrip/#{hlevel}"
      else
        slot_key = if cc_spells_2day.key?(splevel)
                     splevel
                   elsif cc_spells_2day.key?(splevel.to_i)
                     splevel.to_i
                   end
        slots = slot_key ? cc_spells_2day[slot_key] : nil
        return t('pf2emagic.no_available_slots') if slots.nil?

        slots = slots - 1
        cc_spells_2day[slot_key] = slots
        cc_spells[charclass] = cc_spells_2day
        magic.update(spells_today: cc_spells)
      end

      caster_stats['spell level'] = splevel
      caster_stats['spell type'] = 'signature'
      caster_stats['targets'] = target_list unless target_list.empty?
      caster_stats['spell name'] = spname

      caster_stats
    end

    def self.cast_prepared_spell(char, charclass, spell, level=nil, target_list)
      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)
      magic = char.magic

      caster_stats = get_caster_stats(char, charclass)
      return caster_stats if caster_stats.is_a? String

      # Find_spell will be either an array if it found a unique match or a string if it didn't.
      find_spell = get_spell_details(spell)

      return find_spell if find_spell.is_a? String

      spname = find_spell[0]
      spdeets = find_spell[1]

      splevel = level ? level : spdeets['base_level']

      # Is that spell available at that level today?
      cc_spells = magic.spells_today
      cc_spells_2day = cc_spells[charclass]

      return t('pf2emagic.no_available_slots') unless cc_spells_2day

      splist = cc_spells_2day[splevel]
      return t('pf2emagic.no_available_slots') unless splist

      available = splist.include? spname
      unless available
        focus_msg = focus_casting_mismatch_msg(char, charclass, spell)
        return focus_msg if focus_msg

        return t('pf2emagic.not_prepared_at_level')
      end

      # Unless it's a cantrip, deduct the spell from today's prepared list and return a caster hash.

      if splevel == 'cantrip'
        # Oh, and, if it is a cantrip, don't forget to auto-heighten.
        hlevel = get_auto_heighten_level(char).to_s
        splevel = splevel + "/#{hlevel}"
      else
        splist = splist - [ spname ]
        cc_spells_2day[splevel] = splist
        cc_spells[charclass] = cc_spells_2day
        magic.update(spells_today: cc_spells)
      end

      caster_stats['spell level'] = splevel
      caster_stats['targets'] = target_list unless target_list.empty?
      caster_stats['spell name'] = spname

      caster_stats
    end

    def self.cast_spont_spell(char, charclass, spell, level=nil, target_list)
      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)
      magic = char.magic

      caster_stats = get_caster_stats(char, charclass)
      return caster_stats if caster_stats.is_a? String

      # Find_spell will be either an array if it found a unique match or a string if it didn't.
      find_spell = get_spell_details(spell)

      return find_spell if find_spell.is_a? String

      spname = find_spell[0]
      spdeets = find_spell[1]

      base = spdeets['base_level'].to_i

      splevel = level ? level.to_i : base

      # If specified, level must be at least the base level of the spell. Level is an integer here.
      return t('pf2emagic.invalid_level') if splevel < base
      
      splevel = splevel.zero? ? 'cantrip' : splevel.to_s

      # Spontaneous casters can cast a spell at a given level only if either:
      # 1) They know that spell at that specific level in their repertoire, or
      # 2) It is one of their signature spells and the requested level is valid.
      cc_spells = magic.spells_today
      cc_spells_2day = cc_spells[charclass]
      return t('pf2emagic.no_available_slots') unless cc_spells_2day

      castable_levels = cc_spells_2day.keys
                 .map { |lv| lv.to_s.downcase == 'cantrip' ? 0 : lv.to_i }
      max_castable_level = castable_levels.max || 0

      repertoire = magic.repertoire[charclass] || {}
      known_at_level = Array(repertoire[splevel]).include?(spname) ||
                       Array(repertoire[splevel.to_i]).include?(spname)

      signature_spells = magic.signature_spells[charclass] || {}
      known_signature_levels = signature_spells.select do |_sig_level, sig_spells|
        Array(sig_spells).include?(spname)
      end.keys

      is_signature_spell = !known_signature_levels.empty?

      valid_signature_level = if splevel == 'cantrip'
                                is_signature_spell && base.zero?
                              else
                                is_signature_spell && splevel.to_i.between?(base, max_castable_level)
                              end

      can_cast_at_level = known_at_level || valid_signature_level
      unless can_cast_at_level
        focus_msg = focus_casting_mismatch_msg(char, charclass, spell)
        return focus_msg if focus_msg

        return t('pf2emagic.not_in_list')
      end
      
      # Slots are not neccessary for cantrips.
      if splevel != 'cantrip'
        slot_key = if cc_spells_2day.key?(splevel)
                     splevel
                   elsif cc_spells_2day.key?(splevel.to_i)
                     splevel.to_i
                   end
        slots = slot_key ? cc_spells_2day[slot_key] : nil
        return t('pf2emagic.no_available_slots') unless slots

        available = (slots > 0)
        return t('pf2emagic.no_available_slots') unless available
      end

      # Do the cast and return a caster hash. Cantrip recalculates level for auto-heightening.

      if splevel == 'cantrip'
        hlevel = get_auto_heighten_level(char).to_s
        splevel = splevel + "/#{hlevel}"
      else
        slots = slots - 1
        cc_spells_2day[slot_key] = slots
        cc_spells[charclass] = cc_spells_2day
        magic.update(spells_today: cc_spells)
      end

      caster_stats['spell level'] = splevel
      caster_stats['targets'] = target_list unless target_list.empty?
      caster_stats['spell name'] = spname

      caster_stats
    end

    def self.cast_innate_spell(char, spell, target_list)
      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)
      magic = char.magic

      caster_stats = get_caster_stats(char, 'innate')
      return caster_stats if caster_stats.is_a? String

      # Find_spell will be either an array if it found a unique match or a string if it didn't.
      find_spell = get_spell_details(spell)

      return find_spell if find_spell.is_a? String

      spname = find_spell[0]

      # Is that spell name in their list of innate spells?

      innate_spells = magic.innate_spells
      splist = innate_spells.keys

      return t('pf2emagic.not_in_innate_list', :name => spname) unless splist.include? spname

      # Innate spells are structured a little differently and may overwrite base caster stats.
      spinfo = innate_spells[spname]

      level = spinfo['level'].to_s
      if level.downcase != 'cantrip' && level.to_i > 0
        cc_spells = magic.spells_today || {}
        innate_today = cc_spells['innate'] || {}
        level_uses = innate_today[level] || []

        use_index = level_uses.index(spname)
        return t('pf2emagic.no_available_slots') unless use_index

        level_uses.delete_at(use_index)
        innate_today[level] = level_uses
        cc_spells['innate'] = innate_today

        magic.update(spells_today: cc_spells)
      end

      caster_stats['tradition'] = spinfo['tradition']
      caster_stats['spell level'] = spinfo['level']
      caster_stats['spell type'] = 'innate'
      caster_stats['spell_abil'] = spinfo['cast_stat']
      caster_stats['modifier'] = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char,spinfo['cast_stat']))
      caster_stats['targets'] = target_list unless target_list.empty?
      caster_stats['spell name'] = spname

      caster_stats
    end

    def self.cast_spell(char, charclass, spell, target_list, level=nil, switch=nil)
      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)

      # Spell type is either specified in the switch or determined by character class.
      # Note: This function assumes and expects that charclass is passed as titlecase.
      spell_type = if switch
                     switch
                   elsif charclass.to_s.downcase == 'innate'
                     'innate'
                   else
                     Pf2emagic.get_caster_type(charclass)
                   end

      return t('pf2emagic.not_casting_class', :cc => charclass) unless spell_type

      # Spell_type can be 'focus', 'focusc', 'signature', 'prepared', 'spontaneous', or 'innate'. Anything
      # else should throw back an error.

      case spell_type
      when 'focusc'
        focus_type = Global.read_config('pf2e_magic', 'focus_type_by_class', charclass)

        msg = cast_focus_cantrip(char, charclass, focus_type, spell, target_list)
      when 'focus'
        # Focus spells need a special check for Oracle's curse lock.
        revelation_lock = charclass == 'Oracle' ? char.magic.revelation_locked : false

        return t('pf2emagic.revelation_locked') if revelation_lock

        focus_type = Global.read_config('pf2e_magic', 'focus_type_by_class', charclass)
        msg = cast_focus_spell(char, charclass, focus_type, spell, target_list)
      when 'innate'
        msg = cast_innate_spell(char, spell, target_list)
      when 'signature'
        msg = cast_signature_spell(char, charclass, spell, level, target_list)
      when 'prepared'
        msg = cast_prepared_spell(char, charclass, spell, level, target_list)
      when 'spontaneous'
        msg = cast_spont_spell(char, charclass, spell, level, target_list)
      else
        return t('pf2e.bad_switch', :cmd => 'cast')
      end

      msg
    end

    def self.focus_casting_mismatch_msg(char, charclass, spell)
      magic = char.magic
      focus_type = Global.read_config('pf2e_magic', 'focus_type_by_class', charclass)
      return nil unless focus_type

      focus_spells = magic.focus_spells[focus_type] || []
      focus_cantrips = magic.focus_cantrips[focus_type] || []

      spell_match = focus_spells.select { |sp| sp.downcase.match? spell.downcase }
      cantrip_match = focus_cantrips.select { |sp| sp.downcase.match? spell.downcase }

      return nil if spell_match.empty? && cantrip_match.empty?

      if (spell_match.size + cantrip_match.size) > 1
        return t('pf2e.multiple_matches', :element => 'spell')
      end

      return t('pf2emagic.focus_cantrip_cast_cmd', :spell => cantrip_match.first) unless cantrip_match.empty?

      t('pf2emagic.focus_spell_cast_cmd', :spell => spell_match.first)
    end

    def self.get_caster_stats(char, charclass, is_focus=false)
      magic = char.magic

      # Can this character cast as this class?

      cast_stats = magic.tradition[charclass]
      return t('pf2emagic.not_casting_class', :cc => charclass) unless cast_stats

      spell_abil = PF2Magic.get_spell_abil(char, charclass, is_focus)
      tradition = cast_stats[0]
      prof_level = cast_stats[1]
      modifier = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, spell_abil))

      # Return a hash of all the pieces of their casting stats for that class.

      {
        'tradition' => tradition,
        'prof_level' => prof_level,
        'spell_abil' => spell_abil,
        'modifier' => modifier
      }

    end

    def self.get_auto_heighten_level(char)
      # Some spells, such as cantrips, autoheighten to half the character's level.

      # Ruby's rounding functions act wacky when rounding a return that is a float.
      # So, we do the half calculation first, and then beat the rounding into submission with a crowbar.

      half_level = char.pf2_level / 2

      half_level.round(half: :up).clamp(1,10)
    end

  end
end
