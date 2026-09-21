module AresMUSH
  module Pf2e

    # The XP and money audit. Every transaction is kept, and reading a balance stays cheap.
    #
    # The running total lives on the character (`pf2_xp`, `pf2_money`), so the sheet reads one
    # field. Each transaction is its own Pf2eLedgerEntry row, so appending one rewrites nothing. A
    # Redis sorted set per character per currency puts them in order, so a page of history is a
    # ZREVRANGE and a count is a ZCARD at ten entries or at a hundred thousand.
    #
    # The sorted set is the only place this reaches past Ohm. Ohm has no range query and its
    # collection read loads every row. Scores are entry ids, which Ohm hands out from an
    # incrementing counter, so the index is already in insertion order and has no ties to break.
    module Audit

      # Currency to the character attribute holding its running total. Adding a currency is
      # adding a row.
      CURRENCIES = {
        'xp' => 'pf2_xp',
        'money' => 'pf2_money'
      }.freeze

      # What a character holds before any transaction. Money is given to them at creation and no
      # entry records that gift, so a balance is the opening figure plus every entry since - and
      # without this row a money total could never be checked against its history at all.
      OPENING = {
        'xp' => lambda { 0 },
        'money' => lambda { AresMUSH.const_defined?('Pf2egear') ? Pf2egear::STARTING_MONEY : 0 }
      }.freeze

      def self.currencies
        CURRENCIES.keys
      end

      def self.opening(currency)
        (OPENING[currency.to_s] || lambda { 0 }).call.to_i
      end

      def self.total_attr(currency)
        CURRENCIES[currency.to_s] or raise ArgumentError, "unknown currency #{currency.inspect}"
      end

      def self.index_key(char, currency)
        "pf2e:audit:#{char.id}:#{currency}"
      end

      # ------------------------------------------------------------------------------
      # Writing
      # ------------------------------------------------------------------------------

      # Records a transaction and moves the total. The only thing that may move the total.
      #
      # The entry is written before the total, so a crash between them leaves the total
      # behind rather than leaving a movement unrecorded - the entries can always repair the
      # total, never the other way around.
      def self.post(char, currency, amount, by:, reason: nil, ref: nil)
        attr = total_attr(currency)
        amount = amount.to_i

        return nil if amount.zero?

        balance = char.send(attr).to_i + amount

        # An entry exists to say why the total moved, so a blank one is a gap in the record rather
        # than a tidy default. The line still gets written - refusing would lose the movement as
        # well as the reason - and the log names the caller to fix.
        if reason.to_s.strip.empty?
          Global.logger.warn("PF2e #{currency} posted with no reason: #{amount} for #{char.name} by #{by}")
          reason = 'Unspecified'
        end

        entry = Pf2eLedgerEntry.create(
          :character => char,
          :currency => currency.to_s,
          :amount => amount,
          :balance_after => balance,
          :at => Time.now.to_i,
          :by => by.to_s,
          :reason => reason.to_s,
          :ref => ref
        )

        Ohm.redis.call("ZADD", index_key(char, currency), entry.id.to_s, entry.id.to_s)

        char.update(attr.to_sym => balance)

        entry
      end

      # ------------------------------------------------------------------------------
      # Reading
      # ------------------------------------------------------------------------------

      # One page, newest first. Loads only the rows on that page.
      def self.page(char, currency, page = 1, per_page = 10)
        total_attr(currency)

        page = [ page.to_i, 1 ].max
        per_page = [ per_page.to_i, 1 ].max
        first = (page - 1) * per_page

        ids = Ohm.redis.call("ZREVRANGE", index_key(char, currency), first.to_s, (first + per_page - 1).to_s)

        Array(ids).map { |id| Pf2eLedgerEntry[id] }.compact
      end

      def self.count(char, currency)
        total_attr(currency)

        Ohm.redis.call("ZCARD", index_key(char, currency)).to_i
      end

      def self.total_pages(char, currency, per_page = 10)
        per_page = [ per_page.to_i, 1 ].max
        pages = (count(char, currency).to_f / per_page).ceil

        [ pages, 1 ].max
      end

      # A page in the shape the engine's templates expect. Built from a count and one page of
      # rows rather than from the whole list, which is the only difference that matters.
      def self.paginate(char, currency, page = 1, per_page = 10)
        page = [ page.to_i, 1 ].max
        per_page = [ per_page.to_i, 1 ].max

        PaginateResults.new(page, total_pages(char, currency, per_page), page(char, currency, page, per_page), (page - 1) * per_page)
      end

      # ------------------------------------------------------------------------------
      # Checking and repairing
      # ------------------------------------------------------------------------------

      # Walks every entry. Only for a staff check or a migration - never on a player command.
      def self.sum(char, currency)
        ids = Array(Ohm.redis.call("ZRANGE", index_key(char, currency), "0", "-1"))

        ids.sum { |id| Pf2eLedgerEntry[id]&.amount.to_i }
      end

      def self.consistent?(char, currency)
        opening(currency) + sum(char, currency) == char.send(total_attr(currency)).to_i
      end

      # Puts the total back to what the entries say it should be. The entries are the record;
      # the total is a cache of their sum that exists so the sheet does not have to add them up.
      def self.repair!(char, currency)
        attr = total_attr(currency)
        correct = opening(currency) + sum(char, currency)

        return false if char.send(attr).to_i == correct

        char.update(attr.to_sym => correct)

        true
      end

      # ------------------------------------------------------------------------------
      # Housekeeping
      # ------------------------------------------------------------------------------

      def self.delete_all!(char, currency = nil)
        Array(currency ? [ currency.to_s ] : currencies).each do |cur|
          ids = Array(Ohm.redis.call("ZRANGE", index_key(char, cur), "0", "-1"))

          ids.each { |id| Pf2eLedgerEntry[id]&.delete }

          Ohm.redis.call("DEL", index_key(char, cur))
        end
      end
    end
  end
end
