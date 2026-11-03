module AresMUSH
  class Pf2eCombat < Ohm::Model
    include ObjectModel

    attribute :saves, :type => DataType::Hash, :default => {}

    attribute :perception, :default => 'untrained'
    attribute :class_dc, :default => 'untrained'
    attribute :archetype_class_dcs, :type => DataType::Hash, :default => {}
    attribute :key_abil

    attribute :armor_prof, :type => DataType::Hash, :default => {}

    attribute :weapon_prof, :type => DataType::Hash, :default => {}
    attribute :weapon_group_prof, :type => DataType::Hash, :default => {}

    attribute :unarmed_attacks, :type => DataType::Hash, :default => {}
    attribute :defense, :type => DataType::Hash, :default => {}

    # The Rogue's sneak attack, as a dice expression ('1d6' … '4d6'). Set by the class table at
    # chargen, 5, 11 and 17, and read by `roll sneak attack`.
    attribute :sneak_attack

    reference :character, "AresMUSH::Character"


    ##### CLASS METHODS #####

    def self.get_save_from_char(char,save)
      combat = char.combat

      return 'untrained' if !char.combat

      (combat.saves || {})[save] || 'untrained'
    end

    def self.get_create_combat_obj(char)
      obj = char.combat

      return obj if obj

      obj = Pf2eCombat.create(character: char)
      char.update(combat: obj)

      return obj
    end

    def self.init_combat_stats(char, info)
      # Used only when initially populating combat.
      combat = get_create_combat_obj(char)

      info.each_pair do |key, value|
        combat.update("#{key}": value)
      end

      return combat
    end

    # How each key in a `combat_stats` block is written.
    #
    # `merge` keys hold a hash of name => proficiency and take the block's entries one at a time.
    # `set` keys hold a single value. A key absent from this table is logged, because a proficiency
    # a class never receives leaves nothing on the sheet to notice.
    #
    # A proficiency is never lowered. A class table names a rank at the level the class raises it,
    # and a feat may have raised it further in between. A value that is not a rank - a key ability,
    # sneak attack dice, an unarmed attack - is replaced as given.
    STAT_WRITERS = {
      'saves' => 'merge',
      'armor_prof' => 'merge',
      'weapon_prof' => 'merge',
      'weapon_group_prof' => 'merge',
      'unarmed_attacks' => 'define',
      'defense' => 'merge',
      'perception' => 'set',
      'class_dc' => 'set',
      'key_abil' => 'set',
      'sneak_attack' => 'set'
    }.freeze

    def self.update_combat_stats(char, info)
      # Used when something taken later modifies initial combat stats.
      combat = get_create_combat_obj(char)

      info.each_pair do |key, value|
        name = key.to_s

        # Archetypes nest a whole block per archetype, so it keeps its own arm.
        if name == 'archetype_class_dcs'
          write_archetype_dcs(combat, value)
          next
        end

        case STAT_WRITERS[name]
        when 'merge'
          combat.update(name.to_sym => merge_stat(combat.send(name) || {}, value || {}))
        when 'define'
          # Each entry is a definition, so a new one of the same name replaces the old whole.
          combat.update(name.to_sym => (combat.send(name) || {}).merge(value || {}))
        when 'set'
          combat.update(name.to_sym => Pf2e.higher_prof(combat.send(name), value))
        else
          Global.logger.error "Unknown combat stat '#{name}' for #{char.name}; it was not applied."
        end
      end

      return combat
    end

    # Keeps the better of what is held and what is written, however deep the stat nests: a rank
    # per weapon category within a group, a resistance per damage type. Resistances to one type do
    # not stack, so the larger number stands. Anything else is replaced.
    def self.merge_stat(held, written)
      return written if held.nil?
      return written.each_with_object(held.dup) { |(key, value), out| out[key] = merge_stat(out[key], value) } if held.is_a?(Hash) && written.is_a?(Hash)
      return [ held, written ].max if held.is_a?(Numeric) && written.is_a?(Numeric)
      return Pf2e.higher_prof(held, written) if Pf2e.prof_rank(held) && Pf2e.prof_rank(written)

      written
    end

    def self.write_archetype_dcs(combat, value)
      existing = combat.archetype_class_dcs || {}

      (value || {}).each_pair do |name, info|
        existing[name] ||= {}

        normalized = (info || {}).each_with_object({}) { |(k, v), out| out[k.to_s] = v }

        existing[name].merge!(normalized)
      end

      combat.update(archetype_class_dcs: existing)
    end

    def self.get_save_bonus(char, save, options = [])
      Pf2e::Stat.total(char, 'save', save, options)
    end

    def self.get_class_dc(char)
      return 0 if !char.combat

      Pf2e::Stat.total(char, 'class_dc')
    end

    def self.get_archetype_class_dcs(char)
      combat_stats = char.combat

      return {} if !combat_stats

      archetype_dcs = combat_stats.archetype_class_dcs || {}
      return {} if archetype_dcs.empty?

      dc_hash = {}

      archetype_dcs.each_pair do |archetype, info|
        next if !info.is_a?(Hash)

        prof = info['prof'] || info[:prof]
        key_ability = info['key_abil'] || info[:key_abil]

        if key_ability.to_s.strip.empty?
          configured_key_abilities = Array(Global.read_config('pf2e_archetype', archetype, 'key_abil')).compact.map { |a| a.to_s.strip }.reject(&:empty?).uniq
          key_ability = configured_key_abilities.first if configured_key_abilities.size == 1
        end

        next if prof.to_s.strip.empty?
        next if key_ability.to_s.strip.empty?

        # Through the same reader as the class DC itself, so an archetype's DC takes the modifiers a
        # class DC takes: Frightened reduces it, because it is a DC.
        dc_hash[archetype] = {
          'dc' => Pf2e::Stat.total(char, 'class_dc', { 'prof' => prof, 'key_abil' => key_ability }),
          'prof' => prof,
          'key_abil' => key_ability
        }
      end

      dc_hash
    end

    # Armour Class before anything modifies it: the flat 10, the armour worn, and proficiency with it.
    # The armour as an alteration leaves it, so Magic Armor or a spell hardening it is counted.
    def self.base_ac(char)
      armor = Pf2e::Alterations.armor(char)
      category = armor ? armor.category : "unarmored"

      10 + (armor ? armor.ac_bonus : 0) + Pf2e.get_prof_bonus(char, char.combat.armor_prof[category])
    end

    # The attribute and the rune, typed so they stack like anything else. The attribute is offered as
    # an `ability` modifier rather than added to the base, so an effect that lets a character use some
    # other attribute for AC needs only to offer that one and the better of the two applies.
    # The lowest cap on Dexterity holds, whether it is the armour's or an effect's: Mountain Stance caps it
    # at nothing, and a mutagen at two (`character/document.ts:746`).
    def self.ac_modifiers(char)
      armor = Pf2e::Alterations.armor(char)
      caps = Pf2e::Rules.contributions(Pf2e::Effects.sources(char), 'DexterityModifierCap',
                                       Pf2e::Effects.options(char), Pf2e::Effects.context(char))
      cap = ([ armor ? armor.dex_cap : 99 ] + caps.map { |one| one['value'] }).min

      dex = Pf2e::Stat.ability_mod(char, 'Dexterity')
      dex['value'] = dex['value'].clamp(-99, cap)

      [ dex, Pf2e::Stat.rune(char, 'potency'), raised_shield(char) ].compact
    end

    # A shield raised is its own circumstance bonus to AC until the effect of raising it ends. The
    # bonus is the shield's, which is why Raise a Shield's effect carries no number of its own; a broken
    # shield, at half its hit points or less, gives none.
    def self.raised_shield(char)
      shield = Pf2e::ShieldBlock.raised(char)

      return nil unless shield && shield.ac_bonus.to_i.positive?

      { 'source' => shield.nickname || shield.name, 'slug' => 'raised-shield', 'type' => 'circumstance',
        'value' => shield.ac_bonus.to_i }
    end

    def self.calculate_ac(char)
      Pf2e::Stat.total(char, 'ac')
    end

    def self.get_equipped_armor(char)
      char.armor&.select { |a| a.equipped }.first
    end

    def self.get_equipped_shield(char)
      char.shields&.select { |s| s.equipped }.first
    end

    def self.get_perception(char, options = [])
      Pf2e::Stat.total(char, 'perception', nil, options)
    end

    # Stat block for anything that can be attacked with, by name.
    #
    # Alchemical bombs are martial thrown weapons but they are also one-use items, so they live in pf2e_consumables rather than pf2e_weapons.
    def self.weapon_info(name)
      Global.read_config('pf2e_weapons', name) || Global.read_config('pf2e_consumables', name)
    end

    def self.bomb?(wp_info)
      Array(wp_info['traits']).any? { |t| t.to_s.casecmp?('bomb') }
    end

    def self.get_weapon_prof(char, name)
      combat = char.combat

      char_wp_prof = combat.weapon_prof ? combat.weapon_prof : {}
      group_profs = combat.weapon_group_prof ? combat.weapon_group_prof : {}

      wp_info = weapon_info(name)

      return 'untrained' if !wp_info

      wp_cat = wp_info['category']
      wp_group = wp_info['group']

      prof_list = [ 'untrained' ] + granted_weapon_prof(char, name, wp_info)

      # Its own category, and any a choice lets it count as: Advanced Weapon Training's advanced
      # weapons count as martial weapons of their group.
      categories = [ wp_cat.to_s ] + Pf2e.weapon_counts_as(char, wp_cat, wp_group)

      categories.each do |category|
        prof_list << char_wp_prof[category] if %w(unarmed simple martial advanced).include?(category)
      end

      # Does character get a proficiency in that particular weapon from their class?
      charclass_list = wp_info['charclass']

      if charclass_list
        if charclass_list.include?(char.pf2_base_info['charclass'])
          prof_list << char_wp_prof['charclass']
        end
      end

      # Check for ancestry weapon familiarity.
      ancestry_list = wp_info['ancestry']

      if ancestry_list
        char_ancestry = char.pf2_base_info['ancestry'].downcase
        Global.logger.debug "Char Ancestry - #{char_ancestry}"
        anc_wp_feat = (["sildanyar","khazad"].include? char_ancestry) ? char_ancestry + "i Weapon Familiarity" : char_ancestry + " Weapon Familiarity"
        Global.logger.debug "anc_wp_feat - #{anc_wp_feat}"
        if (Pf2e.has_feat?(char, anc_wp_feat) && ancestry_list.include?(char_ancestry))
          prof_list << char_wp_prof['ancestry']
        end
      end

      # Does character get a proficiency in that particular weapon from their deity?
      if char_wp_prof['deity']
        deity_weapon = Global.read_config('pf2e_deities', char.pf2_faith['deity'], 'fav_weapon')
        if deity_weapon && name.to_s.downcase == deity_weapon.to_s.downcase
          prof_list << char_wp_prof['deity']
        end
      end

      # Did the character choose this specific weapon, e.g. the advanced weapon picked for a
      # second or later Weapon Proficiency?
      if char_wp_prof['chosen']
        chosen = Pf2e.chosen_weapons(char)
        prof_list << char_wp_prof['chosen'] if chosen.any? { |w| w.to_s.casecmp?(name.to_s) }
      end

      # Alchemical bombs are martial thrown weapons, so the martial category above already
      # covers anyone trained in martial weapons. This is for the alchemist, who gains bombs
      # on a track of their own without ever becoming trained in martial weapons.
      if char_wp_prof['bomb'] && bomb?(wp_info)
        prof_list << char_wp_prof['bomb']
      end

      # Does character get a proficiency in that particular weapon from a weapon group choice?
      if wp_group && group_profs[wp_group]
        group_prof = group_profs[wp_group]

        categories.each { |category| prof_list << group_prof[category] }
      end

      prof_list << monk_weapon_prof(char_wp_prof, wp_info)

      prof_list = prof_list.compact

      # Of everything we've accumulated, the character's proficiency with that weapon is the best one in the list.
      Pf2e.select_best_prof(prof_list)

    end

    # Monastic Weaponry: simple and martial weapons with the monk trait at the rank it grants, or at
    # the character's unarmed rank up to master once that is higher.
    def self.monk_weapon_prof(char_wp_prof, wp_info)
      return nil unless char_wp_prof['monk']
      return nil unless %w(simple martial).include?(wp_info['category'].to_s)
      return nil unless Array(wp_info['traits']).any? { |trait| trait.to_s.casecmp?('monk') }

      unarmed = char_wp_prof['unarmed'].to_s.casecmp?('legendary') ? 'master' : char_wp_prof['unarmed']

      Pf2e.higher_prof(char_wp_prof['monk'], unarmed)
    end

    # The character's proficiency with one named unarmed attack.
    def self.get_unarmed_prof(char, name, atk_info = nil)
      combat = char.combat

      return 'untrained' if !combat

      char_wp_prof = combat.weapon_prof ? combat.weapon_prof : {}
      group_profs = combat.weapon_group_prof ? combat.weapon_group_prof : {}

      atk_info ||= (combat.unarmed_attacks || {})[name] || {}

      prof_list = [ 'untrained' ]

      # The flat category proficiency.
      prof_list << char_wp_prof['unarmed']

      # A deity's favoured weapon can name an unarmed attack rather than a weapon, the way Navos's is a fist.
      if char_wp_prof['deity']
        faith = char.pf2_faith || {}
        deity_weapon = Global.read_config('pf2e_deities', faith['deity'], 'fav_weapon') if !faith['deity'].blank?
        prof_list << char_wp_prof['deity'] if deity_weapon && name.to_s.casecmp?(deity_weapon.to_s)
      end

      # Did a feat choice name this specific attack?
      if char_wp_prof['chosen']
        chosen = Pf2e.chosen_weapons(char)
        prof_list << char_wp_prof['chosen'] if chosen.any? { |w| w.to_s.casecmp?(name.to_s) }
      end

      # Weapon group proficiency.
      group = atk_info['group']
      if !group.blank?
        group_key = group_profs.keys.find { |g| g.to_s.casecmp?(group.to_s) }
        group_prof = group_key ? group_profs[group_key] : nil
        prof_list << group_prof['unarmed'] if group_prof.is_a?(Hash) && group_prof['unarmed']
      end

      Pf2e.select_best_prof(prof_list.compact)
    end

    def self.get_armor_prof(char, name)

      combat = char.combat

      char_armor_prof = combat.armor_prof || {}

      armor_cat = Global.read_config('pf2e_armor', name, 'category')

      char_armor_prof[armor_cat] ? char_armor_prof[armor_cat] : 'untrained'

    end

    # What the attack and damage arithmetic need to know about an attack, from a catalogue weapon or
    # from an unarmed attack. Config writes `Finesse` and chargen writes `finesse`, which is why traits
    # are compared with `has_trait?` rather than `include?`.
    #
    # `id`, `group` and `base` are here because the domains are built off them: a rune that says
    # `{item|id}-damage` reaches this weapon and nothing else, and a feat that says
    # `sword-weapon-group-damage` reaches every sword.
    # What an attack answers to when a rule asks which attack it is: its id, its name, its base type and
    # Attacks a feat or an item granted, as descriptors the rest of the attack code already reads.
    #
    # A granted attack is proficient as an unarmed attack of its category, which is what the rules say of
    # the ones that exist - a stance's claws use your unarmed proficiency. A battle form's attacks are the
    # only ones its wearer has.
    def self.granted_strikes(char)
      form = Pf2e::BattleForms.strikes(char)

      return form if form.any?

      Pf2e::Rules.strikes(Pf2e::Effects.sources(char), Pf2e::Effects.options(char)).map do |strike|
        adjusted_strike(char, {
          'id' => nil, 'name' => strike['name'], 'source' => strike['source'], 'slug' => strike['slug'],
          'category' => strike['category'], 'prof' => get_unarmed_prof(char, strike['name']),
          'group' => strike['group'], 'base' => strike['base'],
          'traits' => strike['traits'], 'ranged' => !strike['range'].nil?,
          'unarmed' => strike['category'].to_s != 'martial',
          'bomb' => false, 'die' => strike['die'], 'dice' => strike['dice'],
          'range' => strike['range'].to_i, 'materials' => [], 'runes' => [],
          'damage_type' => strike['damage_type'] || 'B', 'striking' => 0, 'rune' => 0,
          'replace_all' => strike['replace_all']
        })
      end
    end

    # What a weapon answers to when a rule asks which weapons it means: its category, its group, its
    # base type and its traits, in Foundry's spelling.
    def self.weapon_options(name, info)
      info ||= weapon_info(name) || {}

      [ "item:slug:#{Pf2e::Domains.slug(name)}",
        "item:category:#{Pf2e::Domains.slug(info['category'])}",
        "item:group:#{Pf2e::Domains.slug(info['group'])}",
        "item:base:#{Pf2e::Domains.slug(info['base'] || name)}" ] +
        Array(info['traits']).map { |trait| "item:trait:#{Pf2e::Domains.slug(trait)}" }
    end

    # Proficiencies a feat grants over a kind of weapon: "monk weapons count as your unarmed
    # proficiency, up to master". The feat says which weapons and which proficiency to copy, so nothing
    # here names a feat.
    def self.granted_weapon_prof(char, name, info)
      combat = char.combat

      return [] unless combat

      held = (combat.weapon_prof || {})
      options = weapon_options(name, info)

      Pf2e::Rules.martial_proficiencies(Pf2e::Effects.sources(char), Pf2e::Effects.options(char))
                 .select { |one| Pf2e::Predicate.test(one['definition'], options) }
                 .map { |one| capped(held[one['same_as']], one['max_rank']) }
                 .compact
    end

    # A granted proficiency goes no higher than the feat says.
    def self.capped(rank, ceiling)
      return nil unless rank
      return rank unless ceiling

      [ Pf2e::Paths.rank_number(rank), Pf2e::Paths.rank_number(ceiling) ].min
                                                                        .then { |n| Pf2e::Paths.rank_name(n) }
    end

    # Damage a weapon does is recorded by initial here, and a predicate names it in full.
    DAMAGE_WORDS = { 'b' => 'bludgeoning', 'p' => 'piercing', 's' => 'slashing' }.freeze
    PHYSICAL = DAMAGE_WORDS.values.freeze

    # What an attack answers to when a rule asks which attacks it means, in Foundry's spelling - the
    # vocabulary their `definition` and their predicates are written in. Reading it off the descriptor
    # rather than the weapon is what lets a granted attack answer the same questions. A granted attack
    # answers to the slug its rule gave it, which is how a sibling rule names it: Slag May's claws are
    # `slag-may-claw`, and that is what makes them cold iron.
    def self.attack_options(descriptor, char = nil)
      damage = Pf2e::Domains.slug(DAMAGE_WORDS[descriptor['damage_type'].to_s.downcase] ||
                                  descriptor['damage_type'])
      thrown = Pf2e.has_trait?(descriptor['traits'], 'thrown')

      [ "item:id:#{descriptor['id']}",
        "item:slug:#{Pf2e::Domains.slug(descriptor['slug'] || descriptor['name'])}",
        descriptor['category'] ? "item:category:#{Pf2e::Domains.slug(descriptor['category'])}" : nil,
        "item:base:#{Pf2e::Domains.slug(descriptor['base'])}",
        "item:group:#{Pf2e::Domains.slug(descriptor['group'])}",
        descriptor['ranged'] ? 'item:ranged' : 'item:melee',
        thrown ? 'item:thrown' : nil,
        thrown && !descriptor['ranged'] ? 'item:thrown-melee' : nil,
        magical?(descriptor) ? 'item:magical' : nil,
        "item:damage:type:#{damage}",
        PHYSICAL.include?(damage) ? 'item:damage:category:physical' : nil,
        "item:hands-held:#{[ descriptor['hands'].to_i, 1 ].max}",
        "item:reload:#{descriptor['reload'].to_i}",
        "item:proficiency:rank:#{Pf2e::Paths.rank_number(descriptor['prof'])}",
        favored?(char, descriptor) ? 'item:deity-favored' : nil ].compact +
        Array(descriptor['traits']).map { |trait| "item:trait:#{Pf2e::Domains.slug(trait)}" } +
        Array(descriptor['materials']).map { |one| "item:material:#{Pf2e::Domains.slug(one)}" } +
        Array(descriptor['runes']).map { |one| "item:rune:property:#{Pf2e::Domains.slug(one)}" } +
        Array(descriptor['tags']).map { |one| "item:tag:#{Pf2e::Domains.slug(one)}" }
    end

    # Magical because it says so, or because someone etched it: a potency or striking rune makes a
    # weapon magical, which is what lets it hurt something only magic can.
    def self.magical?(descriptor)
      Pf2e.has_trait?(descriptor['traits'], 'magical') ||
        descriptor['rune'].to_i.positive? || descriptor['striking'].to_i.positive? ||
        Array(descriptor['runes']).any?
    end

    # The weapon a character's deity favours, which several feats and a champion's cause ask about.
    def self.favored?(char, descriptor)
      return false unless char.respond_to?(:pf2_faith)

      deity = (char.pf2_faith || {})['deity']
      favored = deity.blank? ? nil : Global.read_config('pf2e_deities', deity, 'fav_weapon')

      return false if favored.blank?

      [ descriptor['name'], descriptor['base'] ].compact.any? { |one|
        Pf2e::Domains.slug(one) == Pf2e::Domains.slug(favored)
      }
    end

    # What an effect changes about this attack before anything reads it: the traits it counts as
    # (`finesse` lets Dexterity attack with it, `thrown` adds Strength to its damage), what it is made
    # of, the property runes it has the effects of, and how far it throws.
    def self.adjusted_strike(char, descriptor)
      descriptor = with_unarmed_runes(char, descriptor)
      changes = Pf2e::Rules.strike_adjustments(Pf2e::Effects.sources(char),
                                               Pf2e::Effects.options(char),
                                               attack_options(descriptor, char))

      adjusted = changes.each_with_object(descriptor.dup) { |change, out| adjust_strike!(out, change) }

      # And what an effect changes about the weapon itself while it lasts: Magic Weapon's runes.
      Pf2e::Alterations.attack(char, adjusted)
    end

    # Handwraps of mighty blows are not a weapon to Strike with. Invested, they give their runes to every
    # unarmed attack, and the catalogue marks an item that does so `unarmed_runes`.
    def self.rune_lender?(name)
      !!(weapon_info(name) || {})['unarmed_runes']
    end

    # The invested item whose runes the character's unarmed attacks have, the better of two.
    def self.unarmed_rune_item(char)
      Pf2egear::Inventory.held(char, 'weapons')
                         .select { |item| item.invested && rune_lender?(item.name) }
                         .max_by { |item| [ Pf2egear.get_rune_value(item, 'fundamental', 'potency').to_i,
                                            Pf2egear.get_rune_value(item, 'fundamental', 'power').to_i ] }
    end

    # An unarmed attack the character has by nature or by a feat, with those runes. A property rune's
    # rules name the item it is etched on, so the attack answers to that item's id as `rune_item`.
    def self.with_unarmed_runes(char, descriptor)
      return descriptor unless descriptor['id'].nil? && descriptor['category'].to_s == 'unarmed'

      lender = unarmed_rune_item(char)

      return descriptor unless lender

      descriptor.merge('rune' => Pf2egear.get_rune_value(lender, 'fundamental', 'potency').to_i,
                       'striking' => Pf2egear.get_rune_value(lender, 'fundamental', 'power').to_i,
                       'runes' => (Array(descriptor['runes']) + Pf2egear.property_runes(lender)).uniq,
                       'rune_item' => lender.id.to_s)
    end

    def self.adjust_strike!(descriptor, change)
      field = Pf2e::Rules::STRIKE_PROPERTIES[change['property']]
      held = descriptor[field]

      if Pf2e::Rules::STRIKE_LISTS.include?(field)
        # A word is only ever added to a list: nothing in their data takes a trait or a rune away.
        return unless change['mode'] == 'add'

        descriptor[field] = (Array(held) + [ Pf2e::Domains.slug(change['value']) ]).uniq
      else
        mode = Pf2e::Paths::MODES[change['mode']]

        descriptor[field] = mode.call(held.to_i, change['value'].to_i) if mode
      end
    end

    def self.attack_descriptor(char, weapon, twohand = false)
      info = weapon_info(weapon.name) || {}
      damage = twohand && weapon.wp_damage_2h ? weapon.wp_damage_2h : weapon.wp_damage

      adjusted_strike(char, { 'id' => weapon.id.to_s, 'name' => weapon.name,
        'prof' => get_weapon_prof(char, weapon.name), 'category' => info['category'],
        'group' => info['group'], 'base' => info['base'] || weapon.name,
        'traits' => weapon.traits, 'ranged' => weapon.wp_type == 'ranged',
        'unarmed' => Pf2e.has_trait?(weapon.traits, 'unarmed'),
        'bomb' => bomb?(info),
        'die' => damage, 'damage_type' => weapon.wp_damage_type,
        'range' => weapon.range.to_i, 'reload' => weapon.reload.to_i,
        'hands' => twohand ? 2 : weapon.hands.to_i,
        'materials' => Array(info['materials']),
        'runes' => Pf2egear.property_runes(weapon),
        'striking' => Pf2egear.get_rune_value(weapon, 'fundamental', 'power'),
        'rune' => Pf2egear.get_rune_value(weapon, 'fundamental', 'potency') })
    end

    # A bomb the character carries, thrown as a Strike: a martial weapon of the bomb group, whose item
    # bonus to hit is the bomb's own, and whose damage is its dice - or a flat amount, where it has no
    # die - its persistent damage and its splash, and the effect it leaves on whoever it hits.
    # `consumable` is the item one is spent from.
    def self.bomb_descriptor(char, item)
      info = weapon_info(item.name) || {}
      bomb = info['bomb'] || {}

      adjusted_strike(char, { 'id' => item.id.to_s, 'name' => item.name,
        'prof' => get_weapon_prof(char, item.name), 'category' => info['category'],
        'group' => 'bomb', 'base' => item.name, 'traits' => Array(info['traits']), 'ranged' => true,
        'unarmed' => false, 'bomb' => true,
        'die' => bomb['die'], 'dice' => bomb['die'] ? bomb['dice'].to_i : nil, 'flat' => bomb['die'] ? 0 : bomb['dice'].to_i,
        'damage_type' => bomb['damage_type'], 'range' => bomb['range'].to_i, 'reload' => 0, 'hands' => 1,
        'materials' => [], 'runes' => [], 'striking' => 0, 'rune' => bomb['bonus'].to_i,
        'persistent' => bomb['persistent'], 'persistent_type' => bomb['persistent_type'],
        'splash' => bomb['splash'].to_i, 'effect' => info['effect'], 'consumable' => item.id.to_s })
    end

    # An unarmed attack's damage is written with its count, `1d4`, where a weapon's is its die alone; both
    # are read here, so a fist rolls one d4 and not a d14.
    def self.unarmed_descriptor(name, info, prof, char = nil)
      written = info['damage'].to_s.match(/\A(\d*)(d\d+)\z/)
      descriptor = { 'id' => nil, 'name' => name, 'prof' => prof, 'group' => info['group'],
                     'category' => 'unarmed', 'base' => name, 'traits' => info['traits'], 'ranged' => false, 'unarmed' => true,
                     'bomb' => false, 'die' => written ? written[2] : info['damage'],
                     'dice' => written && !written[1].empty? ? written[1].to_i : nil, 'range' => 0,
                     'materials' => [], 'runes' => [],
                     'damage_type' => info['damage_type'] || 'B', 'striking' => 0, 'rune' => 0 }

      char ? adjusted_strike(char, descriptor) : descriptor
    end

    def self.get_wpattack_bonus(char, weapon, options = [])
      Pf2e::Stat.total(char, 'attack', attack_descriptor(char, weapon), options)
    end

    def self.get_unarmed_bonus(char, name, info, prof)
      Pf2e::Stat.total(char, 'attack', unarmed_descriptor(name, info, prof))
    end

    def self.get_natattack_bonus(char, attack)

    end

    # `twohand` is for a one-handed weapon that does more damage wielded in two; it is ignored for a
    # weapon whose damage does not change.
    def self.damage_descriptor(char, attack, weapon = nil, twohand = false, given = nil)
      return given if given
      return attack_descriptor(char, weapon, twohand) if weapon

      info = (char.combat&.unarmed_attacks || {})[attack.to_s.capitalize] || {}

      name = attack.to_s.capitalize

      unarmed_descriptor(name, info, get_unarmed_prof(char, name, info), char)
    end

    def self.get_damage(char, attack, weapon=nil, twohand=false, options=[])
      Pf2e::Damage.formula(char, damage_descriptor(char, attack, weapon, twohand), options)
    end

    def self.damage_breakdown(char, attack, weapon=nil, twohand=false, options=[], given=nil)
      Pf2e::Damage.of(char, damage_descriptor(char, attack, weapon, twohand, given), options)
    end

    def self.factory_default(char)
      # This may or may not exist, nothing to do if not.
      combat = char.combat
      return unless combat

      combat.saves = {}
      combat.perception = 'untrained'
      combat.class_dc = 'untrained'
      combat.archetype_class_dcs = {}
      combat.key_abil = nil

      combat.armor_prof = {}
      combat.weapon_prof = {}
      combat.weapon_group_prof = {}
      combat.unarmed_attacks = {}

      combat.save
    end
  end
end
