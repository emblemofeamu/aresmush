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
      splist = magic.focus_spells[focus_type]

      spname = splist.select { |sp| sp.downcase.match? spell.downcase }

      return t('pf2emagic.no_match', :item => "spells") if spname.empty?
      return t('pf2e.multiple_matches', :element => 'spell') if spname.size > 1

      spname = spname.first

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

      caster_stats['focus type'] = focus_type
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

      splevel = level ? level : base

      # If specified, level must be at least the base level of the spell. Level is an integer here.
      return t('pf2emagic.invalid_level') if splevel < base

      splevel = 'cantrip' if splevel.zero?

      # Signature means that you can cast that spell at the level you know it at, at its base level, or any
      # level in between.
      cc_spells = magic.spells_today
      cc_spells_2day = cc_spells[charclass]
      return t('pf2emagic.no_available_slots') unless cc_spells_2day

      slots = cc_spells_2day[splevel]
      return t('pf2emagic.no_available_slots') unless slots

      signature_spells = magic.signature_spells[charclass]
      lvceil = signature_spells.invert[spell_name]

      available = lvceil && splevel.to_i.between?(base, lvceil) && (slots > 0)
      return t('pf2emagic.invalid_signature_level') unless available

      # Do the cast and return a caster hash.

      slots = slots - 1
      cc_spells_2day[splevel] = slots
      cc_spells[charclass] = cc_spells_2day
      magic.update(spells_today: cc_spells)

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
      return t('pf2emagic.not_prepared_at_level') unless available

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

      # Got a spell open at that level?
      cc_spells = magic.spells_today
      cc_spells_2day = cc_spells[charclass]
      return t('pf2emagic.no_available_slots') unless cc_spells_2day

      slots = cc_spells_2day[splevel]
      return t('pf2emagic.no_available_slots') unless slots

      available = (slots > 0)
      return t('pf2emagic.no_available_slots') unless available

      # Do the cast and return a caster hash. Cantrip recalculates level for auto-heightening.

      if splevel == 'cantrip'
        hlevel = get_auto_heighten_level(char).to_s
        splevel = splevel + "/#{hlevel}"
      else
        slots = slots - 1
        cc_spells_2day[splevel] = slots
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
      spell_type = switch ? switch : Pf2emagic.get_caster_type(charclass)

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
