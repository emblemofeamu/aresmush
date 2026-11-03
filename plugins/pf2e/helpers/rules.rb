module AresMUSH
  module Pf2e

    # The rule elements we implement, spelled the way Foundry spells them.
    #
    # A feat, an item or a condition carries a `rules:` list, and each row is a rule element: a `key`
    # naming what kind it is, a `selector` naming the domains it reaches, a `value`, and a `predicate`
    # saying when it applies. Those are Foundry's own field names, so a row lifted out of their packs
    # is copied rather than translated - which is the point, since their system is the reference
    # implementation of this game's mechanics and a translation is a place to introduce an error.
    #
    #   rules:
    #     - key: FlatModifier
    #       selector: hp
    #       value: "@actor.level"                # Toughness
    #     - key: FlatModifier
    #       selector: [ cha-based, int-based, wis-based ]
    #       type: status
    #       value: "-@item.badge.value"          # Stupefied, scaled by the condition's own value
    #     - key: DamageDice
    #       selector: strike-damage
    #       diceNumber: 1
    #       dieSize: d6
    #       damageType: fire
    #
    # Foundry ships 42 kinds. A row whose kind is not in the table below is refused rather than
    # ignored: an effect nobody applies is a sheet that is quietly wrong, and the import that wrote
    # these rows refuses the same kinds for the same reason.
    module Rules

      # A row's `slug` is the name other rules call it by: `AdjustModifier` names the modifier it
      # changes, and their data names ours as well as its own - `resilient`, `armor-check-penalty`,
      # `weapon-potency`. A row that does not say is slugged from whatever carries it.
      #
      # `value` and `diceNumber` are read by `Pf2e::Formula`, `predicate` by `Pf2e::Predicate`. Every
      # other field is taken as it stands.
      FORMULA_FIELDS = %w{value diceNumber}.freeze

      KINDS = [
        {
          'key' => 'FlatModifier',
          'fields' => %w{key selector value type ability min max damageType damageCategory critical
                         predicate slug label requiresEquipped removeAfterRoll},
          # A number added to whatever the selector reaches, obeying the stacking rule for its type.
          #
          # `min` and `max` clamp it, which is how a bonus that scales with something says how far it
          # goes. `damageType` makes it a bonus to one kind of damage rather than to the whole roll.
          # `removeAfterRoll` makes it a one-off: Guidance's +1 is spent on the roll it helps, and
          # `Pf2e::ActiveEffects.after_roll` ends the effect that carried it.
          'contribute' => lambda { |row, source, context|
            { 'source' => row['ability'] ? row['ability'].to_s.capitalize : source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'type' => (row['type'] || Modifiers::UNTYPED).to_s.downcase,
              'value' => clamp(Formula.value(row['value'], context), row),
              'damage_type' => row['damageType'],
              'category' => row['damageCategory'],
              'critical' => row['critical'],
              'remove_after_roll' => row['removeAfterRoll'] }
          }
        },
        {
          'key' => 'Note',
          'fields' => %w{key selector text title predicate outcome slug label},
          # Text shown with a roll, and only for the outcomes it names: Revel in Retribution reminds you of
          # its effect on a hit. The importer translates their localisation keys, so this is the English.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'title' => row['title'] || source['name'],
              'text' => row['text'].to_s,
              'outcome' => Array(row['outcome']) }
          }
        },
        {
          'key' => 'RollTwice',
          'fields' => %w{key selector keep predicate removeAfterRoll slug label},
          # Fortune and misfortune: the d20 is rolled twice and the higher or the lower kept. One of each
          # cancels, which is the rule (`rules/helpers.ts` `extractRollTwice`).
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'keep' => row['keep'].to_s,
              'selectors' => selectors_of(row),
              'predicate' => row['predicate'],
              'remove_after_roll' => row['removeAfterRoll'] }
          }
        },
        {
          'key' => 'DamageDice',
          'fields' => %w{key selector diceNumber dieSize damageType category critical predicate slug
                         label override tags},
          # Dice added to a damage roll. `category` separates persistent, precision and splash damage,
          # which are rolled and applied apart from the rest. An `override` changes the weapon's own
          # dice instead of adding any - Vicious Incisors makes the jaws a d6 - and is what the damage
          # reader takes such a row out by.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'dice' => Formula.value(row['diceNumber'] || 1, context),
              'die' => row['dieSize'],
              'damage_type' => row['damageType'],
              'category' => row['category'],
              'critical' => row['critical'],
              'override' => row['override'] }
          }
        },
        {
          'key' => 'RollOption',
          'fields' => %w{key option domain toggleable value predicate label slug suboptions selection
                         alwaysActive disabledIf disabledValue requiresEquipped},
          # Declares a circumstance rather than a number. A rule on the same feat or item is then
          # predicated on it - a Clandestine Cloak declares `clandestine-cloak` and predicates its own
          # bonuses on it - so this contributes an option, not a modifier.
          #
          # `value` decides whether it holds without being asked for. Foundry defaults a toggleable one
          # to off and everything else to on; here an item's toggle is on unless they turn it off,
          # because an item you are wearing should do what it says. A toggle on a feat, a class feature
          # or an action is something done at a moment - Nimble Dodge, a finisher, a spellshape - and
          # is off until the player says, as Foundry has it.
          #
          # Except where the circumstance is about someone else. A declaration marked `totm` - Foundry's
          # own marker for what only the table knows - or one naming a fact about the target is off until
          # the player says it holds: "your weapon counts as ghost touch against something incorporeal"
          # must not read as "against everything".
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'option' => row['option'],
              'domain' => row['domain'] || Domains::ALL,
              'label' => row['label'],
              # A choice among values: a wand set to fire, a gem twisted to frost. Rules are predicated
              # on `<option>:<value>`, so the option holds twice - once bare and once with the choice.
              'choices' => choices_of(row),
              'selection' => row['selection'],
              # A toggle something else locks. While `locked_when` holds, the option reads as
              # `locked_to` whatever the player said - a stance you cannot leave, a rune you cannot turn off.
              'locked_when' => row['disabledIf'],
              'locked_to' => row['disabledValue'],
              'default' => row['value'].nil? ? !about_target?(row) && !done_at_a_moment?(row, source) : truthy(row['value'], context) }
          }
        },
        {
          'key' => 'ActiveEffectLike',
          'fields' => %w{key path mode value predicate slug label merge},
          # Writes a value rather than adding a modifier: a feat that makes you trained in a skill, a
          # counter another rule's predicate asks about. `Pf2e::Paths` says which paths may be written
          # and what each mode does; a path it does not know is refused there.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'path' => row['path'],
              'mode' => row['mode'].to_s,
              'value' => writable_value(row['value'], context) }
          }
        },
        {
          'key' => 'ChoiceSet',
          'fields' => %w{key choices flag prompt rollOption predicate allowNoSelection slug label},
          # Asks the player to choose, and other rules on the same thing read the answer: a Charm of
          # Resistance asks which kind of damage it resists and its Resistance rule reads that choice.
          #
          # The answer is not stored here. A feat's choice is already recorded with the feat - it is what
          # `cg/feat` and `advance/feat` write - so this says where the answer belongs and what the
          # answers may be, and `Pf2e::Effects` reads the one the character made.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'flag' => row['flag'],
              'roll_option' => row['rollOption'],
              'choices' => choices_of_set(row),
              'vocabulary' => query_of(row)['config'],
              'filter' => query_of(row)['filter'],
              'item_type' => query_of(row)['itemType'],
              'when' => row['predicate'],
              # What a candidate answer has to satisfy, which is how "any skill you are untrained in"
              # is written: the set's own predicate, tested once per answer with `{choice|value}` filled
              # in (`choice-set/rule-element.ts` `#choicesFromPath`).
              'each' => query_of(row)['predicate'],
              # One of the character's own things, by kind: "the weapon you choose".
              'owned' => query_of(row)['ownedItems'] ? Array(query_of(row)['types']) : nil,
              'handwraps' => query_of(row)['includeHandwraps'] == true }
          }
        },
        {
          'key' => 'MartialProficiency',
          'fields' => %w{key slug definition sameAs maxRank label},
          # "Your proficiency with weapons like this is the same as your <sameAs> proficiency." Goblin
          # Weapon Familiarity makes martial goblin weapons count as simple; Monastic Weaponry makes monk
          # weapons count as your unarmed proficiency, up to master.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'definition' => row['definition'],
              'same_as' => Domains.slug(row['sameAs']),
              'max_rank' => row['maxRank'] }
          }
        },
        {
          'key' => 'CriticalSpecialization',
          'fields' => %w{key predicate slug label},
          # Grants the critical specialisation effect for the attacks its predicate describes. It carries
          # no value: whether it applies is the whole of it.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'definition' => row['predicate'] }
          }
        },
        {
          'key' => 'Sense',
          'fields' => %w{key selector acuity range predicate slug label},
          # A sense the character would not otherwise have: darkvision from a blindfold, low-light vision
          # from a cat's eyes. Not a figure, but a fact the sheet shows and a predicate can ask about.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'sense' => Domains.slug(row['selector']),
              'acuity' => row['acuity'],
              'range' => row['range'] }
          }
        },
        {
          'key' => 'DamageAlteration',
          'fields' => %w{key property mode value selectors selector predicate slug label requiresEquipped},
          # Changes a damage roll after it is built rather than adding to it: the kind of damage it
          # deals, how many dice, or how large they are.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'property' => Domains.slug(row['property']),
              'mode' => row['mode'].to_s,
              'value' => alteration_value(row['value'], context) }
          }
        },
        {
          'key' => 'Strike',
          'fields' => %w{key slug label category group baseType damage traits otherTags range
                         predicate fist replaceAll},
          # An attack the character would not otherwise have: a shield's lion head, a torch swung as a
          # club, the claws a stance grants. It becomes an unarmed-style attack, described the same way
          # a catalogue weapon is, so everything that reads an attack reads this one too. `replaceAll`
          # makes it the only attack there is while it lasts: "the only Strikes you can make are...".
          'contribute' => lambda { |row, source, _context|
            base = (row['damage'] || {})['base'] || {}

            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(row['label'] || source['name']),
              'name' => row['label'] || source['name'],
              'category' => row['category'],
              'group' => row['group'],
              'base' => row['baseType'] || Domains.slug(row['label'] || source['name']),
              'traits' => Array(row['traits']),
              'dice' => base['dice'] || 1,
              'die' => base['die'],
              'damage_type' => base['damageType'],
              'range' => row['range'],
              'replace_all' => row['replaceAll'] == true }
          }
        },
        {
          'key' => 'AdjustStrike',
          'fields' => %w{key property mode value definition predicate slug label},
          # Changes an attack rather than the roll: adds a trait to it. A trait is not decoration - a
          # weapon that gains `finesse` may be attacked with Dexterity and one that gains `thrown` adds
          # Strength to its damage - so the trait is what this reads and the other properties it can
          # change are refused at import.
          #
          # `definition` says which attack, tested against that attack's own options rather than the
          # character's.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'property' => Domains.slug(row['property']),
              'mode' => row['mode'].to_s,
              'value' => row['value'],
              'definition' => row['definition'] }
          }
        },
        {
          'key' => 'BaseSpeed',
          'fields' => %w{key selector value predicate slug label},
          # A speed of a kind the character would not otherwise have, or a better one: a Ring of
          # Swimming gives a swim speed of half their land speed. `selector` is the kind of movement,
          # and the highest candidate is the one that counts.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'movement' => Domains.slug(row['selector']),
              'value' => Formula.value(row['value'], context) }
          }
        },
        {
          'key' => 'AdjustModifier',
          'fields' => %w{key selector selectors slug mode value suppress relabel damageType
                         maxApplications predicate label requiresEquipped},
          # Changes a modifier that already exists rather than adding one: Intimidating Prowess raises
          # the Strength modifier on Intimidation, and a feat that says you need no crowbar suppresses
          # the penalty for not having one.
          #
          # A row with no slug adjusts *every* modifier the selector reaches
          # (`rules/helpers.ts:47`), which is why the slug is carried as nil rather than defaulted.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'slug' => row['slug'],
              'mode' => (row['suppress'] ? 'override' : row['mode']).to_s,
              'value' => row['value'] ? Formula.value(row['value'], context) : nil,
              'suppress' => !!row['suppress'],
              'relabel' => row['relabel'],
              'max' => row['maxApplications'] }
          }
        },
        {
          'key' => 'AdjustDegreeOfSuccess',
          'fields' => %w{key selector adjustment predicate type slug label},
          # Turns one outcome into another: Assurance makes a failure a success, Deafened drops an
          # auditory Perception check to a critical failure. `Pf2e::Degree` applies it.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'],
              'slug' => row['slug'] || Domains.slug(source['name']),
              'adjustment' => row['adjustment'],
              'check' => row['type'] }
          }
        },
        {
          'key' => 'ItemAlteration',
          'fields' => %w{key itemType itemId mode property value predicate slug label},
          # Changes one of the character's things while an effect lasts, rather than a figure: Magic
          # Weapon's runes, a spell making armour cold iron. `Pf2e::Alterations` applies it to what an
          # attack, the worn armour or a condition's value is read as.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'], 'item_type' => row['itemType'], 'item_id' => row['itemId'],
              'property' => row['property'], 'mode' => row['mode'], 'value' => row['value'] }
          }
        },
        {
          'key' => 'FastHealing',
          'fields' => %w{key value type details deactivatedBy predicate slug label},
          # Hit points regained as each of the character's turns starts. Regeneration is the same, except
          # that damage of the kinds it names switches it off until their next turn (`fast-healing.ts`).
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'],
              'value' => Formula.value(row['value'], context).to_i,
              'type' => (row['type'] || 'fast-healing').to_s,
              'deactivated_by' => Array(row['deactivatedBy']),
              'details' => row['details'] }
          }
        },
        {
          'key' => 'ActorTraits',
          'fields' => %w{key add remove predicate slug label},
          # Traits an effect gives or takes away while it lasts, as the facts a predicate reads.
          'contribute' => lambda { |row, source, _context|
            { 'source' => source['name'], 'add' => Array(row['add']).map { |one| Domains.slug(one) },
              'remove' => Array(row['remove']).map { |one| Domains.slug(one) } }
          }
        },
        {
          'key' => 'DexterityModifierCap',
          'fields' => %w{key value predicate slug label},
          # The most Dexterity counts towards AC. The lowest cap from anywhere holds, armour's included.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'], 'value' => Formula.value(row['value'], context).to_i }
          }
        },
        {
          'key' => 'LoseHitPoints',
          'fields' => %w{key value recoverable reevaluateOnUpdate predicate slug label},
          # Hit points lost as the effect begins; where it says they are not recoverable, they cannot be
          # healed while it lasts. One reevaluated on update loses more as its value rises - Drained.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'], 'value' => Formula.value(row['value'], context).to_i.abs,
              'recoverable' => row['recoverable'] != false, 'again' => row['reevaluateOnUpdate'] == true }
          }
        },
        {
          'key' => 'SubstituteRoll',
          'fields' => %w{key selector value required effectType removeAfterRoll predicate slug label},
          # A fixed number in place of the d20 - Assurance's 10 - chosen by the roller unless it is required.
          # It is fortune or misfortune, and cancels with the other the way rolling twice does.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'], 'slug' => row['slug'] || Domains.slug(source['name']),
              'value' => Formula.value(row['value'], context).to_i.clamp(1, 20),
              'required' => row['required'] == true,
              'effect_type' => (row['effectType'] || 'fortune').to_s,
              'remove_after_roll' => row['removeAfterRoll'] }
          }
        },
        {
          'key' => 'MultipleAttackPenalty',
          'fields' => %w{key selector value predicate slug label},
          # A multiple attack penalty other than the usual, for the second attack; the third is twice it.
          'contribute' => lambda { |row, source, context|
            { 'source' => source['name'], 'value' => Formula.value(row['value'], context).to_i }
          }
        },
        {
          'key' => 'CreatureSize',
          'fields' => %w{key value reach maximumSize minimumSize predicate slug label},
          # A size by name or one step up or down; `Pf2e::Size` reads it.
          'contribute' => lambda { |row, source, _context| row.merge('source' => source['name']) }
        },
        {
          'key' => 'Aura',
          'fields' => %w{key radius slug traits effects predicate level label},
          # An emanation putting effects on whoever is inside it; `Pf2e::Auras` reads it.
          'contribute' => lambda { |row, source, _context| row.merge('source' => source['name']) }
        },
        {
          'key' => 'BattleForm',
          'fields' => %w{key overrides brackets predicate ownUnarmed value slug label},
          # A polymorph; `Pf2e::BattleForms` reads it.
          'contribute' => lambda { |row, source, _context| row.merge('source' => source['name']) }
        },
        {
          'key' => 'TempHP',
          'fields' => %w{key value predicate events slug label},
          # Temporary hit points an effect gives: when it begins, and again at the start of each turn
          # where it says so. They do not stack - the better of what is held and what is given - and
          # they go when the effect that gave them does (`rule-element/temp-hp.ts`).
          'contribute' => lambda { |row, source, context|
            events = row['events'] || {}

            { 'source' => source['name'],
              'value' => Formula.value(row['value'], context).to_i,
              'on_create' => events['onCreate'] != false,
              'on_turn_start' => events['onTurnStart'] == true }
          }
        },
        {
          'key' => 'GrantItem',
          'fields' => %w{key uuid inMemoryOnly predicate onDeleteActions allowDuplicate alterations slug
                         label},
          # Brings another condition or effect with it: Grabbed makes you off-guard, Dying unconscious.
          # What becomes of the granted one is the grant's to say, and `Pf2e::Grants` reads it -
          # conditions through `Pf2e.held_conditions`, effects through `Pf2e::ActiveEffects`.
          'contribute' => lambda { |row, source, _context|
            read = Grants.read(row)

            read && read.merge('source' => source['name'])
          }
        },
        {
          'key' => 'Immunity',
          'fields' => %w{key type value predicate label definition exceptions slug},
          'contribute' => lambda { |row, source, context| declaration_of(row, source, context) }
        },
        {
          'key' => 'Weakness',
          'fields' => %w{key type value predicate label definition exceptions slug},
          'contribute' => lambda { |row, source, context| declaration_of(row, source, context) }
        },
        {
          'key' => 'Resistance',
          'fields' => %w{key type value predicate label definition exceptions slug doubleVs},
          'contribute' => lambda { |row, source, context| declaration_of(row, source, context) }
        }
      ].freeze

      # Fields that position a toggle in Foundry's character sheet. They are neither read nor complained
      # about: a field we ignore that changes the mechanics is a sheet that is quietly wrong, and one
      # that describes where a control sits in an interface we do not have is neither.
      # `placement` and `mergeable` position a toggle in Foundry's character sheet. `phase` and `priority`
      # order a rule against their data-preparation passes, which have no counterpart here: ours are
      # ordered by mode where order matters and by when they are asked for otherwise. `hideIfDisabled`
      # keeps a modifier that is not applying off their sheet; a breakdown here lists it as conditional
      # instead, so a player can see what they would need to claim it.
      PRESENTATION = { 'RollOption' => %w{placement mergeable phase priority},
                       'ActiveEffectLike' => %w{phase priority},
                       'AdjustModifier' => %w{priority},
                       'FlatModifier' => %w{hideIfDisabled phase priority},
                       'DamageDice' => %w{hideIfDisabled phase priority},
                       'AdjustStrike' => %w{phase priority},
                       'DamageAlteration' => %w{phase priority},
                       'ChoiceSet' => %w{adjustName allowedDrops priority},
                       'Strike' => %w{img},
                       'GrantItem' => %w{priority},
                       'Note' => %w{visibility priority},
                       'ItemAlteration' => %w{priority phase fromEquipment},
                       'CreatureSize' => %w{resizeEquipment},
                       'ActorTraits' => %w{priority},
                       'Aura' => %w{appearance priority mergeExisting},
                       'BattleForm' => %w{hasHands canCast} }.freeze

      BY_KEY = KINDS.each_with_object({}) { |row, out| out[row['key']] = row }.freeze

      # A RollOption's `value` is a boolean or a formula, not a number: `true` and `false` mean what they
      # say, and anything else is read as arithmetic and true when it comes to something other than zero.
      # An option that says nothing is on, which is this game's default rather than Foundry's.
      # A written value may be a flag, a word or a number. Only a number goes through the formula reader;
      # anything else is what it says, since `override` writes words and flags as readily as numbers.
      def self.writable_value(value, context)
        return value unless value.is_a?(Numeric) || value.is_a?(String)
        return value unless value.is_a?(Numeric) || value.match?(/[\d@(]/)

        Formula.value(value, context)
      rescue StandardError
        value
      end

      # Only suboptions that say what they are. Their data has a few whose list is a string, which reads
      # as a list of single letters and means nothing.
      # A set that describes its answers rather than listing them: a vocabulary to pick from, or a filter
      # over a catalogue. `Pf2e::Choices` resolves either.
      def self.query_of(row)
        row['choices'].is_a?(Hash) ? row['choices'] : {}
      end

      # A set that lists its answers outright.
      # A listed answer may be an item by its compendium link - which variety of oil this is - and then
      # the answer is that item's slug, which is what Foundry's option for it names
      # (`oil-of-potency:oil-of-potency-greater`).
      def self.choices_of_set(row)
        Array(row['choices']).select { |one| one.is_a?(Hash) && one['value'] }
                             .map { |one| { 'value' => answer_value(one['value']), 'label' => one['label'],
                                            'when' => one['predicate'] } }
      end

      def self.answer_value(value)
        return value if value.is_a?(Hash)

        found = Grants::UUID.match(value.to_s)

        found ? Domains.slug(found[2]) : value.to_s
      end

      # Every choice a source asks the character to make.
      def self.choice_sets(source)
        of_kind(source, 'ChoiceSet').map { |row| contribute(row, source, {}) }.compact
      end

      def self.choices_of(row)
        Array(row['suboptions']).select { |one| one.is_a?(Hash) && one['value'] }
                                .map { |one| { 'value' => one['value'].to_s, 'label' => one['label'] } }
      end

      # Whether a declaration is about the target rather than about the character.
      TABLE_ONLY = 'totm'.freeze

      def self.about_target?(row)
        row['toggleable'].to_s == TABLE_ONLY || row['option'].to_s.start_with?('target:')
      end

      def self.done_at_a_moment?(row, source)
        row['toggleable'] && source['kind'] == Effects::DOES
      end

      def self.truthy(value, context)
        return true if value.nil?
        return value if value == true || value == false

        !Formula.value(value, context).to_i.zero?
      rescue StandardError
        false
      end

      def self.clamp(value, row)
        low = row['min'] ? Formula.value(row['min']) : nil
        high = row['max'] ? Formula.value(row['max']) : nil

        value = [ value, low ].max if low
        value = [ value, high ].min if high

        value
      end

      # An immunity, a weakness or a resistance: a kind of thing and, for the latter two, how much of it.
      def self.declaration_of(row, source, context)
        { 'source' => source['name'],
          'slug' => row['slug'] || Domains.slug(source['name']),
          'type' => row['type'],
          # A resistance may describe what it resists rather than naming a kind: Sacred Defender resists
          # physical damage from an unholy source. Tested against the damage's own facts.
          'definition' => row['definition'],
          'value' => row['value'] ? Formula.value(row['value'], context) : nil }
      end

      # Every declaration of a kind whose circumstances are met. Neither a modifier nor a write, so it
      # has no selector and no stacking: `Pf2e::IWR` decides which of them wins.
      def self.declarations(sources, options, key, context = {})
        return [] unless known?(key)

        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, key).select { |row| Predicate.test(row['predicate'], held) }
                              .map { |row| contribute(row, source, context) }
                              .compact
        end
      end

      # Everything an effect writes, in the order the modes are meant to run: a multiply before an add,
      # and an override last, so an override wins whatever else said (`ae-like.ts`).
      MODE_ORDER = %w{multiply add subtract remove downgrade upgrade override}.freeze

      def self.writes(sources, options, context = {})
        gathered = Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'ActiveEffectLike')
            .select { |row| Predicate.test(row['predicate'], held) }
            .map { |row| contribute(row, source, context) }
            .compact
        end

        gathered.select { |write| Paths.writable?(write['path']) }
                .sort_by { |write| MODE_ORDER.index(write['mode']) || MODE_ORDER.size }
      end

      # Rules that change how a check turned out. A row may restrict itself to a kind of check - a save
      # or a skill - which the check itself declares as `check:type:…`, so the restriction is read the
      # same way any other circumstance is.
      CHECK_TYPES = { 'save' => 'saving-throw', 'skill' => 'skill', 'perception' => 'perception',
                      'attack' => 'attack-roll' }.freeze

      def self.adjustments(sources, domains, options)
        gather(sources, domains, options, 'AdjustDegreeOfSuccess') do |row|
          wanted = CHECK_TYPES[row['type'].to_s] || row['type']

          next nil if row['type'] && !Array(options).include?("check:type:#{wanted}")

          row['adjustment']
        end
      end

      # A value on a damage alteration is a kind of damage, a number, or nothing at all - `dice-faces`
      # with no value means "one step larger".
      def self.alteration_value(value, context)
        return nil if value.nil?
        return value unless value.is_a?(Numeric) || value.to_s.match?(/\A[-\d@(]/)

        Formula.value(value, context)
      rescue StandardError
        value
      end

      # Proficiencies a feat gives over a kind of weapon, each capped where it says.
      def self.martial_proficiencies(sources, options)
        declarations(sources, options, 'MartialProficiency')
      end

      # Whether anything grants the critical specialisation effect for an attack.
      #
      # The predicate is about the weapon as much as the character - "monk weapons, if you have Expert
      # Strikes" - so it is tested once against both sets of facts rather than filtered against the
      # character's first.
      def self.critical_specialization?(sources, options, attack_options)
        Array(sources).any? do |source|
          held = Array(options) + Array(source['options']) + Array(attack_options)

          of_kind(source, 'CriticalSpecialization').any? { |row| Predicate.test(row['predicate'], held) }
        end
      end

      def self.senses(sources, options)
        declarations(sources, options, 'Sense')
      end

      # Alterations to a damage roll that reaches these domains.
      def self.damage_alterations(sources, domains, options, context = {})
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'DamageAlteration')
            .filter_map { |row| resolved(row, source, context) }
            .select { |row| Domains.matches?(selectors_of(row), domains) }
            .select { |row| Predicate.test(row['predicate'], held) }
            .map { |row| contribute(row, source, context) }
            .compact
        end
      end

      # Attacks something granted the character. Each is described the way a catalogue weapon is, so
      # nothing that reads an attack has to know it came from a rule.
      def self.strikes(sources, options)
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'Strike').select { |row| Predicate.test(row['predicate'], held) }
                                   .map { |row| contribute(row, source, {}) }
                                   .compact
        end
      end

      # Traits an effect adds to an attack. `definition` is a predicate over the attack's own options, so a
      # rune reaches the weapon it is on and a feat reaches every weapon of a base type.
      # What an `AdjustStrike` can change about an attack, and what each of them is on the descriptor.
      # A trait changes numbers - `finesse` lets Dexterity attack with it, `thrown` adds Strength to its
      # damage - a material and a property rune are what the attack counts as, and a range increment is
      # how far it reaches.
      STRIKE_PROPERTIES = { 'traits' => 'traits', 'weapon-traits' => 'traits',
                            'property-runes' => 'runes', 'materials' => 'materials',
                            'range-increment' => 'range' }.freeze

      # Which of those is a list of words rather than a number.
      STRIKE_LISTS = %w{traits runes materials}.freeze

      # Every change to this attack whose circumstances are met. `definition` says which attacks a rule
      # is about, and is tested against that attack's own facts rather than the character's.
      def self.strike_adjustments(sources, options, attack_options)
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'AdjustStrike')
            .select { |row| Predicate.test(row['predicate'], held) }
            .map { |row| contribute(row, source, {}) }
            .compact
            .select { |one| STRIKE_PROPERTIES.key?(one['property']) }
            .select { |one| Predicate.test(one['definition'], attack_options) }
        end
      end

      # Speeds a character has because something gave them one, by kind of movement. The highest for a
      # kind wins, which is Foundry's own rule (`creature/document.ts` `selectCandidate`) - two rings
      # that both grant a swim speed are the better swim speed, not the sum.
      def self.speeds(sources, options, context = {})
        gathered = Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'BaseSpeed').select { |row| Predicate.test(row['predicate'], held) }
                                      .map { |row| contribute(row, source, context) }
                                      .compact
        end

        gathered.group_by { |one| one['movement'] }
                .transform_values { |ones| ones.max_by { |one| one['value'].to_i } }
      end

      # Rules that change a modifier that already exists. A row naming several selectors reaches a
      # statistic answering to any of them, which is why `selectors` is read alongside `selector`.
      def self.modifier_adjustments(sources, domains, options, context = {})
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, 'AdjustModifier')
            .filter_map { |row| resolved(row, source, context) }
            .select { |row| Domains.matches?(selectors_of(row), domains) }
            .map { |row| contribute(row, source, context)&.merge('when' => row['predicate'],
                                                                 'held' => held) }
            .compact
        end
      end

      # Every contribution of a kind whose circumstances hold, each worked out against the thing it came
      # from - an effect's rank, an item's level - for a kind that reaches no statistic.
      def self.contributions(sources, key, options, context = {})
        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, key).select { |row| Predicate.test(row['predicate'], held) }
                              .map { |row| contribute(row, source, context.merge('item' => source['item'] || {})) }
                              .compact
        end
      end

      def self.selectors_of(row)
        Array(row['selector']) + Array(row['selectors'])
      end

      # Text to show with a roll, whatever the outcome; `Pf2e::Check#notes` keeps the ones for the
      # outcome it came to.
      def self.notes(sources, domains, options)
        gather(sources, domains, options, 'Note') { |row, source| contribute(row, source, {}) }
      end

      # Whether this roll is rolled twice, and which is kept: `keep-higher`, `keep-lower`, or nil where
      # nothing says so or where fortune and misfortune cancel.
      def self.roll_twice(sources, domains, options)
        keeps = gather(sources, domains, options, 'RollTwice') { |row, source| contribute(row, source, {}) }
                  .map { |one| one['keep'] }.uniq

        return nil if keeps.empty? || keeps.size > 1

        "keep-#{keeps.first}"
      end

      # Every row of a kind that reaches these domains and whose circumstances are met, as whatever the
      # block makes of it. The kinds above are read here rather than through `Effects.rows_of` because
      # they contribute neither a modifier nor dice: there is nothing to stack.
      def self.gather(sources, domains, options, key)
        return [] unless known?(key)

        Array(sources).flat_map do |source|
          held = Array(options) + Array(source['options'])

          of_kind(source, key).filter_map { |row| resolved(row, source, {}) }
                              .select { |row| Domains.matches?(selectors_of(row), domains) }
                              .select { |row| Predicate.test(row['predicate'], held) }
                              .map { |row| yield(row, source) }
                              .compact
        end
      end

      def self.known?(key)
        BY_KEY.key?(key.to_s)
      end

      # Every row of a kind across every source, whether or not its circumstances are met. For the one
      # case that needs the unconditional list: a sense's own predicate is tested against the character's
      # facts, and the senses are among those facts.
      def self.of_kind_across(sources, key)
        Array(sources).flat_map { |source| of_kind(source, key) }
      end

      # The rows of one kind that a source carries, whatever else it carries.
      def self.of_kind(source, key)
        Array(source['rules']).select { |row| row['key'].to_s == key.to_s }
      end

      # What this row is worth - or nil when its kind is one we do not implement, or when it names a
      # choice nobody has made.
      def self.contribute(row, source, context)
        kind = BY_KEY[row['key'].to_s]

        return nil unless kind

        filled = resolved(row, source, context)

        filled && kind['contribute'].call(filled, source, context)
      end

      # What a rule may name by interpolation rather than outright: a charm resists the kind of damage
      # its wearer chose, a feat trains the skill its taker named. The choice lives where Foundry's own
      # path says it does, so the interpolation is theirs unchanged.
      #
      # The whole row is walked rather than a list of fields, which is what Foundry does
      # (`rule-element/base.ts` `resolveInjectedProperties`): a predicate reads a choice the same way a
      # path does, and Virtuosic Performer's bonus is written against
      # `action:perform:{item|flags.system.rulesSelections.performanceType}`.
      #
      # Only the actor, the item and the rule are resolved here, which is the list Foundry resolves
      # against unless a reader supplies more. `{choice|value}` is the other one their data uses: it
      # belongs to a choice set testing a candidate answer, so it is left alone for `Pf2e::Choices`
      # rather than counting as a path nothing holds.
      INTERPOLATION = /\{(actor|item|rule)\|([^}]*)\}/

      # A rule naming something the context does not hold is ignored, which is Foundry's own answer to
      # it (`this.ignored = true`): a feat whose choice has not been made yet says nothing, rather than
      # something other than what it says.
      def self.resolved(row, source, context)
        return row unless interpolated?(row)

        filled = fill(row, Formula.flatten(context.merge('item' => source['item'] || {})))

        interpolated?(filled) ? nil : filled
      end

      def self.interpolated?(held)
        case held
        when String then held.match?(INTERPOLATION)
        when Array then held.any? { |one| interpolated?(one) }
        when Hash then held.any? { |_key, one| interpolated?(one) }
        else false
        end
      end

      def self.fill(held, facts)
        case held
        when String then interpolate(held, facts)
        when Array then held.map { |one| fill(one, facts) }
        when Hash then held.each_with_object({}) { |(key, one), out| out[key] = fill(one, facts) }
        else held
        end
      end

      # A path the context does not hold leaves the interpolation as it stands, so `resolved` can tell
      # a rule that resolved from one that did not.
      def self.interpolate(text, facts)
        text.gsub(INTERPOLATION) do
          held = facts["#{Regexp.last_match(1)}.#{Regexp.last_match(2)}"]

          held.nil? ? Regexp.last_match(0) : held.to_s
        end
      end

      # Whether a rule needs its item worn. Foundry's default is that it does; a rule that says otherwise
      # works from a pack, which is why those items are gathered at all.
      def self.needs_wearing?(row)
        row['requiresEquipped'] != false
      end

      # A field nobody reads is a rule that silently does something other than what it says, so it is
      # reported. Checked against the kind's own field list rather than one list for all of them,
      # because `dieSize` means nothing on a FlatModifier.
      def self.complain(name, row)
        kind = BY_KEY[row['key'].to_s]

        unless kind
          Global.logger.warn "PF2e rule on #{name.inspect} is a #{row['key'].inspect}, which nothing applies."
          return
        end

        strays = row.keys.map(&:to_s) - kind['fields'] -
                 Array(PRESENTATION[row['key'].to_s])

        return if strays.empty?

        Global.logger.warn "PF2e #{row['key']} on #{name.inspect} has fields nothing reads: #{strays.join(', ')}."
      end
    end
  end
end
