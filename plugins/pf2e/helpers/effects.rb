module AresMUSH
  module Pf2e

    # What a feat, an item or a condition does, gathered from whatever carries it.
    #
    # `grants:` already lets a feat declare what it gives you - a further feat, a training slot, a
    # proficiency. `rules:` is the same idea for the numbers: a list of rule elements in Foundry's own
    # vocabulary, described in `Pf2e::Rules`. The thing with the effect carries the effect, so nothing
    # in the engine has to know that Toughness exists.
    #
    # Two roots are available to a formula on a rule, and both are Foundry's. `@actor` is the
    # character - level and attribute modifiers, the facts that cannot themselves be modified without
    # circularity. `@item` is the thing carrying the rule: `@item.badge.value` is a condition's value,
    # which is how Frightened 3 is the same row as Frightened 1, and `@item.level` an item's level.
    #
    # An item may also declare circumstances of its own, with `grants_options:`, taken from its
    # RollOption rules. A Clandestine Cloak predicates its bonuses on `clandestine-cloak` and declares
    # that option itself, so wearing the cloak is enough and a player has nothing to say. What stays
    # conditional is what depends on the player: the action they are taking, or a fact about the check.
    module Effects

      def self.modifiers(sources, domains, context = {}, options = [])
        rows_of(sources, domains, context, options, 'FlatModifier')
      end

      def self.damage_dice(sources, domains, context = {}, options = [])
        rows_of(sources, domains, context, options, 'DamageDice')
      end

      # Every contribution of one kind that reaches a statistic with these domains, each carrying
      # whether its circumstances were met. An unmet row is reported rather than dropped, because
      # "you have a +2 here but only while picking a lock" is what a player wants to know.
      def self.rows_of(sources, domains, context, options, key)
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])
          own = context.merge('item' => source['item'] || {})

          Rules.of_kind(source, key).each_with_object([]) do |raw, out|
            # Resolved before the selector is matched, because a rule may name the item it sits on:
            # a rune that adds fire damage to *this* sword says `{item|id}-damage`, and the domain the
            # sword's damage declares is that id.
            row = Rules.resolved(raw, source, own)

            next unless row && Domains.matches?(Rules.selectors_of(row), domains)

            contribution = Rules.contribute(row, source, own)

            next unless contribution

            # Where it came from, so a one-off can tell whether the roll it helped was this one.
            out << contribution.merge('when' => row['predicate'],
                                      'met' => Predicate.test(row['predicate'], held),
                                      'origin' => (source['item'] || {})['id'])
          end
        end
      end

      # ------------------------------------------------------------------------------

      # Whatever carries a rule the actor is under: a character's conditions, feats, gear and effects, or a
      # creature's conditions, abilities and effects. Each actor answers for its own (`Pf2e::Actors`).
      def self.sources(char)
        Actors.of(char).sources
      end

      def self.sheet_sources(char)
        SheetReads.memo(char, :effect_sources) do
          conditions(char) + feats(char) + features(char) + actions(char) + items(char) + runes(char) +
            ActiveEffects.sources(char)
        end
      end

      # A source, with its rules held against what we implement. Checked here rather than where a row
      # is applied, because a kind nothing applies would otherwise never be looked at: the reader
      # filters to the kind it wants first, and a rule nobody wants is exactly the one to complain
      # about. Sources are assembled once per read block, so this says it once.
      # Its name is part of what its rules may read - a note titled `{item|name}` is titled with it.
      def self.source(name, rules, extras = {})
        Array(rules).each { |row| Rules.complain(name, row) }

        item = { 'name' => name }.merge(extras['item'] || {})

        { 'name' => name, 'rules' => rules }.merge(extras).merge('item' => item)
      end

      # What is true about the character, as the options a predicate is tested against. Foundry's own
      # spelling, so a predicate lifted from their data reads the same facts.
      # What is true of the character, for a statistic with these domains. A declared circumstance may be
      # about some statistics and not others, so the domains asking decide which of them hold; nothing
      # asking without domains sees a scoped one.
      def self.options(char, domains = nil)
        Actors.of(char).options(domains)
      end

      # What is true about the character whatever anyone has switched on. Kept apart from the switched-on
      # options because the store asks for these while working out what is switched on, and asking it
      # for its own answer would not terminate.
      def self.facts(char)
        Actors.of(char).facts
      end

      def self.sheet_facts(char)
        SheetReads.memo(char, :effect_facts) { build_facts(char) }
      end

      # What is true about the character, in Foundry's spelling, so a predicate copied from their data
      # reads the same facts.
      #
      # Every prefix here answers predicates that were in config and could never be met without it.
      # `heritage:`, `feat:`, `feature:`, `class:`, `skill:<name>:rank:<n>` and `proficiency:` are all
      # asked about by imported rules, and a predicate about a fact nobody supplies is a rule that is
      # read and does nothing - which is the failure this branch has hit more than once.
      def self.build_facts(char)
        with_traits(char, character_facts(char)) +
          armor_facts(char) +
          Size.facts(char) +
          named('self:condition', Pf2e.held_conditions(char).keys) +
          named('self:sense', granted_sense_names(char))
      end

      # What is true of the character without asking what they are under, or what the things they wear
      # have been made into. A grant's or an alteration's predicate is tested against these, because
      # which conditions a character has and what their armour counts as are themselves among the things
      # the full list of facts is built from.
      def self.character_facts(char)
        Actors.of(char).base_facts
      end

      def self.sheet_character_facts(char)
        SheetReads.memo(char, :character_facts) { build_character_facts(char) }
      end

      def self.build_character_facts(char)
        info = char.pf2_base_info || {}

        [ "self:level:#{char.pf2_level.to_i}" ] +
          named('self:trait', Array(char.pf2_traits)) +
          mode_facts(Array(char.pf2_traits)) +
          effect_facts(char) +
          named('heritage', [ info['heritage'] ]) +
          named('ancestry', [ info['ancestry'] ]) +
          named('class', [ info['charclass'] ]) +
          named('background', [ info['background'] ]) +
          named('feat', (char.pf2_feats || {}).values.flatten) +
          named('feature', (char.pf2_features || {}).values.flatten) +
          skill_facts(char) +
          proficiency_facts(char) +
          attribute_facts(char)
      end

      # The effects a character is under, as Foundry names them for a predicate: the effect's slug without
      # the `effect-`, `spell-effect-` or `stance-` it opens with, so Effect: Rage is `self:effect:rage` -
      # and with its counter after it where it has one (`abstract-effect/document.ts:121`). Reading these
      # asks nothing but which effects there are, so it is safe while anything else is being built.
      EFFECT_PREFIX = /\A(?:[a-z]+-)?(?:effect|stance)-/

      def self.effect_facts(char)
        ActiveEffects.on(char).flat_map do |effect|
          slug = Domains.slug(effect.name).sub(EFFECT_PREFIX, '')

          [ "self:effect:#{slug}", effect.badge ? "self:effect:#{slug}:#{effect.badge}" : nil ].compact
        end
      end

      # Undead, a construct, or living: what a predicate about a mode of being asks, from the traits
      # (`actor/base.ts` `modeOfBeing`).
      def self.mode_facts(traits)
        slugs = traits.map { |one| Domains.slug(one) }
        mode = if slugs.include?('undead') then 'undead'
               elsif slugs.include?('construct') then 'construct'
               else 'living'
               end

        [ "self:mode:#{mode}" ]
      end

      # The character's traits as their effects leave them: Humanoid Form makes them humanoid, Soul Thief
      # undead (`actor-traits.ts`). The traits and the mode of being they imply are replaced as a set,
      # because taking a trait away has to take its fact with it.
      def self.with_traits(char, facts)
        changes = Rules.contributions(sources(char), 'ActorTraits', facts)

        return facts if changes.empty?

        base = Array(char.pf2_traits).map { |one| Domains.slug(one) }
        traits = (base + changes.flat_map { |one| one['add'] }).uniq - changes.flat_map { |one| one['remove'] }

        facts.reject { |one| one.start_with?('self:trait:', 'self:mode:') } +
          named('self:trait', traits) + mode_facts(traits)
      end

      # What is true of the armour a character is wearing. Foundry's `armor:` options
      # (`character/document.ts:427`), which is what a rule about armour is written against: the
      # penalties armour carries are waived for a character strong enough to wear it, and a feat that
      # waives one of them says so by name.
      def self.armor_facts(char)
        armor = Alterations.armor(char)

        return [] unless armor

        [ Stat.strong_enough?(char, armor) ? 'armor:strength-requirement-met' : nil ].compact +
          named('armor:trait', Array(armor.traits)) +
          [ "armor:category:#{Domains.slug(armor.category)}" ]
      end

      # Read from the rules directly rather than through `senses`, because a sense's own predicate is
      # tested against these facts and asking for them while building them would not terminate.
      def self.granted_sense_names(char)
        Rules.of_kind_across(sources(char), 'Sense').map { |row| Domains.slug(row['selector']) }
      end

      # Senses something granted, as facts. A sense is not a figure, but the sheet shows it and a
      # predicate can ask about it - Moonlit Chain grants low-light vision only in moonlight.
      def self.senses(char)
        SheetReads.memo(char, :senses) do
          Rules.senses(sources(char), facts(char)).map do |one|
            one.merge('name' => one['sense'])
          end
        end
      end

      def self.named(prefix, values)
        Array(values).reject { |one| one.to_s.strip.empty? }
                     .map { |one| "#{prefix}:#{Domains.slug(one)}" }
      end

      # `skill:athletics:rank:4` is how a feat asks whether you are legendary in Athletics.
      def self.skill_facts(char)
        SheetReads.rows(char, :skills).flat_map do |skill|
          rank = Pf2e::Paths.rank_number(skill.prof_level)

          [ "skill:#{Domains.slug(skill.name)}:rank:#{rank}" ]
        end
      end

      def self.proficiency_facts(char)
        combat = char.combat

        return [] unless combat

        (combat.weapon_prof || {}).flat_map do |key, rank|
          [ "proficiency:#{Domains.slug(key)}:rank:#{Pf2e::Paths.rank_number(rank)}" ]
        end
      end

      def self.attribute_facts(char)
        Pf2e::ABILITIES.map do |ability|
          "attribute:#{Domains.abbreviation(ability)}:#{Pf2e.ability_mod(char, ability)}"
        end
      end

      # What a declaration on this source is tested against: the character's own facts and the source's.
      def self.options_of(char, source)
        facts(char) + Array(source['options'])
      end

      # A condition's value is its badge, which is Foundry's word for the number a condition carries.
      # Every condition the character has, including the ones another brought with it: a grabbed
      # character is off-guard, and Off-Guard's own rule is what lowers their AC.
      def self.conditions(char)
        Pf2e.held_conditions(char).map do |name, held|
          info = Global.read_config('pf2e_conditions', name)

          next nil unless info && info['rules']

          source(name, info['rules'],
                 'item' => { 'id' => Domains.slug(name),
                             'badge' => { 'value' => held['value'].to_i },
                             'level' => char.pf2_level.to_i })
        end.compact
      end

      # What a feat, a class feature or an action is: something the character does, whose toggles are off
      # until they say (`Rules`, RollOption).
      DOES = 'does'.freeze

      # A class feature's rules, from `pf2e_class_features.yml`, as a feat's are, and the character's
      # subclass's - a barbarian's instinct, a ranger's hunter's edge - which the catalogue files under the
      # class and subclass it is.
      def self.features(char)
        named = (char.pf2_features || {}).values.flatten.map { |one| feature_named(one.to_s) }
        names = (named + [ subclass_named(char) ]).compact.uniq

        names.map do |name|
          info = Global.read_config('pf2e_class_features', name)

          next nil unless info.is_a?(Hash) && info['rules']

          built = source(name, info['rules'], 'id' => Domains.slug(name), 'kind' => DOES,
                                              'item' => { 'level' => char.pf2_level.to_i },
                                              'chosen' => subclass_choice(char, name))

          with_selections(char, built)
        end.compact
      end

      # What a subclass's own question was answered with at chargen: which dragon a Dragon Instinct is.
      def self.subclass_choice(char, name)
        picked = (char.pf2_base_info || {})['specialize_info']

        name == subclass_named(char) && !picked.to_s.empty? ? [ picked ] + chosen_for(char, name) : nil
      end

      def self.subclass_named(char)
        info = char.pf2_base_info || {}

        return nil if info['specialize'].to_s.empty?

        (Global.read_config('pf2e_class_features') || {}).find do |_name, entry|
          entry.is_a?(Hash) && entry['charclass'] == info['charclass'] && entry['subclass'] == info['specialize']
        end&.first
      end

      # The rules of an action the character has of their own - Rage's +2 to melee damage while raging.
      # The basic actions everyone has are not anyone's to carry rules for.
      def self.actions(char)
        held = ((char.pf2_feats || {}).values.flatten + (char.pf2_features || {}).values.flatten +
                (char.respond_to?(:pf2_actions) ? (char.pf2_actions || {}).values_at('actions', 'reactions').flatten.compact : []))
               .map { |one| Domains.slug(feature_named(one.to_s)) }

        (Global.read_config('pf2e_actions') || {}).filter_map do |name, entry|
          next nil unless entry.is_a?(Hash) && entry['rules'] && entry['for'] != 'everyone' && held.include?(Domains.slug(name))

          with_selections(char, source(name, entry['rules'], 'id' => Domains.slug(name), 'kind' => DOES,
                                                             'item' => { 'level' => char.pf2_level.to_i }))
        end
      end

      # A class feature as the class tables grant it carries what it amounts to at that level - "Sneak
      # Attack 2d6", "Incredible Movement (+15 feet)", "Precise Strike 3 (3d6)" - where the catalogue
      # holds the one item that works that out for itself.
      def self.feature_named(granted)
        granted.sub(/\s*\(.*\)\z/, '').sub(/\s+\d+d\d+\z/, '').sub(/\s+\d+\z/, '').strip
      end

      def self.feats(char)
        (char.pf2_feats || {}).values.flatten.uniq.map do |name|
          info = Global.read_config('pf2e_feats', name)

          next nil unless info && info['rules']

          built = source(name, info['rules'],
                         'id' => Domains.slug(name), 'kind' => DOES, 'item' => { 'level' => char.pf2_level.to_i })

          with_selections(char, built)
        end.compact
      end

      # The answers to the choices a source asked for.
      #
      # A rule reads an answer by interpolating `{item|flags.system.rulesSelections.<flag>}`, which is
      # Foundry's own path, so the answer goes where that path looks for it. The answer itself is the
      # choice already recorded with the feat - `cg/feat` and `advance/feat` write it - so nothing new
      # stores it and a choice taken back goes with the feat.
      #
      # The sets are read in order, because one may ask whether another was answered: Bloodline
      # Mutation's second trait is asked only of someone who said they wanted a second trait. Nothing
      # here reads the character's facts, which are still being assembled when a source is built.
      def self.with_selections(char, built)
        sets = Rules.choice_sets(built)

        return built unless sets.any?

        # An effect carries the answers it was applied with; a feat's are recorded with the feat.
        chosen = built['chosen'] || chosen_for(char, built['name'])
        declared = Array(built['options']) + cast_from(built['chosen'])
        selections = {}

        # A set may ask something of the character - Azarim's choice is from 11th level - and what is
        # true of them without asking what they are under is safe to read while sources are gathered.
        known = character_facts(char)

        sets.each do |set|
          next unless Predicate.test(set['when'], known + declared)

          answer = answer_to(set, chosen, char)

          next unless answer

          selections[set['flag'].to_s] = answer if set['flag']
          declared += [ "#{set['roll_option']}:#{answer}" ] if set['roll_option']
        end

        built.merge('item' => (built['item'] || {}).merge(
                      'flags' => { 'system' => { 'rulesSelections' => selections } }),
                    'options' => declared)
      end

      # The tradition an effect was cast from, where it was applied saying so: `tradition primal`. Dragon
      # Form's resistance depends on the caster's tradition matching the dragon's.
      def self.cast_from(answers)
        Array(answers).map { |one| one.to_s[/\Atradition\s+(\w+)\z/i, 1] }.compact
                      .map { |tradition| "parent:spellcasting:tradition:#{tradition.downcase}" }
      end

      # An answer counts only if it is one this set could have offered, so a choice recorded against some
      # other question on the same feat does not read as an answer to this one.
      def self.answer_to(set, chosen, char = nil)
        # One of their own things is answered by its id, which is not a word to slug - or, for a feat whose
        # choice was recorded as a name, by the name of something they carry.
        if set['owned']
          return chosen.map(&:to_s).find { |one| Choices.includes?(set, one, char) } ||
                 chosen.map { |one| Choices.owned_answer(set, char, one) }.compact.first
        end

        # A listed choice records its own value for the answer, which may not be the answer's slug.
        return chosen.map { |one| Choices.listed_answer(set, one) }.compact.first if Array(set['choices']).any?

        chosen.map { |one| Domains.slug(one) }.find { |one| Choices.includes?(set, one) }
      end

      # Every choice recorded against this feat, at any level. `pf2_level_tracker` is the ledger's own view
      # of the choices a character made, rebuilt on every materialise, so a choice taken back is gone from
      # here too.
      def self.chosen_for(char, name)
        (char.pf2_level_tracker || {}).values.flat_map { |entry|
          Array((entry['feat_choices'] || {})[name])
        }.compact
      end

      # An item's effects come from the catalogue, the same way a feat's do, and only the rules that apply
      # given how the item is being carried: everything while it is worn or held and invested, and only
      # the rules that say they need no wearing while it is merely in a pack.
      #
      # Its id is its own, because a rule may name it - a rune that adds fire damage to *this* sword
      # says `{item|id}-damage`, and the sword's damage domains include exactly that.
      def self.items(char)
        worn = Pf2egear.effective_items(char).map { |_category, item| item.id.to_s }

        Pf2egear.carried_items(char).map do |category, item|
          info = Pf2egear.catalogue_entry(category, item) || {}
          rules = Array(info['rules'])

          rules = rules.reject { |row| Rules.needs_wearing?(row) } unless worn.include?(item.id.to_s)

          next nil if rules.empty?

          source(Pf2egear.get_item_name(item), rules,
                 'item' => { 'id' => item.id.to_s, '_id' => item.id.to_s, 'level' => item_level(item) },
                 'options' => item_options(item))
        end.compact
      end

      # The property runes etched on what a character is carrying, each as a source of its own.
      #
      # A rune is not an item: it is something done to one, and what it does belongs to the thing it is
      # etched on. So the source carries the *weapon's* id, which is what its rules name - a flaming
      # rune's fire is written against `{item|id}-damage` and reaches that weapon's damage and no other.
      def self.runes(char)
        Pf2egear.carried_items(char).flat_map do |_category, item|
          next [] unless item.respond_to?(:runes)

          Pf2egear.property_runes(item).map { |slug| rune_source(item, slug) }.compact
        end
      end

      def self.rune_source(item, slug)
        info = Pf2egear.rune_entry(slug)
        rules = Array(info && info['rules'])

        return nil if rules.empty?

        source(Pf2egear.rune_named(slug), rules,
               'item' => { 'id' => item.id.to_s, '_id' => item.id.to_s,
                           'level' => info['level'].to_i,
                           # `@item.baseDamage.dice` is what a shockwave rune's splash is worth.
                           'baseDamage' => { 'dice' => damage_dice_count(item) } },
               'options' => Array(info['traits']).map { |trait| "item:trait:#{Domains.slug(trait)}" })
      end

      # How many dice the weapon itself rolls: `2d6` is two, and `d8` is one.
      def self.damage_dice_count(item)
        found = item.respond_to?(:wp_damage) ? item.wp_damage.to_s.match(/\A(\d*)d/) : nil

        return 0 unless found

        found[1].empty? ? 1 : found[1].to_i
      end

      def self.item_level(item)
        item.respond_to?(:level) ? item.level.to_i : 0
      end

      def self.item_options(item)
        traits = item.respond_to?(:traits) ? Array(item.traits) : []

        [ "item:level:#{item_level(item)}" ] + traits.map { |trait| "item:trait:#{Domains.slug(trait)}" }
      end

      def self.context(char)
        Actors.of(char).context
      end

      def self.sheet_context(char)
        SheetReads.memo(char, :effect_context) { build_context(char) }
      end

      # What a formula on a rule may read about the character. Deliberately small: a figure that could
      # itself be modified has no place here, because reading it while assembling another one is how a
      # sheet render comes to depend on the order it happened to run in.
      def self.build_context(char)
        mods = Pf2e::ABILITIES.each_with_object({}) do |ability, out|
          out[Domains.abbreviation(ability)] = { 'mod' => Pf2e.ability_mod(char, ability) }
        end

        # The land speed is here because a granted speed is usually written as a fraction of it - a Ring
        # of Swimming gives half. Only the base is exposed, not the figure: a granted speed that read the
        # finished land speed would have to be assembled while the land speed was being assembled.
        #
        # Ranks are here because effects are written against them: Armored Stealth reduces the armour
        # penalty by your Stealth rank less one, and Specialty Crafting scales with Crafting. A rank is a
        # proficiency rather than a figure, so reading one assembles nothing.
        #
        # So are the counters a rule writes to `flags.system` for another to read: Rage's temporary hit
        # points are `@actor.flags.system.rageTempHP`.
        { 'actor' => { 'level' => char.pf2_level.to_i, 'abilities' => mods,
                       'flags' => { 'system' => Paths.flags(char) },
                       'system' => { 'movement' => { 'speeds' =>
                                       { 'land' => { 'value' => Pf2e.ancestry_speed(char) } } },
                                     'skills' => skill_ranks(char),
                                     'proficiencies' => { 'defenses' => armour_ranks(char) },
                                     'attributes' => { 'shield' => { 'ac' => shield_ac(char) } } } } }
      end

      def self.skill_ranks(char)
        SheetReads.rows(char, :skills).each_with_object({}) do |skill, out|
          out[Domains.slug(skill.name)] = { 'rank' => Paths.rank_number(skill.prof_level) }
        end
      end

      def self.armour_ranks(char)
        (char.combat&.armor_prof || {}).each_with_object({}) do |(category, rank), out|
          out[Domains.slug(category)] = { 'rank' => Paths.rank_number(rank) }
        end
      end

      def self.shield_ac(char)
        Pf2eCombat.get_equipped_shield(char)&.ac_bonus.to_i
      end

      def self.for_stat(char, kind, name = nil, ability = nil, options = [])
        modifiers(sources(char), Domains.for(kind, name, ability), context(char),
                  options(char) + Array(options))
      end
    end
  end
end
