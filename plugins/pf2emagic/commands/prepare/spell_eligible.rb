module AresMUSH
  module Pf2emagic

    # Every spell the character could put in a slot, per spellcasting source and rank.
    #
    # Picking a spell meant guessing a name and reading whichever refusal came back - wrong
    # tradition, wrong rank, not in the database. This answers the question first.
    class PF2SpellEligibleCmd
      include CommandHandler

      attr_accessor :rank, :filter

      # `<rank>`, `<rank>=<text>`, or neither. The same shape `cg/info` and `advance/info` take, and
      # for the same reason: a parser that insists on the `=` refuses the forms the help offers.
      def parse_args
        rank, self.filter = Pf2e.split_info_filter(cmd.args)

        self.rank = rank&.downcase
      end

      def handle
        sources = Pf2emagic::Entries.for_magic(enactor.magic).reject { |entry| entry['tradition'].blank? }

        if sources.empty?
          client.emit_failure t('pf2emagic.not_a_caster')
          return
        end

        if self.rank.blank?
          client.emit t('pf2emagic.eligible_ranks', :sources => source_lines(sources).join("%r"),
                                                    :example => example_rank(sources))
          return
        end

        show_rank(sources)
      end

      private

      # Each source, the tradition it draws on, and the ranks the character has of it - a level 3
      # sorcerer is offered cantrips and rank 1 and 2, rather than an example they cannot cast.
      def source_lines(sources)
        sources.map do |entry|
          t('pf2emagic.eligible_source', :source => entry['name'], :tradition => entry['tradition'],
                                         :ranks => ranks_of(entry).join(", "))
        end
      end

      CANTRIP = 'cantrip'.freeze

      def ranks_of(entry)
        highest = Pf2e.preview_max_spell_rank(enactor, entry['name']).to_i

        [ CANTRIP ] + (1..highest).to_a.map(&:to_s)
      end

      # A rank this character actually has, for the hint to name.
      def example_rank(sources)
        sources.flat_map { |entry| ranks_of(entry) }.max_by { |rank| rank.to_i }
      end

      def show_rank(sources)
        traditions = sources.map { |entry| entry['tradition'].to_s.downcase }.uniq
        options = traditions.flat_map { |tradition| Pf2emagic.eligible_spells(tradition, self.rank) }.uniq.sort

        title = t('pf2emagic.eligible_title', :rank => self.rank, :traditions => traditions.join(", "))
        display = Pf2e.info_option_display(title, options, cmd.page, self.filter)

        display[:error] ? client.emit_failure(display[:error]) : client.emit(display[:text])
      end
    end
  end
end
