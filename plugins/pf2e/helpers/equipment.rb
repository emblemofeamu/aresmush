module AresMUSH
  module Pf2e

    # What a character carries in an encounter: a copy of their gear, what they wear, wield and have
    # invested, and their money, taken as they enter it.
    #
    # Everything in the encounter - their sheet there, their Strikes and AC, what they use - reads and
    # changes the copy, so what they buy or sell outside meanwhile is no part of it, and what they carried
    # in is not used or sold outside until it ends (`held_by`). A character carrying on from an earlier
    # encounter carries that one's copy on. When the encounter ends, what they used up of their own
    # consumables comes off their own inventory, and their money and anything made to last only a while
    # stay with it.
    #
    # An item that something made rather than the character owning it says so: `granted_by` what made it,
    # and `expires` when it goes - `encounter` for what the encounter gave out, `rest` for what lasts until
    # the next daily preparations, `turn` until its maker's next turn, nothing for what they keep. An
    # alchemist's preparations are made this way; see `docs/plans/2026-09-22-made-and-granted-items.md`.
    module Equipment

      # The kinds of item, by the collection a holder keeps each in. Bags first, so an item in one can be
      # put in the bag's copy.
      def self.kinds
        [ [ 'bags', PF2Bag ] ] + Pf2egear::Inventory::CATEGORIES.map do |row|
          [ row['collection'].to_s, AresMUSH.const_get(row['model']) ]
        end
      end

      # The links between items, which a copy points at the other copies.
      LINKS = %w{bag shield weapon}.freeze

      # Something made an item for whoever holds it: the encounter gave it out, a rest prepared it, a
      # character crafted it. `expires` says how long it lasts. It is kept apart from anything of the same
      # name that lasts another while, so each goes at its own time: what Quick Alchemy made for a turn is
      # not the two they prepared for the day, nor the two they bought.
      def self.grant!(holder, category, name, quantity, info, granted_by:, expires: nil)
        return Pf2egear.build_item(holder, category, name, info).update(:granted_by => granted_by, :expires => expires) unless
          Pf2egear::Inventory.stackable?(category)

        held = Pf2egear::Inventory.all(holder, category).find do |item|
          item.name == name && !item.copied_from && item.granted_by == granted_by && item.expires == expires
        end

        return held.update(:quantity => held.quantity.to_i + quantity.to_i) if held

        Pf2egear.build_item(holder, category, name, info).update(:quantity => quantity, :granted_by => granted_by, :expires => expires)
      end

      # How soon each kind of lasting ends, soonest first; what they keep lasts longest.
      LASTS = [ 'turn', 'encounter', 'rest', nil ].freeze

      # Items with the ones that will be gone soonest first, which is the one to use up of two alike.
      def self.soonest_first(items)
        items.sort_by.with_index { |item, at| [ LASTS.index(item.expires) || LASTS.size, at ] }
      end

      # What lasts no longer than this, gone: the day's preparations at the next rest, what Quick Alchemy
      # made at the maker's next turn. A creature carries nothing of its own, so it has none of this.
      def self.lapse!(holder, expires)
        return unless Actors.of(holder).carries_items?

        kinds.each do |collection, _model|
          holder.public_send(collection).to_a.select { |item| item.expires == expires }.each(&:delete)
        end
      end

      def self.copies(state)
        kinds.flat_map { |collection, _model| state.public_send(collection).to_a }
      end

      # Copies what `from` carries - a character, or their state in an earlier encounter - to `state`.
      def self.copy!(state, from)
        copied = {}
        made = []

        kinds.each do |collection, model|
          from.public_send(collection).to_a.each do |item|
            copy = copy_item(state, model, item)

            copied[[ model, item.id ]] = copy
            made << [ item, copy ]
          end
        end

        link!(made, copied)

        state.update(:pf2_money => from.pf2_money.to_i, :consumables_at_start => started_with(state))
      end

      def self.copy_item(state, model, item)
        own = item.attributes.except(:character_id, :state_id, :created_at, :updated_at, :copied_from,
                                     *LINKS.map { |link| :"#{link}_id" })

        model.create(own.merge(:state => state, :copied_from => item.copied_from || item.id))
      end

      # Each copy linked as its item is: to the copy of the item's bag, shield or weapon. `copied` is the
      # copies by `[ model, the id of the item copied ]`.
      def self.link!(made, copied)
        made.each do |item, copy|
          links = LINKS.select { |link| item.respond_to?(link) && item.public_send(link) }
                       .to_h { |link| [ link.to_sym, copied[[ item.public_send(link).class, item.public_send(link).id ]] ] }

          copy.update(links) unless links.empty?
        end
      end

      # What a character carries in an encounter made what their sheet holds now, for a GM who lets them
      # have what they bought since joining, or invest what they forgot to. What they had already is kept
      # as they have it here - drawn, stowed, its charges spent - except whether it is invested and what
      # runes it has, which are the sheet's; and a consumable less what they used of it here. What their sheet no
      # longer holds goes, and what the encounter gave them stays. Their money is their sheet's.
      def self.resync!(state, char)
        copied = {}
        made = []
        started = state.consumables_at_start || {}

        kinds.each do |collection, model|
          own = char.public_send(collection).to_a
          theirs = state.public_send(collection).to_a.select { |copy| from_sheet?(copy, model, char) }
                        .group_by { |copy| copy.copied_from.to_s }

          theirs.each { |source, copies| copies.each(&:delete) unless own.any? { |item| item.id.to_s == source } }

          own.each do |item|
            copy = Array(theirs[item.id.to_s]).first

            if copy.nil?
              copy = copy_item(state, model, item)
              made << [ item, copy ]
            elsif collection == 'consumables'
              # What came in less what they used of it here.
              left = copy.quantity.to_i + item.quantity.to_i - (started.dig(item.id.to_s, 'quantity') || copy.quantity).to_i
              left.positive? ? copy.update(:quantity => left) : copy.delete
            elsif Pf2egear::Inventory.stackable?(collection)
              copy.update(:quantity => item.quantity)
            else
              facts = facts_of(model, item)
              copy.update(facts) unless facts.empty?
            end

            copied[[ model, item.id ]] = copy
          end
        end

        link!(made, copied)

        # The consumables they came in with are now their sheet's, and what is used of them settles from there.
        baseline = char.consumables.to_a.to_h { |one| [ one.id.to_s, { 'quantity' => one.quantity.to_i, 'name' => one.name } ] }
        state.update(:pf2_money => char.pf2_money.to_i, :consumables_at_start => baseline)
      end

      # What an item is, which the sheet decides even mid-encounter: whether it is invested and what runes
      # it has. Whether it is drawn, and what is spent of it, happened in the encounter and stays.
      FACTS = %i{invested invest_on_refresh runes}.freeze

      def self.facts_of(model, item)
        held = model.attributes.map(&:to_sym)

        FACTS.select { |field| held.include?(field) }.to_h { |field| [ field, item.public_send(field) ] }
      end

      # Whether a copy is of something on the character's own sheet, or was: the encounter's own - what it
      # gave, what was made to last a while, what an earlier encounter's copy held - is not.
      def self.from_sheet?(copy, model, char)
        return false if copy.copied_from.nil? || copy.expires

        source = model[copy.copied_from]

        source.nil? || source.character_id.to_s == char.id.to_s
      end

      # The running encounter that carries a copy of an item of a character's own, if one does. What they
      # carried in is that encounter's until it ends, so it is neither used nor sold on their sheet
      # meanwhile: they would have it twice. A copy is no character's, and is held by nothing.
      def self.held_by(item)
        char = item.respond_to?(:character) ? item.character : nil

        return nil unless char

        collection = kinds.find { |_collection, model| item.is_a?(model) }&.first

        PF2Encounter.running_for(char).to_a.find do |encounter|
          state = CombatantStates.of(encounter, char)
          state && state.public_send(collection).to_a.any? { |copy| copy.copied_from.to_s == item.id.to_s }
        end
      end

      # What of the copy becomes the character's own when the encounter ends: what it gave them to keep.
      # Anything made to last a while - for the encounter, the day or a turn - is the encounter's and goes
      # with it: whoever joins another fresh joins rested, and the day's preparations are made again.
      def self.kept(state)
        kinds.flat_map do |collection, model|
          state.public_send(collection).to_a.reject(&:copied_from).reject(&:expires).map { |one| [ model, one ] }
        end
      end

      # The encounter has ended: what it did to the character's own consumables happens to them. Answers
      # what it could not do - an item they no longer have - as events, for whoever tells it.

      def self.settle!(state)
        char = state.character

        return [] unless char

        now = state.consumables.to_a
        held = now.select(&:copied_from).to_h { |one| [ one.copied_from.to_s, one ] }
        missed = []

        (state.consumables_at_start || {}).each do |source, started|
          used = started['quantity'].to_i - (held[source]&.quantity).to_i

          next unless used.positive?

          missed << used_up(char, source, started['name'], used)
        end

        kept(state).each do |model, gained|
          own = gained.attributes.except(:character_id, :state_id, :created_at, :updated_at, :copied_from,
                                         *LINKS.map { |link| :"#{link}_id" })

          gained.update(:copied_from => model.create(own.merge(:character => char)).id)
        end

        # Settled up to here: an encounter restarted and ended again settles only what happened since.
        state.update(:consumables_at_start => started_with(state))

        missed.compact
      end

      # What they came in with, by the item of their own each copy was taken from. What the encounter gave
      # them has none, and settles nothing.
      def self.started_with(state)
        state.consumables.to_a.select(&:copied_from)
             .to_h { |one| [ one.copied_from.to_s, { 'quantity' => one.quantity.to_i, 'name' => one.name } ] }
      end

      def self.used_up(char, source, name, used)
        item = PF2Consumable[source]

        return Turns.event('pf2e.settle_missing', 'name' => char.name, 'item' => name) unless item && item.character == char

        left = item.quantity.to_i - used

        left.positive? ? item.update(:quantity => left) : item.delete

        nil
      end
    end
  end
end
