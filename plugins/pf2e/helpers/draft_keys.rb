module AresMUSH
  module Pf2e

    # The vocabulary of a draft: every key the two draft hashes use, what it holds, and which hash it
    # belongs to.
    #
    # `pf2_to_assign` holds what is still open to pick. `pf2_advancement` holds what a level-up has
    # picked so far. A key belongs to one of them, and the naming says which: a space for `to_assign`,
    # an underscore for `advancement`. Four keys predate that convention and break it, and the
    # `holder` column is where a reader finds out.
    #
    # `Slots.apply` refuses a delta whose path root is not registered here, so a key invented at a
    # call site fails the first time it is written.
    module DraftKeys

      TO_ASSIGN = 'to_assign'.freeze
      ADVANCEMENT = 'advancement'.freeze
      # One key appears in both hashes, so the holder column has to be able to say so.
      BOTH = 'both'.freeze

      # key => [ holder, what it holds ]
      KEYS = {
        # Picks a player still owes, in to_assign.
        'open languages' => [ TO_ASSIGN, 'language picks, as open markers and filled names' ],
        'open skills' => [ TO_ASSIGN, 'free skill increases, as open markers' ],
        'feat choice' => [ TO_ASSIGN, 'open slots for a choice a feat or feature carries, by choice name' ],
        'feat choice filter' => [ TO_ASSIGN, 'what narrows one of those choices, by choice name' ],
        'feat_choices' => [ TO_ASSIGN, 'labels already chosen for a choice, by choice name' ],
        'bg skill choice' => [ TO_ASSIGN, 'the background skill pick, as options and selected' ],
        'class skill choice' => [ TO_ASSIGN, 'the class skill pick, as options and selected' ],
        'specialty skill choice' => [ TO_ASSIGN, 'the specialty skill pick, as options and selected' ],
        'bgskill' => [ TO_ASSIGN, 'background skills granted outright' ],
        'bg_lore' => [ TO_ASSIGN, 'the background lore, which breaks the spacing convention' ],
        'bgfeat' => [ TO_ASSIGN, 'background feats to choose between, which breaks the spacing convention' ],
        'class option' => [ TO_ASSIGN, 'a class feature option awaiting a pick' ],
        'divine font' => [ TO_ASSIGN, 'the divine font choice, when a deity offers both' ],
        'archetype' => [ TO_ASSIGN, 'the archetype being joined this level' ],
        'archetype_specialty' => [ TO_ASSIGN, 'the archetype specialty pick, which breaks the spacing convention' ],
        'archetype specialty choice' => [ TO_ASSIGN, 'a choice an archetype specialty carries, by archetype' ],
        'archetype deity' => [ TO_ASSIGN, 'the deity an archetype asks for' ],
        'archetype key ability' => [ TO_ASSIGN, 'the key ability an archetype asks for' ],

        # What a level-up has settled, in advancement.
        'feats' => [ BOTH, 'the feat slot pool in to_assign, keyed by slot type, and what was taken in them in advancement' ],
        'grants' => [ ADVANCEMENT, 'what those feats handed over, pending advance/done' ],
        'magic_stats' => [ ADVANCEMENT, 'spellcasting this level grants, by source' ],
        'combat_stats' => [ ADVANCEMENT, 'proficiencies this level grants, including an archetype class DC' ],
        'raise skill' => [ ADVANCEMENT, 'skill increases taken, which breaks the spacing convention' ],
        'raise skill choice' => [ ADVANCEMENT, 'increases taken from a restricted list, which breaks the convention' ],
        'raise ability' => [ ADVANCEMENT, 'attribute boosts taken this level' ],
        'repertoire' => [ ADVANCEMENT, 'spells added to a repertoire this level' ],
        'repertoire_swap' => [ ADVANCEMENT, 'a repertoire spell traded for another' ],
        'spellbook' => [ ADVANCEMENT, 'spells added to a spellbook this level' ],
        'signature' => [ ADVANCEMENT, 'signature spells designated this level' ],
        'spells' => [ ADVANCEMENT, 'spells learned this level, by source and rank' ],
        'innate' => [ ADVANCEMENT, 'innate spells granted this level' ],
        'archetype_features' => [ ADVANCEMENT, 'features an archetype granted this level' ],
        'archetype_deity' => [ ADVANCEMENT, 'the deity chosen for an archetype' ],
        'archetype_sanctification' => [ BOTH, 'the sanctification, as an open marker in to_assign and as the choice in advancement - the one archetype pick that uses the same key in both' ],
        'charclass_feature option' => [ ADVANCEMENT, 'the option chosen for a class feature' ]
      }.freeze

      def self.all
        KEYS.keys
      end

      def self.canonical(key)
        name = key.to_s

        KEYS.key?(name) ? name : KEYS.keys.find { |k| k.casecmp?(name) }
      end

      def self.registered?(key)
        !canonical(key).nil?
      end

      def self.holder(key)
        found = canonical(key)

        found && KEYS[found][0]
      end

      def self.describe(key)
        found = canonical(key)

        found && KEYS[found][1]
      end

      # Keys whose name does not say which hash they belong to.
      def self.breaking_convention
        KEYS.select do |key, (holder, _what)|
          spaced = key.include?(' ')

          next true if holder == BOTH

          (spaced && holder == ADVANCEMENT) || (!spaced && holder == TO_ASSIGN)
        end.keys
      end
    end
  end
end
