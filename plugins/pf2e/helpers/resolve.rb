module AresMUSH
  module Pf2e

    # A check rolled against something: the d20, the figure, the DC, and the outcome.
    #
    # `Check` builds what a roll is worth; this throws the die and measures it, the same way for a
    # character and a creature. Everything a rule can do to a roll is asked of the check: fortune rolls
    # twice, Assurance stands in for the die, a keen weapon turns a near miss into a critical hit, and what
    # the roll spent - Guidance's bonus - is spent.
    module Resolve

      # `extra` are modifiers this one roll carries that no figure does: a range increment, an action's
      # own circumstance penalty. They are stacked with the figure's, so a circumstance penalty the
      # action carries does not stack with one the character already has.
      # `shift` moves the outcome once everything else has had its say, as the incapacitation trait does.
      def self.roll(check, dc: nil, extra: [], shift: 0, rolled: nil)
        breakdown = restacked(check.breakdown, extra)
        rolled ||= d20([ check ])
        total = rolled['face'] + breakdown['total'].to_i

        check.rolled!(total, dc, rolled['die'])

        degree = degree([ check ], total, dc, rolled['die'])
        degree = Degree.shift(degree, shift) if degree && shift != 0

        rolled.except('face').merge('modifier' => breakdown['total'].to_i, 'total' => total, 'dc' => dc,
                                    'degree' => degree, 'shift' => shift, 'breakdown' => breakdown)
      end

      FORTUNE = { 'keep-higher' => 'fortune', 'keep-lower' => 'misfortune' }.freeze

      # The d20 of a roll that holds these checks. Fortune rolls it twice and keeps the higher,
      # misfortune the lower, and one of each cancels. A substitution - Assurance's 10 - stands in for
      # the die and is itself fortune or misfortune, so it cancels with the other too
      # (`check.ts:127`). `die` is the natural face, which a substitution has none of.
      def self.d20(checks)
        checks = Array(checks)
        keep = roll_twice(checks)
        substitution = checks.map { |check| check.respond_to?(:substitution) ? check.substitution : nil }.compact.first

        if [ substitution && substitution['effect_type'], FORTUNE[keep] ].compact.sort == %w{fortune misfortune}
          keep = nil
          substitution = nil
        end

        if substitution
          checks.each { |check| check.substituted = substitution['slug'] if check.respond_to?(:substituted=) }

          return { 'die' => nil, 'dice' => [], 'kept' => nil, 'substitution' => substitution,
                   'face' => substitution['value'].to_i }
        end

        dice = DiceTape.for_check(roller(checks), keep) do
          keep ? [ Pf2e.roll_dice(1, 20).first, Pf2e.roll_dice(1, 20).first ] : Pf2e.roll_dice(1, 20)
        end
        natural = keep == 'keep-lower' ? dice.min : dice.max

        { 'die' => natural, 'dice' => dice, 'kept' => keep, 'substitution' => nil, 'face' => natural }
      end

      # Whose roll it is, by name, for the record of the dice. A creature's is marked as one, so it is
      # never taken for a character's of the same name.
      def self.roller(checks)
        char = checks.map { |check| check.respond_to?(:char) ? check.char : nil }.compact.first

        return nil unless char.respond_to?(:name)

        Actors.of(char).creature? ? "creature:#{char.name}" : char.name
      end

      # Fortune or misfortune on a roll, from the checks in it: one of each cancels.
      def self.roll_twice(checks)
        keeps = Array(checks).map { |check| check.respond_to?(:roll_twice) ? check.roll_twice : nil }.compact.uniq

        keeps.size == 1 ? keeps.first : nil
      end

      # How a roll went against a DC, once every rule the checks in it hold about the outcome has had its
      # say: Assurance's failure made a success, a keen weapon's 19 made a critical hit. `held` are the
      # checks, or adjustments already read off them.
      def self.degree(held, total, dc, die)
        return nil unless dc

        adjustments = Array(held).flat_map do |one|
          one.respond_to?(:rolled) ? one.adjustments(one.rolled(total, dc, die)) : one
        end

        Degree.adjusted(Degree.of(total, dc, die), adjustments)
      end

      # A figure's modifiers with more added, stacked again.
      def self.restacked(breakdown, extra)
        return breakdown if Array(extra).empty?

        rows = Array(breakdown['modifiers']).map { |row| row.except('enabled') } + Array(extra)

        breakdown.merge(Modifiers.breakdown(breakdown['base'].to_i, rows))
      end

      # A flat check: a d20 against a DC, nothing added.
      def self.flat(dc)
        die = Pf2e.roll_dice(1, 20).first

        { 'die' => die, 'dc' => dc, 'success' => die >= dc }
      end

      # ------------------------------------------------------------------------------
      # Defences

      # What each defence an action names is, as a figure: AC, a save, Perception, or a skill DC.
      def self.defence_figure(against)
        named = against.to_s.downcase

        return [ 'ac', nil ] if %w{ac armor}.include?(named)
        return [ 'perception', nil ] if named == 'perception'
        return [ 'save', named ] if Pf2e::SAVES.include?(named)

        [ 'skill', Stat.skill_named(named) || named.capitalize ]
      end

      # A defence as a DC: AC as it stands, anything else ten more than its modifier. `options` are what
      # is true of the one attacking, as the defender's rules read them; `extra` what this attack alone
      # gives the defender - cover, or the off-guard of being flanked.
      def self.defence(holder, against, options: [], extra: [])
        kind, name = defence_figure(against)
        figure = Actors.of(holder).figure(kind, name, options)

        return nil unless figure

        figure = restacked(figure, extra)
        dc = kind == 'ac' ? figure['total'].to_i : 10 + figure['total'].to_i

        { 'dc' => dc, 'kind' => kind, 'name' => name, 'breakdown' => figure }
      end

      # What is true of one side, as the other's rules ask about it: Foundry spells what an attacker knows
      # of its target `target:` and what a defender knows of its attacker `origin:`.
      def self.seen_as(holder, prefix)
        Effects.facts(holder).select { |one| one.start_with?('self:') }
                             .map { |one| one.sub(/\Aself:/, "#{prefix}:") }
      end

      # ------------------------------------------------------------------------------
      # Cover and concealment

      COVER = { 'lesser' => 1, 'standard' => 2, 'greater' => 4 }.freeze
      CONCEALMENT = { 'concealed' => 5, 'hidden' => 11, 'undetected' => 11 }.freeze

      # What an attacker who cannot see well is to everything they attack: hidden from the blinded, and
      # concealed from the dazzled.
      UNSEEING = { 'blinded' => 11, 'dazzled' => 5 }.freeze

      def self.flat_dc(why)
        CONCEALMENT[why] || UNSEEING[why]
      end

      # Cover's bonus to AC, and to a Reflex save against an area where the cover is standard or better.
      def self.cover_modifier(level, against = 'ac')
        value = COVER[level.to_s]

        return nil unless value
        return nil if against.to_s != 'ac' && value < COVER['standard']

        { 'source' => "#{level} cover", 'slug' => 'cover', 'type' => 'circumstance', 'value' => value }
      end

      # Being flanked leaves a creature off-guard to the flanker: -2 AC, the same circumstance penalty
      # Off-Guard's own rule gives, so the two do not stack.
      FLANKED = { 'source' => 'off-guard (flanked)', 'slug' => 'off-guard', 'type' => 'circumstance',
                  'value' => -2 }.freeze

      # Two degrees are shown as words.
      WORDS = [ 'critical failure', 'failure', 'success', 'critical success' ].freeze

      def self.word(degree)
        degree ? WORDS[degree] : nil
      end

    end
  end
end
