module AresMUSH
  module Pf2e

    # A figure on the sheet, and the arithmetic behind it.
    #
    # Each of these used to be assembled by hand in whichever model owned it, and they did not agree
    # on shape: a save counted its armour rune and the class DC counted no item bonus, a skill's item
    # bonus was added by the roll parser but not by the skill reader, and nothing anywhere could say
    # "these two bonuses do not stack" because nothing carried a type.
    #
    # Now a kind of statistic is a row: what its base is, and which modifiers are intrinsic to it -
    # the attribute it reads, the rune on the armour worn for it. Everything else reaches it through
    # `Pf2e::Domains`, so a feat or a condition that changes it is config rather than code.
    #
    #   Pf2e::Stat.of(char, 'save', 'Fortitude')
    #   # => { 'base' => 12, 'modifiers' => [ … ], 'total' => 15 }
    #
    # The list is the point as much as the total: a player can see that the ring was counted and the
    # spell was overridden, rather than being handed a number and asked to trust it.
    module Stat

      # One row per kind of figure. `base` is what the figure is before anything modifies it;
      # `intrinsic` are the modifiers the figure carries by its own nature, which are typed so they
      # obey the same stacking rule as everything else; `ability` names the attribute it reads, which
      # decides its `<attr>-based` domain. `domain_name` is for a figure a caller may name more than
      # one way - a save is asked for as both `fort` and `fortitude`, and both have to answer to the
      # same domain.
      KINDS = [
        { 'name' => 'hp',
          'ability' => ->(_char, _name) { nil },
          # Constitution is inside the base because it is per level. Drained's own row multiplies by
          # level to match, which is what adopting a formula language buys.
          'base' => ->(char, _name) { Pf2eHP.base_max_hp(char) },
          'intrinsic' => ->(_char, _name) { [] } },

        # `name` is the kind of movement, land when nobody says. A kind other than land exists only
        # because the ancestry has it or something granted it, and the highest grant wins.
        { 'name' => 'speed',
          'ability' => ->(_char, _name) { nil },
          'base' => ->(char, movement) { speed_base(char, movement) },
          # Armour slows a character by its own untyped amount, so Encumbered's status penalty is on
          # top of it rather than competing with it.
          'intrinsic' => ->(char, _name) { [ armor_penalty(char) ] } },

        { 'name' => 'ac',
          'ability' => ->(_char, _name) { 'Dexterity' },
          'base' => ->(char, _name) { Pf2eCombat.base_ac(char) },
          'basis' => ->(char, _name) { ac_basis(char) },
          'intrinsic' => ->(char, _name) { Pf2eCombat.ac_modifiers(char) } },

        { 'name' => 'perception',
          'ability' => ->(_char, _name) { 'Wisdom' },
          'base' => ->(char, _name) { Pf2e.get_prof_bonus(char, char.combat&.perception) },
          'rank' => ->(char, _name) { char.combat&.perception },
          'intrinsic' => ->(char, _name) { [ ability_mod(char, 'Wisdom') ] } },

        { 'name' => 'save',
          'ability' => ->(_char, name) { Pf2e::LINKED_ABILITY[name.to_s.downcase] },
          'domain_name' => ->(name) { Pf2e.canonical_save(name) },
          'base' => ->(char, name) {
            Pf2e.get_prof_bonus(char, Pf2eCombat.get_save_from_char(char, name))
          },
          'rank' => ->(char, name) { Pf2eCombat.get_save_from_char(char, name) },
          'intrinsic' => ->(char, name) {
            [ ability_mod(char, Pf2e::LINKED_ABILITY[name.to_s.downcase]),
              # This game's armour carries `potency` for AC and `power` for saves, which is what the
              # rules call resilient.
              rune(char, 'power') ]
          } },

        { 'name' => 'skill',
          'ability' => ->(_char, name) { Pf2eSkills.get_linked_attr(name) },
          'base' => ->(char, name) { Pf2e.get_prof_bonus(char, Pf2eSkills.get_skill_prof(char, name)) },
          'rank' => ->(char, name) { Pf2eSkills.get_skill_prof(char, name) },
          'intrinsic' => ->(char, name) {
            [ ability_mod(char, Pf2eSkills.get_linked_attr(name)), armor_check_penalty(char, name) ]
          } },

        { 'name' => 'lore',
          'ability' => ->(_char, _name) { 'Intelligence' },
          'base' => ->(char, name) { Pf2e.get_prof_bonus(char, Pf2eSkills.get_skill_prof(char, name)) },
          'rank' => ->(char, name) { Pf2eSkills.get_skill_prof(char, name) },
          'intrinsic' => ->(char, _name) { [ ability_mod(char, 'Intelligence') ] } },

        # Here `name` is a descriptor rather than a name: `Pf2eCombat.attack_descriptor` builds one
        # from a weapon and one from an unarmed attack, so both go through the same arithmetic.
        #
        # A ranged attack reads Dexterity, a finesse attack the better of Strength and Dexterity -
        # which is not a comparison here, because both are offered as `ability` modifiers and the
        # stacking rule takes the better of them by itself.
        { 'name' => 'attack',
          'ability' => ->(_char, attack) { attack_abilities(attack) },
          'base' => ->(char, attack) { Pf2e.get_prof_bonus(char, attack['prof']) },
          'rank' => ->(_char, attack) { attack['prof'] },
          'intrinsic' => ->(char, attack) {
            attack_abilities(attack).map { |ability| ability_mod(char, ability) } +
              [ item(attack['rune'], 'potency rune', 'weapon-potency') ]
          } },

        # `name` is the caster stats block `Pf2emagic.get_caster_stats` returns, which already carries
        # the proficiency and the casting attribute.
        { 'name' => 'spell_dc',
          'ability' => ->(_char, caster) { caster['spell_abil'] },
          'base' => ->(char, caster) { 10 + Pf2e.get_prof_bonus(char, caster['prof_level']) },
          'rank' => ->(_char, caster) { caster['prof_level'] },
          'intrinsic' => ->(char, caster) { [ ability_mod(char, caster['spell_abil']) ] } },

        { 'name' => 'spell_attack',
          'ability' => ->(_char, caster) { caster['spell_abil'] },
          'base' => ->(char, caster) { Pf2e.get_prof_bonus(char, caster['prof_level']) },
          'rank' => ->(_char, caster) { caster['prof_level'] },
          'intrinsic' => ->(char, caster) { [ ability_mod(char, caster['spell_abil']) ] } },

        # `name` is nothing for the character's own class DC, and an archetype's proficiency and key
        # attribute when an archetype has one of its own. Both are the same figure with different inputs.
        { 'name' => 'class_dc',
          'ability' => ->(char, named) { class_attribute(char, named) },
          'base' => ->(char, named) { 10 + Pf2e.get_prof_bonus(char, class_proficiency(char, named)) },
          'rank' => ->(char, named) { class_proficiency(char, named) },
          'intrinsic' => ->(char, named) { [ ability_mod(char, class_attribute(char, named)) ] } },

        # How much more a character recovers than they were given. Not a figure on a sheet: the base is
        # nothing, so the total is whatever the effects come to - which is what a bonus to healing is.
        { 'name' => 'healing',
          'ability' => ->(_char, _name) { nil },
          'base' => ->(_char, _name) { 0 },
          'intrinsic' => ->(_char, _name) { [] } }
      ].freeze

      BY_KIND = KINDS.each_with_object({}) { |row, out| out[row['name']] = row }.freeze

      # `options` are the circumstances a predicate is tested against beyond what is true of the
      # character anyway - what the player said they are doing. A roll supplies them; a sheet does not,
      # which is why a sheet reports a conditional bonus rather than counting it.
      #
      # `extra` are domains this reading of the figure also answers to. Initiative is a Perception check
      # that also answers to `initiative`, which is how Foundry composes it: the base statistic's
      # domains plus its own.
      def self.of(char, kind, name = nil, options = [], extra = [])
        row = BY_KIND[kind.to_s]

        raise ArgumentError, "no such kind of statistic: #{kind.inspect}" unless row

        ability = row['ability'].call(char, name)
        named = row['domain_name'] ? row['domain_name'].call(name) : name
        domains = Domains.for(kind, named, ability) + Array(extra)

        sources = Effects.sources(char)
        context = Effects.context(char)
        held = Effects.options(char, domains) + Array(options)

        effects = Effects.modifiers(sources, domains, context, held)
        met, unmet = effects.partition { |effect| effect['met'] }

        # A figure's own parts can have circumstances too: armour hampers a skill until its wearer is
        # strong enough for it, and a feat can waive that. One whose circumstances are unmet is reported
        # the same way an effect's is, rather than counted.
        own, waived = (row['intrinsic'].call(char, name) + [ multiple_attack(kind, name, sources, domains, held, context) ])
                        .compact.partition { |one| Predicate.test(one['when'], held) }

        # A rule that changes a modifier is applied before anything is stacked, so the comparison that
        # decides which of them count is against the adjusted numbers.
        adjusted = Modifiers.adjust(own + met,
                                    Rules.modifier_adjustments(sources, domains, held, context))

        # An unmet row is kept out of the stacking, so it cannot override one that applies, but it is
        # still reported: "+2, but only while picking a lock" is what a player wants to know.
        figure = Modifiers.breakdown(row['base'].call(char, name).to_i, adjusted)
                          .merge('conditional' => unmet + waived, 'basis' => basis(row, char, name))

        # A character in a battle form has the form's AC, skills, attacks and speeds where those are
        # better or the form insists.
        BattleForms.override(char, kind, name, figure, options, extra)
      end

      # What the base is made of, for whoever asks why: `expert, level 11`; for AC the armour as well.
      def self.basis(row, char, name)
        return row['basis'].call(char, name) if row['basis']
        return nil unless row['rank']

        proficiency(char, row['rank'].call(char, name))
      end

      def self.proficiency(char, rank)
        rank = rank.to_s.downcase
        rank.empty? || rank == 'untrained' ? 'untrained' : "#{rank}, level #{char.pf2_level.to_i}"
      end

      def self.ac_basis(char)
        armor = Alterations.armor(char)
        category = armor ? armor.category : 'unarmored'
        worn = armor && armor.ac_bonus.to_i.positive? ? ", #{armor.name} +#{armor.ac_bonus.to_i}" : ''

        "10#{worn}, #{proficiency(char, (char.combat&.armor_prof || {})[category])}"
      end

      def self.total(char, kind, name = nil, options = [], extra = [])
        of(char, kind, name, options, extra)['total']
      end

      # What a player means by a figure's name. Tried in order, so `fort` reaches the save rather than
      # a skill, and anything the catalogue does not hold is a lore - which is what a lore is.
      NAMED = [
        { 'match' => ->(term) { %w{hp hitpoints health}.include?(term) },
          'stat' => ->(_term) { [ 'hp', nil ] } },
        { 'match' => ->(term) { %w{ac armor armour}.include?(term) },
          'stat' => ->(_term) { [ 'ac', nil ] } },
        { 'match' => ->(term) { term == 'speed' },
          'stat' => ->(_term) { [ 'speed', nil ] } },
        { 'match' => ->(term) { %w{perception per}.include?(term) },
          'stat' => ->(_term) { [ 'perception', nil ] } },
        { 'match' => ->(term) { Pf2e::SAVES.include?(term) },
          'stat' => ->(term) { [ 'save', term ] } },
        { 'match' => ->(term) { [ 'class dc', 'classdc', 'class' ].include?(term) },
          'stat' => ->(_term) { [ 'class_dc', nil ] } },
        # Before skills, because most of the catalogue is lores and a lore wants the domain that
        # reaches every lore at once.
        { 'match' => ->(term) { Pf2eSkills.lore?(term) },
          'stat' => ->(term) { [ 'lore', skill_named(term) || titleize(term) ] } },
        { 'match' => ->(term) { skill_named(term) },
          'stat' => ->(term) { [ 'skill', skill_named(term) ] } }
      ].freeze

      def self.identify(term)
        wanted = term.to_s.strip.downcase

        row = NAMED.find { |candidate| candidate['match'].call(wanted) }

        row && row['stat'].call(wanted)
      end

      def self.titleize(term)
        term.to_s.split.map(&:capitalize).join(' ')
      end

      def self.skill_named(term)
        Global.read_config('pf2e_skills').keys.find { |name| name.casecmp?(term) }
      end

      # An attribute's contribution is typed `ability`, so the best one applies and no two stack. That
      # is what lets an effect offer a different attribute for a figure without anything special-casing
      # which attribute the figure "really" uses.
      #
      # Foundry slugs an attribute modifier with the attribute's short name (`modifiers.ts`), which is
      # what a rule adjusting one names, so ours are slugged the same way.
      def self.ability_mod(char, ability, source = nil)
        return nil unless ability

        { 'source' => source || ability, 'slug' => Domains.abbreviation(ability),
          'type' => Modifiers::ABILITY, 'value' => Pf2e.ability_mod(char, ability) }
      end

      LAND = 'land'.freeze

      # What a speed starts from. Land is the ancestry's; any other kind is whatever the ancestry gives,
      # or the best thing that granted one - a Ring of Swimming grants half the land speed.
      def self.speed_base(char, movement)
        kind = Domains.slug(movement || LAND)
        known = (char.pf2_movement || {})[kind].to_i

        return [ Pf2e.ancestry_speed(char), known ].max if kind == LAND

        granted = Rules.speeds(Effects.sources(char),
                               Effects.options(char, Domains.for('speed', kind)),
                               Effects.context(char))[kind]

        [ known, granted ? granted['value'].to_i : 0 ].max
      end

      def self.class_attribute(char, named)
        (named.is_a?(Hash) ? named['key_abil'] : nil) || char.combat&.key_abil || 'Strength'
      end

      def self.class_proficiency(char, named)
        (named.is_a?(Hash) ? named['prof'] : nil) || char.combat&.class_dc
      end

      def self.attack_abilities(attack)
        return [ 'Dexterity' ] if attack['ranged']

        Pf2e.has_trait?(attack['traits'], 'finesse') ? [ 'Strength', 'Dexterity' ] : [ 'Strength' ]
      end

      def self.item(value, source, slug = nil)
        return nil if value.to_i.zero?

        { 'source' => source, 'slug' => slug || Domains.slug(source), 'type' => 'item',
          'value' => value.to_i }
      end

      # The penalty for a second or third attack in a turn. Which attack it is comes from Foundry's own
      # option, `map:increases:1` for the second and `:2` for the third, so whatever counts a turn's
      # attacks says so and this does the arithmetic (`actor/helpers.ts` `calculateMAPs`): -5 and -10,
      # -4 and -8 for an agile weapon, or the least severe a rule offers - Agile Grace's -3 - doubled for
      # the third.
      def self.multiple_attack(kind, attack, sources, domains, held, context)
        return nil unless kind.to_s == 'attack' && attack.is_a?(Hash)

        increases = held.map { |one| one.to_s[/\Amap:increases:(\d+)\z/, 1] }.compact.map(&:to_i).max.to_i

        return nil unless increases.positive?

        traits = Array(attack['traits']).map { |one| Domains.slug(one) }
        base = traits.include?('agile') ? -4 : -5
        offered = Rules.gather(sources, domains, held + traits, 'MultipleAttackPenalty') do |row, source|
          Rules.contribute(row, source, context.merge('item' => source['item'] || {}))
        end
        each = ([ base ] + offered.map { |one| one['value'] }).max

        { 'source' => 'multiple attack penalty', 'slug' => 'multiple-attack-penalty',
          'type' => Modifiers::UNTYPED, 'value' => each * [ increases, 2 ].min }
      end

      # Their slug, because a feat that lets a character ignore armour's speed penalty names it
      # (`character/document.ts:933`). A character strong enough for the armour is slowed five feet
      # less by it, and never sped up.
      def self.armor_penalty(char)
        armor = Alterations.armor(char)
        penalty = armor ? armor.speed_penalty.to_i : 0
        penalty = [ penalty + 5, 0 ].min if armor && strong_enough?(char, armor)

        return nil if penalty.zero?

        { 'source' => armor.name, 'slug' => 'armor-speed-penalty', 'type' => Modifiers::UNTYPED,
          'value' => penalty, 'when' => [ { 'nor' => [ 'armor:ignore-speed-penalty' ] } ] }
      end

      # Armour hampers a Strength- or Dexterity-based skill until you are strong enough to wear it
      # (`character/document.ts:848`). Their predicate, unchanged: Acrobatics and Athletics are waived
      # by flexible armour as well as by strength, Stealth in noisy armour needs both, and a feat that
      # waives the penalty outright names it.
      ARMOR_SKILLS = %w{Strength Dexterity}.freeze
      NIMBLE = %w{Acrobatics Athletics}.freeze

      def self.armor_check_penalty(char, name)
        return nil unless ARMOR_SKILLS.include?(Pf2eSkills.get_linked_attr(name).to_s)

        armor = Alterations.armor(char)
        penalty = armor ? armor.check_penalty.to_i : 0

        return nil unless penalty.negative?

        { 'source' => armor.name, 'slug' => 'armor-check-penalty', 'type' => Modifiers::UNTYPED,
          'value' => penalty, 'when' => penalty_when(name, armor) }
      end

      def self.penalty_when(name, armor)
        waived = if NIMBLE.include?(Domains.slug(name).capitalize) || NIMBLE.include?(name.to_s)
                   { 'nor' => [ 'armor:strength-requirement-met', 'armor:trait:flexible' ] }
                 elsif name.to_s.casecmp?('Stealth') && noisy?(armor)
                   { 'nand' => [ 'armor:strength-requirement-met', 'armor:ignore-noisy-penalty' ] }
                 else
                   { 'not' => 'armor:strength-requirement-met' }
                 end

        # A predicate is a list of statements, all of which have to hold - which is how Foundry pushes
        # the second one onto the first.
        [ { 'nor' => %w{attack armor:ignore-check-penalty} }, waived ]
      end

      def self.noisy?(armor)
        Array(armor.traits).any? { |trait| Domains.slug(trait) == 'noisy' }
      end

      # Armour asks a minimum Strength of whoever wears it comfortably. This game's catalogue records
      # that as a score, so it is compared against one.
      def self.strong_enough?(char, armor)
        armor.min_str.to_i.positive? &&
          Pf2eAbilities.get_score(char, 'Strength').to_i >= armor.min_str.to_i
      end

      # This game's armour carries `potency` for AC and `power` for saves. The save rune is what the
      # rules call resilient, and `resilient` is the slug their data adjusts.
      RUNE_SLUGS = { 'potency' => 'armor-potency', 'power' => 'resilient' }.freeze

      # Read off the armour as an alteration leaves it: Magic Armor's rune is the one it counts.
      RUNE_FIELDS = { 'potency' => :potency, 'power' => :resilient }.freeze

      def self.rune(char, subtype)
        worn = Alterations.armor(char)

        item(worn ? worn.public_send(RUNE_FIELDS[subtype]) : 0, "#{subtype} rune", RUNE_SLUGS[subtype])
      end
    end
  end
end
