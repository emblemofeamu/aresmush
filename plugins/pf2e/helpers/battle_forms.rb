module AresMUSH
  module Pf2e

    # A polymorph: Animal Form, Dragon Form, a druid's wild shape. While it lasts the character fights as
    # the form - its AC, its attacks, its speeds - unless their own is better where the form allows that.
    #
    # Foundry's `BattleForm` (`battle-form/rule-element.ts`), read unchanged:
    #
    #   * The form's numbers are the better of its own and a bracket by the effect's rank: Animal Form
    #     heightened to 5th is a huge creature with a +18 attack.
    #   * A fixed AC, skill or attack modifier replaces the character's own - unless theirs is higher and
    #     the form allows it, which a skill and an attack do by default and AC does not. Only status and
    #     circumstance modifiers and penalties survive on top of a form's figure: the character's
    #     attribute, proficiency and items do not.
    #   * A form with speeds replaces every speed the character has.
    #   * What else it gives - senses, a size, resistances, temporary hit points - is what the ordinary
    #     rules for each of those read, so it is given as those rules rather than read here.
    #   * Only one form holds at a time: the first.
    module BattleForms

      # The slug a form's own modifier carries, which is how a form's figure is told from a borrowed one.
      SLUG = 'battle-form'.freeze

      # The form the character is in, as `{ 'effect' =>, 'form' => }`, or nil.
      def self.active(char)
        SheetReads.memo(char, :battle_form) do
          facts = Effects.character_facts(char)

          ActiveEffects.on(char).sort_by { |effect| effect.id.to_i }.each do |effect|
            rows = Array(ActiveEffects.info(effect.name)['rules']).select { |one| one['key'] == 'BattleForm' }

            next if rows.empty?

            # An effect with several shapes has a row for each, and the answer it was applied with picks one.
            known = facts + ActiveEffects.own_options(char, effect)
            row = rows.find { |one| Predicate.test(one['predicate'], known) }

            next unless row

            break { 'effect' => effect, 'form' => bracketed(row, effect.level.to_i) }
          end.then { |found| found.is_a?(Hash) ? found : nil }
        end
      end

      def self.active?(char)
        !active(char).nil?
      end

      # Forms whose spell text gives them hands, where the imported row doesn't say so.
      WITH_HANDS = [ 'Spell Effect: Elemental Form', 'Spell Effect: Sacred Form' ].freeze

      # Whether the form they're in has hands to use a manipulate action with.
      def self.hands?(char)
        found = active(char)

        !found.nil? && (found['form']['hasHands'] == true || WITH_HANDS.include?(found['effect'].name))
      end

      # In a form that gives no attacks, which leaves them none at all: a pest can't make Strikes.
      def self.strikeless?(char)
        active?(char) && strikes(char).empty?
      end

      # The form's overrides with the bracket its rank has reached laid over them.
      def self.bracketed(row, level)
        bracket = Array(row['brackets']).select { |one| one['start'].to_i <= level }.max_by { |one| one['start'].to_i }

        bracket ? merged(row['overrides'] || {}, bracket['value'] || {}) : (row['overrides'] || {})
      end

      def self.merged(base, over)
        base.merge(over) { |_key, one, two| one.is_a?(Hash) && two.is_a?(Hash) ? merged(one, two) : two }
      end

      # A number the form gives, which may be a formula over the character, the effect's rank, or the answer
      # it was applied with.
      def self.number(char, value, effect)
        return nil if value.nil?
        return value.to_i if value.is_a?(Numeric)

        Formula.value(value, Effects.context(char).merge('item' => ActiveEffects.answered(char, effect)['item'])).to_i
      end

      # ------------------------------------------------------------------------------
      # What the form gives through the ordinary rules

      # Rows in the ordinary vocabulary for what a form gives that the ordinary rules already read.
      def self.rows(char, effect)
        found = active(char)

        return [] unless found && found['effect'].id == effect.id

        form = found['form']

        senses(form) + sized(form) + defences(form) + temp_hp(form) + declared(form) + waived(form)
      end

      def self.senses(form)
        (form['senses'] || {}).map do |sense, data|
          { 'key' => 'Sense', 'selector' => Domains.slug(sense) }.merge((data || {}).slice('acuity', 'range'))
        end
      end

      def self.sized(form)
        form['size'] ? [ { 'key' => 'CreatureSize', 'value' => form['size'] } ] : []
      end

      def self.defences(form)
        { 'immunities' => 'Immunity', 'weaknesses' => 'Weakness', 'resistances' => 'Resistance' }
          .flat_map { |field, key| Array(form[field]).map { |one| { 'key' => key }.merge(one) } }
      end

      def self.temp_hp(form)
        form['tempHP'] ? [ { 'key' => 'TempHP', 'value' => form['tempHP'] } ] : []
      end

      # What a predicate may ask about: that the character is polymorphed, in a battle form, and which
      # skills the form gives them (`#setRollOptions`).
      def self.declared(form)
        options = %w{polymorph battle-form} + (form['skills'] || {}).keys.map { |skill| "battle-form:#{skill}" }

        options.map { |option| { 'key' => 'RollOption', 'option' => option } }
      end

      # A form that ignores armour's penalties says so as suppressions of them, which is how Foundry does.
      def self.waived(form)
        ac = form['armorClass'] || {}
        rows = []

        if ac['ignoreCheckPenalty']
          rows << { 'key' => 'AdjustModifier', 'selector' => 'skill-check', 'slug' => 'armor-check-penalty',
                    'suppress' => true }
        end

        if ac['ignoreSpeedPenalty'] || ac['ignoreSpeedReduction']
          rows << { 'key' => 'AdjustModifier', 'selector' => 'all-speeds', 'slug' => 'armor-speed-penalty',
                    'suppress' => true }
        end

        rows
      end

      # ------------------------------------------------------------------------------
      # The figures a form replaces

      # What survives on top of a form's figure: its own modifier, status and circumstance modifiers, and
      # penalties of any kind (`#filterModifier`).
      def self.kept?(row)
        row['slug'] == SLUG || %w{status circumstance}.include?(row['type'].to_s) || Modifiers.value_of(row).negative?
      end

      # Whether the form's figure is used: always, unless the character's own is higher and the form
      # allows it. What survives on top of either counts on both sides (`#useFormModifier`).
      def self.use_form?(form, own, rows, own_if_higher)
        shared = rows.select { |row| row['enabled'] && kept?(row) }.sum { |row| Modifiers.value_of(row) }

        !own_if_higher || form + shared >= own
      end

      # A figure as the form leaves it. `base` is what the form's modifier sits on - 10 for AC, nothing for
      # a check - and `value` the form's own figure.
      def self.replaced(breakdown, value, base, own_if_higher)
        rows = Array(breakdown['modifiers'])

        return breakdown unless use_form?(value, breakdown['total'], rows, own_if_higher)

        kept = rows.select { |row| kept?(row) }.map { |row| row.reject { |field, _| field == 'enabled' } }
        form = { 'source' => 'battle form', 'slug' => SLUG, 'type' => Modifiers::UNTYPED, 'value' => value - base }

        Modifiers.breakdown(base, kept + [ form ]).merge('conditional' => breakdown['conditional'],
                                                         'battle_form' => true)
      end

      # What a predicate asks about when a character in a form uses their own attack modifier: Untamed Form
      # gives +2 for it.
      OWN_ATTACK = 'battle-form:own-attack-modifier'.freeze

      # The figure `Stat.of` assembled, as the form the character is in leaves it.
      def self.override(char, kind, name, breakdown, options = [], extra = [])
        found = active(char)

        return breakdown unless found
        return breakdown if Array(options).include?(OWN_ATTACK)

        form = found['form']
        effect = found['effect']

        case kind.to_s
        when 'ac'
          ac = form['armorClass'] || {}
          value = number(char, ac['modifier'], effect)

          value ? replaced(breakdown, value, 10, ac['ownIfHigher'] == true) : breakdown
        when 'skill'
          skill = (form['skills'] || {})[Domains.slug(name)]
          value = skill && number(char, skill['modifier'], effect)

          value ? replaced(breakdown, value, 0, skill['ownIfHigher'] != false) : breakdown
        when 'attack'
          strike = name.is_a?(Hash) ? name['form'] : nil
          value = strike && strike['modifier']

          return breakdown unless value

          own_if_higher = strike['own_if_higher'] != false
          # Their own modifier has what invested handwraps give it, a constant ability of gear they still
          # have. Only the bonus to hit: the form's damage is the form's, so a striking rune adds no dice.
          own = own_if_higher ? Stat.of(char, kind, Pf2eCombat.with_unarmed_runes(char, name), Array(options) + [ OWN_ATTACK ], extra) : breakdown

          use_form?(value, own['total'], Array(breakdown['modifiers']), own_if_higher) ? replaced(breakdown, value, 0, false) : own
        when 'speed'
          sped(char, form, name, breakdown, effect)
        else
          breakdown
        end
      end

      # A form with speeds has those and no others; one without leaves the character's alone.
      def self.sped(char, form, movement, breakdown, effect)
        speeds = form['speeds'] || {}

        return breakdown if speeds.empty?

        value = number(char, speeds[Domains.slug(movement || 'land')], effect).to_i
        kept = Array(breakdown['modifiers']).select { |row| kept?(row) }.map { |row| row.reject { |field, _| field == 'enabled' } }

        Modifiers.breakdown(value, kept).merge('conditional' => breakdown['conditional'], 'battle_form' => true)
      end

      # ------------------------------------------------------------------------------
      # The form's attacks

      # The attacks the form gives, as descriptors the attack and damage readers already read. Each
      # carries the form's fixed modifiers, which is what `override` and `Damage` look for, and replaces
      # every attack the character has of their own. Where one row lists the attacks of several shapes,
      # each says which it belongs to.
      def self.strikes(char)
        found = active(char)

        return [] unless found

        effect = found['effect']
        known = nil

        kept = (found['form']['strikes'] || {}).select do |_slug, strike|
          strike['predicate'].nil? ||
            Predicate.test(strike['predicate'], known ||= Effects.character_facts(char) + ActiveEffects.own_options(char, effect))
        end

        kept.map do |slug, strike|
          damage = strike['damage'] || {}
          traits = (Array(strike['traits']) + [ 'magical' ]).uniq

          { 'id' => nil, 'name' => strike['label'] || slug.split('-').map(&:capitalize).join(' '),
            'source' => effect.name, 'slug' => slug, 'category' => strike['category'],
            'prof' => Pf2eCombat.get_unarmed_prof(char, slug),
            'group' => strike['group'], 'base' => strike['baseType'] || slug,
            'traits' => traits, 'ranged' => !strike['range'].nil?, 'range' => reach_of(strike['range']),
            'unarmed' => strike['category'].to_s == 'unarmed', 'bomb' => false,
            'die' => damage['die'], 'dice' => damage['dice'] || 1,
            'damage_type' => damage['damageType'] || 'bludgeoning', 'striking' => 0, 'rune' => 0,
            'materials' => [], 'runes' => [], 'replace_all' => true,
            'form' => { 'modifier' => number(char, strike['modifier'], effect),
                        'damage_modifier' => number(char, damage['modifier'], effect).to_i,
                        'own_if_higher' => strike['ownIfHigher'] != false } }
        end
      end

      # How far a form's attack reaches, which it gives as an increment or as a maximum.
      def self.reach_of(range)
        (range.is_a?(Hash) ? range['increment'] || range['max'] : range).to_i
      end

      # What a form's attack does to its damage: the form's own damage modifier stands for the attribute,
      # and the character's numeric bonuses and extra dice do not come with them - only status and
      # circumstance bonuses, penalties, and anything written for a battle form do, and a form's own
      # deadly or fatal die (`applyDamageExclusion`). What the form's effect itself adds is the form's: a
      # dragon's jaws deal 2d6 of the dragon's own damage on top.
      def self.damage_kept?(row, traits, form_effect = nil)
        return true if written_for_form?(row['when']) || (form_effect && row['source'] == form_effect)

        if row.key?('dice')
          return row['slug'].to_s.match?(/\A(?:deadly|fatal)-\d?d\d{1,2}\z/) && Array(traits).include?(row['slug'])
        end

        Modifiers.value_of(row).negative? || %w{status circumstance}.include?(row['type'].to_s)
      end

      def self.written_for_form?(predicate)
        Array(predicate).any? do |one|
          one.to_s == SLUG || (one.is_a?(Hash) && Array(one['or']).any? { |each| each.to_s == SLUG })
        end
      end
    end
  end
end
