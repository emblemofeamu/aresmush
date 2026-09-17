module AresMUSH
  module Pf2emagic
    class PF2SearchSpellCmd
      include CommandHandler

      attr_accessor :search

      def parse_args
        if cmd.args
          search_list = trimmed_list_arg(cmd.args, ", ")

          # At most two parts, so a term that itself holds an `=` stays whole.
          self.search = search_list.map { |term| term.split("=", 2) }
        else
          self.search = nil
        end

      end

      def required_args
        [ self.search ]
      end

      def check_search_type
        valid_types = [ 'name',
          'traits',
          'level',
          'tradition',
          'bloodline',
          'cast',
          'description',
          'desc',
          'effect'
        ]

        check = []

        self.search.each { |t| check << valid_types.include?(t.first.downcase) }

        return nil if check.all?
        return t('pf2emagic.invalid_search_type', :options => valid_types.sort)
      end

      # Only a level search takes something in front of its term. Everywhere else the whole
      # argument is the term, so a spell called Wall of Fire is searchable by its name.
      OPERATOR_TYPES = %w{level}.freeze

      # Every pair needs both halves. A term with no `=` used to reach nil.split and take the
      # command down with "undefined method `split' for nil", which is what a player gets for
      # typing `spell/search arcane` - and this is the command the magic help sends them to when
      # they do not know a spell's name.
      def check_search_term
        return t('pf2emagic.bad_search_syntax') if self.search.any? { |t| t[1].to_s.strip.empty? }

        # A level search is one term, or a comparison and a term. More than that is not a search
        # this understands.
        levels = self.search.select { |t| t.first.to_s.downcase == 'level' }

        return t('pf2emagic.bad_search_syntax') unless levels.all? { |t| t[1].split.size <= 2 }

        nil
      end

      # [ term, operator ], with the operator nil on every search that does not take one.
      def term_and_operator(search_type, value)
        return [ value.to_s, nil ] unless OPERATOR_TYPES.include?(search_type)

        operator, _, term = value.to_s.strip.partition(' ')

        return [ value.to_s, nil ] if term.strip.empty?

        [ term.strip, operator ]
      end

      def handle

        # Break down each search term and get results for it.

        # Start with all spells.

        spells = Global.read_config('pf2e_spells').keys

        # Iterate through each term and narrow down the list with each search.
        self.search.each do |argument|

          search_type = argument[0].downcase
          term, operator = term_and_operator(search_type, argument[1])

          result = Pf2emagic.search_spells(search_type, term, operator)

          spells = result.intersection(spells)

        end

        if spells.empty?
          client.emit_failure missing_spell_message
          return
        end

        template = PF2DisplayManySpellTemplate.new(spells, client)

        client.emit template.render

      end

      private

      # A name search that found nothing is the one a rename can explain.
      def missing_spell_message
        named = self.search.find { |pair| pair.first.to_s.downcase == 'name' }
        hint = named && Pf2e::Renames.hint_for('spells', named.last, Global.read_config('pf2e_spells').keys)

        hint || t('pf2e.nothing_to_display', :elements => 'spells')
      end

    end
  end
end
