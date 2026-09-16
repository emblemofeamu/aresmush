module AresMUSH
  module Pf2emagic

    # Records a spell as a signature spell.
    #
    # The one writer, because there were two and they disagreed: the level-up path stored
    # charclass => rank => [ spells ], which is what the cast path and the magic display both
    # read, and the prepared-caster path stored a flat list under the granting feat's name -
    # so a signature spell designated that way was never treated as one.
    def self.record_signature_spell(magic, charclass, rank, spell_name)
      signatures = magic.signature_spells || {}
      for_class = signatures[charclass] || {}

      for_class[rank.to_s] = (Array(for_class[rank.to_s]) + [ spell_name ]).uniq
      signatures[charclass] = for_class

      magic.update(:signature_spells => signatures)

      signatures
    end

    def self.prepare_spell(spell, char, castclass, level, use_arcane_evo=false)
      # All validations are done in the helper.

      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)

      magic = char.magic

      cc = castclass.capitalize
      return t('pf2emagic.not_casting_class', :cc => cc) unless Entries.casts_from?(magic, cc)

      prepared_cc_list = Global.read_config('pf2e_magic', 'prepared_casters')

      if !(prepared_cc_list.include? cc)
        if !use_arcane_evo
          return t('pf2emagic.does_not_prepare')
        end
      end

      # Can you prepare the level of spell you asked for?
      max_level = max_spell_level_available(char, cc)
      return t('pf2emagic.spell_exceeds_max_level') unless max_level

      return t('pf2emagic.spell_exceeds_max_level') if max_level.to_i < level.to_i

      # Get the spell info.
      spells = get_spell_details(spell)

      return spells if spells.is_a? String

      spell_name = spells[0]
      spell_details = spells[1]
      spell_level = spell_details['base_level']

      # Level can be passed as nil; default to the spell's base level.
      level = spell_level unless level
      level = level.to_s
      level = 'cantrip' if level.downcase == 'cantrip' || level.to_i.zero?

      is_cantrip_spell = spell_level.to_i.zero?
      is_cantrip_level = (level == 'cantrip')

      return t('pf2emagic.cant_prepare_cantrip_slot') if is_cantrip_spell && !is_cantrip_level
      return t('pf2emagic.cant_prepare_level') if !is_cantrip_spell && is_cantrip_level

      return t('pf2emagic.cant_prepare_level') if (spell_level.to_i > level.to_i)

      # An adapted spell (Adapted Cantrip and friends) may be prepared through this class
      # even though it is off the class's tradition list and not in any spellbook.
      is_adapted = Pf2emagic.adapted_spell?(char, cc, spell_name)

      needs_spellbook = spell_details['traits'].intersect?(['rare', 'uncommon', 'unique'])

      # Whether this class has to have the spell written down comes from its config - does it
      # get a spellbook at all - rather than from its name. Naming the Wizard here meant any
      # other class that acquires spells one at a time would silently have been given access to
      # its whole tradition list instead.
      if !is_adapted && (use_arcane_evo || needs_spellbook || Entries.enumerated?(cc))
        is_in_spellbook = spellbook_check(magic, cc, level, spell_name)
        return t('pf2emagic.not_in_spellbook') unless is_in_spellbook[0]
        make_signature = is_in_spellbook[1]
      end

      return_msg = {
        "level" => level,
        "name" => spell_name,
        "caster class" => cc,
        "is_signature" => make_signature
      }

      if make_signature
        # Recorded under the caster class at the spell's rank, which is the shape every reader
        # expects. This used to write a flat list keyed by the feat's own name, so the cast
        # path - which looks under the charclass - never found it and Arcane Evolution's
        # signature spell was silently not one.
        Pf2emagic.record_signature_spell(magic, cc, level, spell_name)

        return return_msg
      end

      spell_trad = spell_details['tradition']

      return t('pf2emagic.cant_prepare_trad', :cc => cc) unless is_adapted || spell_trad.include?(tradition[0].downcase)

      if use_arcane_evo
        repertoire = obj.repertoire
        repertoire['Arcane Evolution'] = [ spells ]
        magic.update(repertoire: repertoire)

        return return_msg
      end

      spell_list = magic.spells_prepared
      spell_list_for_class = spell_list[cc] || {}
      spell_list_for_level = spell_list_for_class[level] || []

      max_spells_per_day = max_spells_per_day(char, cc, level)

      return t('pf2emagic.no_available_slots') unless spell_list_for_level.size < max_spells_per_day

      unless prepared_set_fits?(char, cc, level, spell_list_for_level + [ spell_name ])
        return t('pf2emagic.no_unrestricted_slots')
      end

      # If all checks succeed, prepare the spell and return a hash.

      spell_list_for_level << spell_name

      spell_list_for_class[level] = spell_list_for_level.sort
      spell_list[cc] = spell_list_for_class
      magic.update(spells_prepared: spell_list)

      return_msg

    end

    def self.unprepare_spell(spell, char, castclass, level)
      # All validations are done in the helper.
      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)

      magic = char.magic
      cc = castclass.capitalize

      prepared_spells = magic.spells_prepared
      prep_spells_class = prepared_spells[cc]

      return t('pf2emagic.no_prepared_spells_class', :cc => cc.downcase) unless prep_spells_class

      prep_spells_level = prep_spells_class[level]
      return t('pf2emagic.no_prepared_spells_level') unless prep_spells_level

      # Because it is possible to prep the same spell multiple times, duplicates are accepted. Therefore,
      # we need to be able to delete just one at a time.

      # First, find the spell in question.

      spell_result = get_spell_details(spell)

      return spell_result if spell_result.is_a? String

      spname = spell_result[0]

      index = prep_spells_level.index(spname)
      return t('pf2emagic.not_prepared_at_level') unless index

      prep_spells_level.delete_at(index)

      prep_spells_class[level] = prep_spells_level
      prepared_spells[cc] = prep_spells_class
      magic.update(spells_prepared: prepared_spells)

      return nil
    end

    def self.spellbook_check(obj, castclass, level, spell)

      # Some classes may have their repertoire automatically written in a spellbook.
      # This is sometimes treated differently if prepared.

      prepare_ok = false
      make_signature = false

      spellbook = obj.spellbook[castclass]

      return [false, false] unless spellbook

      repertoire = obj.repertoire[castclass]

      book_spells_list = spellbook.values&.flatten

      rep_spells_list = repertoire ? repertoire[level] || [] : []

      is_in_book = book_spells_list.include? spell
      is_in_rep = rep_spells_list.include? spell

      prepare_ok = true if is_in_book

      make_signature = true if (is_in_book && is_in_rep)

      [prepare_ok, make_signature]
    end

    def self.open_spells_per_day(char, charclass, level)
      magic = char.magic
      return 0 unless magic

      list = magic.spells_per_day[charclass]
      return 0 unless list

      list[level].to_i
    end

    # { restriction => count } for one rank.
    def self.restricted_slots_at(char, charclass, level)
      magic = char.magic
      return {} unless magic

      for_class = (magic.restricted_slots || {})[charclass]
      return {} unless for_class.is_a?(Hash)

      for_class.each_with_object({}) do |(restriction, by_rank), hash|
        count = Pf2emagic.restricted_count_at_rank(by_rank, level)
        hash[restriction] = count if count.positive?
      end
    end

    def self.restricted_spell_list(char, charclass, restriction, level)
      case restriction.to_s.downcase
      when 'curriculum'
        Pf2emagic.curriculum_spells(char, charclass, level)
      else
        Global.logger.error "Unknown restricted slot '#{restriction}' for #{char.name}."
        []
      end
    end

    # Whether a set of prepared spells fits the slots available at a rank.
    def self.prepared_set_fits?(char, charclass, level, spells)
      open = open_spells_per_day(char, charclass, level)
      restricted = restricted_slots_at(char, charclass, level)

      return spells.size <= open if restricted.empty?
      return false if spells.size > open + restricted.values.sum

      if restricted.size > 1
        Global.logger.error "More than one restricted slot type at rank #{level} for #{char.name}; only the first is enforced."
      end

      restriction, count = restricted.first
      eligible = restricted_spell_list(char, charclass, restriction, level).map { |s| s.to_s.downcase }

      others = spells.reject { |s| eligible.include?(s.to_s.downcase) }

      others.size <= open && spells.size <= open + count
    end

    def self.max_spells_per_day(char, charclass, level)
      # Determines how many spells per day of that level the character can cast, for full spellcasting classes.
      # Not useful for focus-only classes.
      magic = char.magic
      return 0 unless magic

      # This will return nil for non-full casting classes.
      type = get_caster_type(charclass)
      return 0 unless type

      # This is the same whether you're a prepared or spontcaster.
      list = magic.spells_per_day[charclass]
      return 0 unless list

      sublist = list[level]

      sublist.to_i + restricted_slots_at(char, charclass, level).values.sum
    end

    def self.max_spell_level_available(char, charclass)
      # Determines max spell level available for full spellcasting classes.
      # Not useful for focus-only classes.
      magic = char.magic
      return nil unless magic

      # This will return nil for non-full casting classes.
      type = get_caster_type(charclass)
      return nil unless type

      # This is the same whether you're a prepared or spontcaster.
      list = magic.spells_per_day[charclass]
      return nil unless list

      levels_available = list.keys.sort { |a,b| a.to_i <=> b.to_i }

      levels_available.pop
    end

  end
end
