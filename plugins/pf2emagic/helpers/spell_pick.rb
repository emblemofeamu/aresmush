module AresMUSH
  module Pf2emagic

    # Whether a character may add this spell to this list at this rank.
    #
    # Chargen and a level-up both ask it, and asked it in two places with two different subsets of
    # the rules: chargen checked the ranks and whether a spellbook addition still fits its restricted
    # entries, a level-up checked that a signature spell is one the character knows. Each was missing
    # what the other had.
    #
    # One row per rule, in the order a player should hear them, and pure: the context is plain data,
    # so a spec needs no character and no database. Resolving the *name* stays with the caller,
    # because chargen offers common spells only and a level-up offers what the class can reach.
    module SpellPick

      # The list a pick is going into. `signature` designates a spell the character already knows
      # rather than adding one, which is why it has a rule of its own.
      LISTS = %w{spellbook repertoire signature}.freeze

      GUARDS = [
        # A spell with no tradition at all cannot go in a spellbook: there is nothing to match.
        {
          'name' => 'has a tradition',
          'check' => lambda { |ctx|
            next nil unless Array(ctx['details']['tradition']).empty?

            Pf2e::Err.new(:no_tradition, 'pf2emagic.not_spellbook_eligible')
          }
        },
        # Off the class's own tradition list, unless something adapted it onto it. A signature
        # designates a spell already known, and a mystery or a bloodline grants spells from any
        # tradition for the class to cast as its own, so knowing it is the only test there.
        {
          'name' => 'the class can cast it',
          'check' => lambda { |ctx|
            next nil if ctx['list'] == 'signature'
            next nil if ctx['adapted']
            next nil if Array(ctx['details']['tradition']).any? { |trad| trad.to_s.casecmp?(ctx['tradition'].to_s) }

            Pf2e::Err.new(:wrong_tradition, 'pf2emagic.class_does_not_get_spell')
          }
        },
        # A cantrip goes in a cantrip slot and a ranked spell in a ranked one, and a spell cannot be
        # learned at a rank below the one it is written for.
        {
          'name' => 'the rank agrees',
          'check' => lambda { |ctx|
            base = ctx['details']['base_level'].to_i
            slot_cantrip = SpellPick.cantrip?(ctx['rank'])

            next Pf2e::Err.new(:cantrip_in_slot, 'pf2emagic.cant_learn_cantrip_slot') if base.zero? && !slot_cantrip
            next Pf2e::Err.new(:spell_in_cantrip, 'pf2emagic.cant_learn_spell_cantrip') if !base.zero? && slot_cantrip
            next nil if slot_cantrip
            next nil if base <= ctx['rank'].to_i

            Pf2e::Err.new(:rank_too_low, 'pf2emagic.cant_prepare_level')
          }
        },
        {
          'name' => 'not picked already this time',
          'check' => lambda { |ctx|
            next nil unless Array(ctx['picks']).any? { |pick| pick.to_s.casecmp?(ctx['spell'].to_s) }

            Pf2e::Err.new(:already_picked, 'pf2emagic.spell_already_on_list_to_assign')
          }
        },
        # Already known. A repertoire holds a spell per rank, so knowing Fireball at 3rd does not
        # stop a Sorcerer learning it at 5th; a spellbook holds it once.
        {
          'name' => 'not known already',
          'check' => lambda { |ctx|
            next nil if ctx['list'] == 'signature'

            held = ctx['list'] == 'spellbook' ? SpellPick.all_known(ctx) : Array((ctx['known'] || {})[ctx['rank'].to_s])

            next nil unless held.any? { |spell| spell.to_s.casecmp?(ctx['spell'].to_s) }

            Pf2e::Err.new(:already_known,
                          ctx['list'] == 'spellbook' ? 'pf2emagic.spell_already_in_spellbook' : 'pf2emagic.spell_already_in_repertoire')
          }
        },
        # A signature spell is one of the character's repertoire spells, designated so it can be
        # heightened freely - so it has to be one they know at that rank.
        {
          'name' => 'a signature is known',
          'check' => lambda { |ctx|
            next nil unless ctx['list'] == 'signature'
            next nil if Array((ctx['known'] || {})[ctx['rank'].to_s]).any? { |spell| spell.to_s.casecmp?(ctx['spell'].to_s) }

            Pf2e::Err.new(:signature_unknown, 'pf2emagic.signature_not_in_repertoire', 'level' => ctx['rank'])
          }
        },
        # A Wizard's curriculum entry can only hold a school spell, so the question is not how many
        # spells are in the book but whether an arrangement exists that seats them all. The caller
        # works that out with SlotFit and answers here.
        {
          'name' => 'it fits the restricted entries',
          'check' => lambda { |ctx|
            next nil unless ctx['list'] == 'spellbook'
            next nil unless ctx.key?('fits')
            next nil if ctx['fits']

            Pf2e::Err.new(:no_room, 'pf2emagic.no_unrestricted_spellbook')
          }
        }
      ].freeze

      # An innate spell is granted rather than learned, so it asks a different set: the grant names
      # a tradition and a rank, and the spell has to match both. Its own message keys, because a
      # player told "you cannot prepare that" about a granted spell would be looking in the wrong
      # place. One row per rule, in order.
      INNATE_GUARDS = [
        {
          'name' => 'castable at all',
          'check' => lambda { |ctx|
            next nil unless Array(ctx['details']['tradition']).empty?

            Pf2e::Err.new(:no_tradition, 'pf2emagic.innate_not_spell_eligible')
          }
        },
        {
          'name' => "the grant's tradition",
          'check' => lambda { |ctx|
            next nil if Array(ctx['details']['tradition']).any? { |trad| trad.to_s.casecmp?(ctx['tradition'].to_s) }

            Pf2e::Err.new(:wrong_tradition, 'pf2emagic.innate_tradition_mismatch')
          }
        },
        {
          'name' => 'the rank agrees',
          'check' => lambda { |ctx|
            base = ctx['details']['base_level'].to_i
            asked_cantrip = SpellPick.cantrip?(ctx['rank'])

            next Pf2e::Err.new(:cantrip_in_slot, 'pf2emagic.innate_cant_learn_cantrip_slot') if base.zero? && !asked_cantrip
            next Pf2e::Err.new(:spell_in_cantrip, 'pf2emagic.innate_cant_learn_spell_cantrip') if !base.zero? && asked_cantrip
            next Pf2e::Err.new(:rank_too_low, 'pf2emagic.innate_cant_prepare_level') if base > ctx['rank'].to_i && !asked_cantrip

            nil
          }
        },
        # The grant is for one rank, so the spell has to be taken at that rank and no other.
        {
          'name' => "the grant's own rank",
          'check' => lambda { |ctx|
            asked_cantrip = SpellPick.cantrip?(ctx['rank'])
            granted_cantrip = SpellPick.cantrip?(ctx['granted_rank'])

            next Pf2e::Err.new(:wrong_slot, 'pf2emagic.innate_cant_prepare_level') if granted_cantrip != asked_cantrip
            next nil if granted_cantrip
            next nil if ctx['granted_rank'].to_i == ctx['rank'].to_i

            Pf2e::Err.new(:wrong_slot, 'pf2emagic.innate_cant_prepare_level')
          }
        }
      ].freeze

      # The first rule an innate pick breaks, or nil.
      def self.check_innate(ctx)
        context = { 'details' => {} }.merge(ctx || {})

        INNATE_GUARDS.each do |guard|
          failure = guard['check'].call(context)

          return failure if failure
        end

        nil
      end

      def self.cantrip?(rank)
        rank.to_s.casecmp?('cantrip') || rank.to_i.zero?
      end

      def self.all_known(ctx)
        (ctx['known'] || {}).values.flatten
      end

      def self.rules
        GUARDS.map { |guard| guard['name'] }
      end

      # The first rule this pick breaks, or nil.
      def self.check(ctx)
        context = { 'list' => 'spellbook', 'details' => {}, 'picks' => [], 'known' => {} }.merge(ctx || {})

        GUARDS.each do |guard|
          failure = guard['check'].call(context)

          return failure if failure
        end

        nil
      end
    end
  end
end
