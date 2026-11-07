module AresMUSH
  module Pf2e

    # Things a character can do: Take Cover, Rage, a monk's stance.
    #
    # The catalogue (`pf2e_actions.yml`, from Foundry's actions pack and the feats that are actions) says
    # what each costs, what it puts on whoever uses it - Foundry's `selfEffect` - and, for one that rolls,
    # what the check is. This says which a character may use; using one is `Acting.act`, which
    # `action/use` and `+e/act` both are.
    module Actions

      # What an action costs, as a sheet says it.
      COSTS = { 1 => 'one action', 2 => 'two actions', 3 => 'three actions' }.freeze
      TYPES = { 'reaction' => 'reaction', 'free' => 'free action', 'passive' => 'passive' }.freeze

      def self.catalogue
        Global.read_config('pf2e_actions') || {}
      end

      def self.info(name)
        catalogue[name] || {}
      end

      # What each outcome of an action's check does, by the action's slug and the way of doing it where
      # it has more than one: `{ 'success' => [ { 'on' => 'target', 'condition' => 'Prone' } ] }`. Game
      # config (`pf2e_action_consequences.yml`), so a GM can change what Trip does.
      def self.consequences(slug, variant = nil)
        held = Global.read_config('pf2e_action_consequences') || {}

        (variant && held["#{slug}:#{variant}"]) || held[slug.to_s] || {}
      end

      # The action a player means, by the name they typed.
      def self.find(term)
        wanted = Domains.slug(term)
        names = catalogue.keys

        exact = names.find { |name| Domains.slug(name) == wanted }

        return Ok.new(:state => exact) if exact

        close = names.select { |name| Domains.slug(name).include?(wanted) }

        return Ok.new(:state => close.first) if close.size == 1
        return Err.new(:not_found, 'pf2e.action_not_found', 'action' => term) if close.empty?

        Err.new(:ambiguous, 'pf2e.action_ambiguous', 'action' => term, 'options' => close.first(8).join(', '))
      end

      # An exploration or downtime activity costs no actions - Foundry files it as passive - but it is
      # something a character does, so it is an activity rather than nothing.
      def self.cost(name)
        entry = info(name)

        return 'activity' if entry['type'] == 'passive' && activity?(entry)

        TYPES[entry['type']] || COSTS[entry['cost'].to_i] || 'one action'
      end

      def self.activity?(entry)
        exploration?(entry) || downtime?(entry)
      end

      # ------------------------------------------------------------------------------
      # Whose it is

      # Whether the character can use an action. The basic, skill, exploration and downtime actions are
      # everyone's. Anything else - a class's, an archetype's, a heritage's - and any feat that is an
      # action, is theirs if a feat or feature of theirs has its name: the Rage class feature is what gives
      # a barbarian Rage, at the level the class grants it and not before. A class, heritage or background
      # can also name an action outright, as an investigator's names Devise a Stratagem.
      def self.usable(char, name)
        entry = info(name)

        return Ok.new(:state => name) if entry['for'] == 'everyone' || owned?(char, name) || DragonBreath.grants?(char, name)

        Err.new(:not_yours, 'pf2e.action_not_yours', 'action' => name)
      end

      def self.owned?(char, name)
        wanted = Domains.slug(name)
        given = char.respond_to?(:pf2_actions) ? (char.pf2_actions || {}).values_at('actions', 'reactions') : []
        held = (char.pf2_feats || {}).values.flatten + (char.pf2_features || {}).values.flatten + given.flatten.compact

        held.any? { |one| Domains.slug(one) == wanted }
      end

      # ------------------------------------------------------------------------------
      # What a character has

      # The modes of play an action belongs to, by the traits Foundry gives it: an exploration activity
      # and a downtime activity say so, and anything else that costs actions is for an encounter.
      MODES = {
        'combat' => ->(entry) { !exploration?(entry) && !downtime?(entry) },
        'exploration' => ->(entry) { exploration?(entry) },
        'downtime' => ->(entry) { downtime?(entry) },
        'reactions' => ->(entry) { entry['type'] == 'reaction' }
      }.freeze

      # What a player may call a mode, onto the mode.
      ALIASES = { 'encounter' => 'combat', 'reaction' => 'reactions' }.freeze

      def self.mode(named)
        return nil if named.to_s.strip.empty?

        wanted = named.to_s.strip.downcase

        MODES.key?(wanted) ? wanted : ALIASES[wanted]
      end

      def self.exploration?(entry)
        Array(entry['traits']).include?('exploration')
      end

      def self.downtime?(entry)
        Array(entry['traits']).include?('downtime')
      end

      # Every action the character can use, in a mode of play or in all of them, by name. Something passive
      # is not used, so it is not listed - unless it is an exploration or downtime activity, which is.
      def self.available(char, mode = nil)
        keep = mode ? MODES[mode] : ->(_entry) { true }

        catalogue.select { |name, entry|
          (entry['type'] != 'passive' || activity?(entry)) && keep.call(entry) && usable(char, name).ok?
        }.keys.sort
      end
    end
  end
end
