module AresMUSH
  class PF2Magic < Ohm::Model
    include ObjectModel

    # The focus pool stays here and stays shared: PF2e gives a character one pool however many
    # sources feed it. The spells themselves moved to Pf2eSpellcastingEntry rows, one per focus
    # type per granting source, because a single bucket per type could not say whose they were.
    attribute :focus_pool, :type => DataType::Hash, :default => { "max"=>0, "current"=>0 }
    attribute :last_refocus, :type => DataType::Time
    # A list of grants rather than a map keyed by spell name, because two sources can grant
    # the same innate spell and a map silently loses one of them. Charm is granted by
    # Enthralling Allure at rank 4 divine and by Supernatural Charm at rank 1 arcane;
    # Interplanar Teleport by one source as divine and another as primal; and six sources grant
    # an unchosen 'open' spell, which as a single key meant taking two of them lost a pick.
    # Each grant is { 'name', 'level', 'tradition', 'cast_stat' }. Read it through
    # Pf2emagic::Entries, not directly.
    attribute :innate_spells, :type => DataType::Array, :default => []
    attribute :revelation_locked, :type => DataType::Boolean
    attribute :signature_spells, :type => DataType::Hash, :default => {}
    attribute :repertoire, :type => DataType::Hash, :default => {}
    attribute :spell_abil, :type => DataType::Hash, :default => {}
    attribute :spellbook, :type => DataType::Hash, :default => {}
    attribute :spells_per_day, :type => DataType::Hash, :default => {}
    attribute :restricted_slots, :type => DataType::Hash, :default => {}
    attribute :restricted_spellbook, :type => DataType::Hash, :default => {}
    attribute :spells_prepared, :type => DataType::Hash, :default => {}
    attribute :spells_today, :type => DataType::Hash, :default => {}
    attribute :adapted_spells, :type => DataType::Hash, :default => {}
    attribute :tradition, :type => DataType::Hash, :default => { "innate"=>["innate", "trained"] }
    attribute :prepared_lists, :type => DataType::Hash, :default => {}
    attribute :divine_font

    reference :character, "AresMUSH::Character"


    ##### CLASS METHODS #####

    def self.get_magic_obj(char)
      char.magic
    end

    def self.get_create_magic_obj(char)
      obj = char.magic

      return obj if obj

      obj = PF2Magic.create(character: char)
      char.update(magic: obj)

      return obj
    end

    def self.assess_magic_stats(char, info)
      magic_stats = {}
      magic_options = {}

      info.each_pair do |key, value|
        case key
        when "innate_spell"
          # The entry itself belongs in magic_stats so update_magic grants the spell when the
          # advancement is committed. An 'open' name additionally needs a slot to choose it in, and
          # the stats entry is what advance/spell reads for the slot's rank and tradition.
          magic_stats["innate_spell"] = value.dup

          names = Array(value['name'])
          open_count = names.count { |n| n.to_s.downcase == 'open' }

          if open_count > 0
            level_key = value['level'].to_i.zero? || value['level'].to_s.downcase == 'cantrip' ? 'cantrip' : value['level'].to_s
            assignment_list = magic_options['innate'] || {}
            list = assignment_list[level_key] || []
            list.concat(Array.new(open_count, 'open'))
            assignment_list[level_key] = list
            magic_options['innate'] = assignment_list
          end
        when "repertoire"

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          magic_options["repertoire"] = assignment_list
        when "spellbook"
          assignment_list = magic_options["spellbook"] || {}

          if value.is_a?(Hash)
            value.each_pair do |level, num|
              assignment_list[level] = Array(assignment_list[level]) + Array.new(num, "open")
            end
          else
            key = Pf2emagic::ANY_RANK
            assignment_list[key] = Array(assignment_list[key]) + Array.new(value.to_i, "open")
          end

          magic_options["spellbook"] = assignment_list
        when "signature_spell", "signature_spells"
          # This key means that the character needs to pick a spell from their repertoire as a signature spell.
          # Structure of value: { level to pick from => number of spells to add }
          # Use to_assign["signature"]

          magic_stats["signature_spells"] = value

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          magic_options["signature"] = assignment_list
        else
          magic_stats[key] = value
        end
      end

      # Return a hash comprised of the two keys.
      hash = {}

      hash['magic_stats'] = magic_stats
      hash['magic_options'] = magic_options

      hash
    end

    def self.update_magic(char, charclass, info, client)
      magic = get_create_magic_obj(char)

      # Race condition with to_assign requires that to_assign be assembled and returned by the function for a merge.
      to_assign = {}

      info.each_pair do |key, value|
        case key
        when "spell_abil"
          spell_abil = magic.spell_abil
          spell_abil[charclass] = value
          magic.spell_abil = spell_abil

          Pf2emagic::Entries.grant_casting!(char, charclass, :ability => value)

        when "tradition"
          # The hash is still the register of which classes cast at all - Entries.derived reads
          # it to find them - so it is written as well as the row, until the spell lists move too.
          tradition = magic.tradition
          value.each_pair do |trad, prof|
            tradition[charclass] = [ trad, prof ]

            Pf2emagic::Entries.grant_casting!(char, charclass, :tradition => trad, :proficiency => prof)
          end

          magic.tradition = tradition
        when "spells_per_day"
          # Structure: { charclass => {"cantrip" => 5, 1 => 3, 2 => 1} }
          # This key grants spells per day.

          spells_per_day = magic.spells_per_day
          spd_for_class = spells_per_day[charclass] ? spells_per_day[charclass] : {}

          value.each_pair do |level, num|
            spd_for_class[level] = Pf2emagic.apply_stat_delta(spd_for_class[level], num)
          end

          spells_per_day[charclass] = spd_for_class

          magic.spells_per_day = spells_per_day
        when "restricted_slots", "restricted_spellbook"
          # Structure: { charclass => { restriction => { "cantrip" => 1, 1 => 1 } } }, for the
          # slots a restriction reserves per day and the spellbook entries it reserves. The two
          # differ only in which attribute they land in, so they share one branch.
          restricted = magic.send(key)
          for_class = restricted[charclass] || {}

          (value || {}).each_pair do |restriction, by_rank|
            existing = for_class[restriction] || {}

            (by_rank || {}).each_pair do |rank, num|
              existing[rank] = Pf2emagic.apply_stat_delta(existing[rank], num)
            end

            for_class[restriction] = existing
          end

          restricted[charclass] = for_class

          magic.send("#{key}=", restricted)
        when "repertoire"
          # Structure: { "cantrip" => 5, 1 => 3, 2 => 1 }
          # This key gets dumped into to_assign as repertoire and represents spells that need to be chosen
          # for the repertoire.

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          to_assign["repertoire"] = assignment_list

        when "focus_pool"
          pool = magic.focus_pool

          old_max_pool = pool["max"].to_i
          old_current_pool = pool["current"].to_i

          new_max_pool = Pf2emagic.get_max_focus_pool(char, value)
          pool["max"] = new_max_pool

          new_current_pool = if old_max_pool.zero? && old_current_pool.zero?
                               new_max_pool
                             elsif old_current_pool == old_max_pool
                               new_max_pool
                             else
                               [ old_current_pool, new_max_pool ].min
                             end

          pool["current"] = new_current_pool
          magic.focus_pool = pool
        when "addrepertoire"
          # This key is called for spells added to the repertoire by bloodlines, mysteries, etc.
          # Initial/advanced/greater bloodline spells are focus spells and handled by that key.
          # Expected structure of value: { <level> => <spell> }
          repertoire = magic.repertoire
          rep_for_class = repertoire[charclass] || {}

          value.each_pair do |level, spell|
            list = rep_for_class[level] || []
            spell.each { |s| list << s }
            rep_for_class[level] = list
          end

          repertoire[charclass] = rep_for_class

          magic.repertoire = repertoire
        when "get_genie_repertoire"
          # Value of this key is an integer that corresponds to the level of the spell.
          # It works like repertoire, but what this bloodline gets depends on their genie ancestry.

          genie = char.pf2_base_info['specialize_info']
          spells = Global.read_config('pf2e_subclass', 'get_genie_spell', genie)

          # Do nothing if genie not found.
          next unless spells

          # Grab the spell corresponding to value.
          spell = spells[value]

          next unless spell

          repertoire = magic.repertoire
          rep_for_class = repertoire[charclass]

          rep_at_level = rep_for_class[value] || []

          rep_at_level << spell

          rep_for_class[value] = rep_at_level

          repertoire[charclass] = rep_for_class

          magic.repertoire = repertoire
        when "get_dragon_repertoire"
          # Value of this key is an integer that corresponds to the level of the spell.
          # It works like repertoire, but what this bloodline gets depends on their dragon ancestry.

          draconic = char.pf2_base_info['specialize_info']
          spells = Global.read_config('pf2e_subclass', 'get_dragon_spell', draconic)

          # Do nothing if draconic not found.
          next unless spells

          # Grab the spell corresponding to value.
          spell = spells[value]

          next unless spell

          repertoire = magic.repertoire
          rep_for_class = repertoire[charclass]

          rep_at_level = rep_for_class[value] || []

          rep_at_level << spell

          rep_for_class[value] = rep_at_level

          repertoire[charclass] = rep_for_class

          magic.repertoire = repertoire
        when "focus_spell", "domain_focus_spell", "focus_cantrip"
          # One spellcasting entry per focus type per granting source, so two sources of the same
          # type stay apart - they share PF2e's single focus pool but cast at their own DCs.
          # Cantrips and spells are the same entry under different keys, because they differ only
          # in how they are cast.
          kind = key.to_s == 'focus_cantrip' ? 'cantrip' : 'spell'

          # A block may name what granted it - "Domain Healing" for a cleric's domain spell -
          # and otherwise it is the class itself. Recorded with the level, so the sheet can say
          # where a focus spell came from without deriving it.
          source = info['focus_source'].presence || charclass

          value.each_pair do |fstype, spell_list|
            Pf2emagic::Entries.grant_focus!(char, fstype, spell_list,
              :kind => kind, :granted_by => source, :granted_at => char.pf2_level)
          end
        when "spellbook"
          # Spells need to be chosen, redirect to to_assign.

          assignment_list = to_assign["spellbook"] || {}

          if value.is_a?(Hash)
            value.each_pair do |level, num|
              assignment_list[level] = Array(assignment_list[level]) + Array.new(num, "open")
            end
          else
            key = Pf2emagic::ANY_RANK
            assignment_list[key] = Array(assignment_list[key]) + Array.new(value.to_i, "open")
          end

          to_assign["spellbook"] = assignment_list

        when "addspellbook"
          # Addspellbook means to add a specific spell to the spellbook. Adding spells to be chosen
          # should be the "spellbook" key.
          # Structure of value for addspell key: { level => [ spell ] }

          spellbook = magic.spellbook

          # Initialize spellbook for class if not already present.
          csb = spellbook[charclass] ? spellbook[charclass] : {}

          value.each do |level, spell_list|
            list = csb[level] ? csb[level] : []

            spell_list.each { |s| list << s }

            csb[level] = list
          end

          spellbook[charclass] = csb
          magic.spellbook = spellbook
        when "adapted_spell"
          # Structure: { "name" => spell, "tradition" => trad, "base_level" => n,
          #                       "source" => feat, "no_heighten" => bool }
          name = value['name'].to_s

          unless name.empty?
            adapted_class = Pf2emagic.get_caster_type(charclass) ? charclass : nil

            adapted = magic.adapted_spells
            adapted[name] = {
              'tradition'  => value['tradition'].to_s.downcase,
              'base_level' => value['base_level'].to_i,
              'source'     => value['source'],
              'class'      => adapted_class
            }
            adapted[name]['no_heighten'] = true if value['no_heighten']

            magic.adapted_spells = adapted
          end
        when "signature_spell", "signature_spells"
          # This key means that the character needs to pick a spell from their repertoire as a signature spell.
          # Structure of value: { level to pick from => number of spells to add }
          # Use to_assign["signature"]

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          to_assign["signature"] = assignment_list

        when "innate_spell"
          # One grant appended per spell, so two sources granting the same spell are two grants
          # rather than one overwriting the other. See the note on the attribute.
          grants = Array(magic.innate_spells)
          spell_data = value.reject { |k, _| k == 'name' }

          Array(value['name']).each do |spell_name|
            next if spell_name.nil? || spell_name.to_s.empty?

            grants = grants + [ spell_data.merge('name' => spell_name) ]
          end

          magic.innate_spells = grants
        when "divine_font"
          if value.size > 1

            to_assign['divine font'] = value
          else
            magic.update(divine_font: value.first)
          end
        when 'grant_choice'
          Array(value).compact.each { |name| Pf2e.open_feat_choice(to_assign, name.to_s) }
        when 'gated_spell'
          sublist_name = value + " spell"

          to_assign[sublist_name] = value
        else
          client.emit_ooc "Unknown key #{key} in update_magic. Please inform staff."
        end

      end

      magic.save
      char.save

      # The return of this function should be merged into pf2_to_assign.
      to_assign
    end

    def self.get_spell_dc(char, charclass, is_focus=false)

      # is_focus should be the focus spell type if given.
      caster_stats = Pf2emagic.get_caster_stats(char, charclass, is_focus)

      return 0 if caster_stats.is_a? String

      prof = caster_stats['prof_level']
      prof_bonus = Pf2e.get_prof_bonus(char, prof)

      abil_mod = caster_stats['modifier']

      10 + abil_mod + prof_bonus
    end

    def self.get_spell_abil(char, charclass, is_focus=false)
      if charclass == "innate"
        spell_abil = "Charisma"
      elsif is_focus
        spell_abil = Pf2emagic.get_focus_casting_stat(is_focus)
      else
        magic = char.magic
        spell_abil = magic.spell_abil[charclass]
      end

      spell_abil
    end

    def self.get_spell_attack_bonus(char, charclass, is_focus=false)

      # is_focus should be the focus spell type if given.
      caster_stats = Pf2emagic.get_caster_stats(char, charclass, is_focus)

      return 0 if caster_stats.is_a? String

      prof = caster_stats['prof_level']
      prof_bonus = Pf2e.get_prof_bonus(char, prof)

      abil_mod = caster_stats['modifier']

      abil_mod + prof_bonus
    end

    def self.factory_default(char)

      magic = char.magic

      # Don't do anything unless magic is created.
      return nil unless magic

      (default_values || {}).each_pair do |attr, value|
        copy = value.is_a?(Hash) || value.is_a?(Array) ? Marshal.load(Marshal.dump(value)) : value
        magic.public_send("#{attr}=", copy)
      end

      # Attributes with no declared default that a reset should still clear.
      magic.divine_font = nil
      magic.revelation_locked = nil
      magic.last_refocus = nil

      magic.save

    end

  end
end
