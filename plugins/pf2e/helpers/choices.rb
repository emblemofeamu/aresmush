module AresMUSH
  module Pf2e

    # What a `ChoiceSet` offers the player.
    #
    # A choice set asks a question and other rules on the same feat read the answer: a Charm of Resistance
    # asks which kind of damage it resists and its Resistance rule resists that kind. Ninety-two of the
    # rules on what we stock are questions of this sort.
    #
    # They come in three shapes, and the third is why this is small. A set may list its answers outright.
    # It may name a vocabulary - the skills, the saves, the weapon groups. Or it may describe the answers
    # with a filter, which is a predicate over catalogue entries - and a predicate engine already exists,
    # so the filter is tested the same way every other predicate in this codebase is, against facts built
    # from each candidate.
    #
    # The answer itself is not stored here. A feat's choice is recorded with the feat, which is what
    # `cg/feat` and `advance/feat` write, so a choice taken back goes with the feat that carried it.
    module Choices

      # The vocabularies a set may name, onto ours. Foundry's own table names.
      VOCABULARIES = {
        'skills' => -> { (Global.read_config('pf2e_skills') || {}).keys.reject { |name| Pf2eSkills.lore?(name) } },
        'saves' => -> { %w{Fortitude Reflex Will} },
        # Read off the catalogue rather than listed here, so a weapon group added tomorrow is offered.
        'weaponGroups' => -> {
          (Global.read_config('pf2e_weapons') || {}).values
            .map { |info| info.is_a?(Hash) ? info['group'] : nil }.compact.uniq
        },
        'damageTypes' => -> { DAMAGE_TYPES },
        'creatureTraits' => -> {
          (Global.read_config('pf2e_ancestry') || {}).values
            .flat_map { |info| info.is_a?(Hash) ? Array(info['traits']) : [] }.uniq
        }
      }.freeze

      # PF2e's own damage types. Listed because they are the rules' vocabulary rather than this game's
      # catalogue: nothing in config enumerates them.
      DAMAGE_TYPES = %w{acid bludgeoning cold electricity fire force mental piercing poison slashing
                        sonic spirit vitality void bleed untyped}.freeze

      # Which of our catalogues holds a kind of item a filter may describe.
      CATALOGUES = { 'feat' => 'pf2e_feats', 'spell' => 'pf2e_spells', 'weapon' => 'pf2e_weapons',
                     'ancestry' => 'pf2e_ancestry', 'armor' => 'pf2e_armor' }.freeze

      # Every answer this set allows a player to pick now. A condition on an answer is about the
      # character, so this is the offer to make rather than the record of one made: Skill Training
      # offers the skills you are untrained in, and a moment after you take it you are trained in one.
      def self.offer(set, char)
        held = char ? Effects.facts(char) : []

        listed = Array(set['choices'])

        return listed.select { |one| Predicate.test(one['when'], held) }.map { |one| one['value'] } \
          if listed.any?

        return from_vocabulary(set, held) if set['vocabulary']
        return owned(set, char).select { |_id, facts| Predicate.test(set['each'], held + facts) }.keys \
          if set['owned']

        from_filter(set, held)
      end

      # Their kinds of thing, onto our inventory categories. A creature's natural attack is one of their
      # `melee` items, and a character's weapons stand in for it.
      OWNED = { 'weapon' => 'weapons', 'melee' => 'weapons', 'armor' => 'armor', 'shield' => 'shields' }.freeze

      # The character's own things of the kinds a set asks for, each as its id and what it answers to.
      # The id is the answer, as it is in Foundry, because it is what a rule names: the damage of the
      # weapon chosen is `{item|flags.system.rulesSelections.weapon}-damage`, which is that weapon's own
      # damage domain. Handwraps of mighty blows stand for the unarmed attack, whose domain is `unarmed`.
      def self.owned(set, char)
        # Only an actor that carries things has anything a set could choose from.
        return {} unless char && Actors.of(char).carries_items?

        categories = Array(set['owned']).map { |kind| OWNED[kind] }.compact.uniq

        found = Pf2egear.carried_items(char).select { |category, _item| categories.include?(category) }
                        .to_h { |category, item| [ item.id.to_s, owned_facts(category, item) ] }

        found['unarmed'] = [ 'item:category:unarmed' ] if set['handwraps'] && handwraps?(char)

        found
      end

      # What one of the character's things answers to, from the catalogue: a filter over it has to be
      # tested without assembling an attack, because this is asked while effects are being gathered.
      def self.owned_facts(category, item)
        info = Pf2egear.catalogue_entry(category, item) || {}
        kind = category == 'weapons' ? 'weapon' : category.delete_suffix('s')

        facts_of(item.name, info, kind) +
          (category == 'weapons' ? Pf2eCombat.weapon_options(item.name, info) : [])
      end

      def self.handwraps?(char)
        Pf2egear.carried_items(char).any? { |_category, item| Domains.slug(item.name).include?('handwraps') }
      end

      # What a player typed for one of their own things, as the id the answer is: the weapon's name or its
      # nickname, whichever they used.
      def self.owned_answer(set, char, typed)
        return nil unless Actors.of(char).carries_items?

        wanted = Domains.slug(typed)

        return 'unarmed' if wanted == 'unarmed' && owned(set, char).key?('unarmed')

        Pf2egear.carried_items(char).find { |_category, item|
          owned(set, char).key?(item.id.to_s) &&
            [ item.name, (item.nickname if item.respond_to?(:nickname)) ].compact
                                                                          .any? { |one| Domains.slug(one) == wanted }
        }&.last&.id&.to_s
      end

      # Whether an answer belongs to this set at all - that it names a skill, a kind of damage, a feat
      # the description reaches. Asked of an answer already recorded, where the conditions that shaped
      # the offer have since been met by the choice itself.
      #
      # Nothing here reads the character, which is what lets a recorded answer be read while the
      # character's own facts are still being assembled.
      #
      # One of the character's own things is the exception: whether an answer is one of them depends on
      # what they carry, so the character is asked - which reads the inventory and nothing derived.
      def self.includes?(set, answer, char = nil)
        wanted = Domains.slug(answer)
        listed = Array(set['choices'])

        return !listed_answer(set, answer).nil? if listed.any?
        return owned(set, char).key?(answer.to_s) if set['owned']
        return from_vocabulary(set, nil).include?(wanted) if set['vocabulary']

        from_filter(set, []).include?(wanted)
      end

      # The value a listed choice records for what someone answered. A number is matched as a number, so
      # `-1` is not `+1`; a word by its slug; and failing both, the choice's own label - Bon Mot's
      # `Critical Success`, whose value is `-3`. Tried in that order, because labels like `+1` and `-1`
      # slug alike. A value that is a set of figures, as Dragon Form's dragons are, stays one: its rules read
      # parts of it.
      NUMBER = /\A[+-]?\d+\z/

      def self.listed_answer(set, answer)
        typed = answer.to_s.strip
        listed = Array(set['choices'])
        numeric = typed.match?(NUMBER)

        found = listed.find { |one| one['value'].to_s == typed } ||
                (numeric && listed.find { |one| one['value'].to_s.match?(NUMBER) && one['value'].to_i == typed.to_i }) ||
                (!numeric && listed.find { |one| one['value'].to_s == Domains.slug(typed) }) ||
                listed.find { |one| one['label'].to_s.casecmp?(typed) } ||
                (!numeric && listed.find { |one| Domains.slug(one['label']) == Domains.slug(typed) })

        return nil unless found

        found['value'].is_a?(Hash) ? found['value'] : found['value'].to_s
      end

      # A vocabulary may come with one condition covering every answer in it, written with the answer
      # left blank: `skill:{choice|value}:rank:0` is "a skill you are untrained in". The answer being
      # considered is filled in before the condition is tested, which is Foundry's `{choice|…}`
      # (`choice-set/rule-element.ts` `#choicesFromPath`). A nil `held` asks for the vocabulary itself,
      # with no condition applied.
      def self.from_vocabulary(set, held)
        found = VOCABULARIES[set['vocabulary'].to_s]

        return [] unless found

        whole = found.call.map { |one| Domains.slug(one) }

        held.nil? ? whole : whole.select { |one| allowed?(set['each'], one, held) }
      end

      CANDIDATE = /\{choice\|[^}]*\}/

      def self.allowed?(condition, answer, held)
        return true unless condition

        Predicate.test(about(condition, answer), held)
      end

      def self.about(condition, answer)
        case condition
        when String then condition.gsub(CANDIDATE) { answer }
        when Array then condition.map { |one| about(one, answer) }
        when Hash then condition.each_with_object({}) { |(key, one), out| out[key] = about(one, answer) }
        else condition
        end
      end

      # Catalogue entries whose own facts satisfy the filter. A filter describes what an answer *is*
      # rather than whether the character may have it, so it applies to an answer already recorded as
      # much as to one being offered. `item:level` and the rest are Foundry's spelling, so a filter
      # copied from their data reads the same facts.
      def self.from_filter(set, held)
        catalogue = CATALOGUES[set['item_type'].to_s]

        return [] unless catalogue && set['filter']

        (Global.read_config(catalogue) || {}).select do |name, info|
          Predicate.test(set['filter'], facts_of(name, info, set['item_type']) + Array(held))
        end.keys.map { |name| Domains.slug(name) }
      end

      # What a catalogue entry answers to when a filter asks about it.
      def self.facts_of(name, info, type)
        info = {} unless info.is_a?(Hash)

        [ "item:type:#{type}",
          "item:slug:#{Domains.slug(name)}",
          "item:level:#{(info['level'] || 1).to_i}",
          "item:category:#{Domains.slug(info['category'])}",
          "item:group:#{Domains.slug(info['group'])}" ] +
          Array(info['traits']).map { |trait| "item:trait:#{Domains.slug(trait)}" } +
          Array(info['type']).map { |kind| "item:feat-type:#{Domains.slug(kind)}" }
      end

      # Whether an answer is one this set would offer: it belongs to the set, and the character meets
      # whatever the set asks of them.
      def self.allows?(set, char, answer)
        offer(set, char).map { |one| Domains.slug(one) }.include?(Domains.slug(answer))
      end
    end
  end
end
