module AresMUSH
  module Pf2emagic

    # Every spell the character could put in a slot, per spellcasting source and rank.
    #
    # Picking a spell meant guessing a name and reading whichever refusal came back - wrong
    # tradition, wrong rank, not in the database. This answers the question first.
    class PF2SpellEligibleCmd
      include CommandHandler

      attr_accessor :rank, :filter

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.rank = downcase_arg(args.arg1)
        self.filter = trim_arg(args.arg2)
      end

      def handle
        sources = Pf2emagic::Entries.for_magic(enactor.magic).reject { |entry| entry['tradition'].blank? }

        if sources.empty?
          client.emit_failure t('pf2emagic.not_a_caster')
          return
        end

        if self.rank.blank?
          client.emit t('pf2emagic.eligible_ranks', :sources => source_lines(sources).join("%r"))
          return
        end

        show_rank(sources)
      end

      private

      # Each source, the tradition it draws on, and the command that lists a rank of it.
      def source_lines(sources)
        sources.map do |entry|
          t('pf2emagic.eligible_source', :source => entry['name'], :tradition => entry['tradition'],
                                         :cmd => "spell/eligible <rank>")
        end
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
