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

      # Every pair needs both halves. A term with no `=` used to reach nil.split and take the
      # command down with "undefined method `split' for nil", which is what a player gets for
      # typing `spell/search arcane` - and this is the command the magic help sends them to when
      # they do not know a spell's name.
      def check_search_term
        return t('pf2emagic.bad_search_syntax') if self.search.any? { |t| t[1].to_s.strip.empty? }

        # One term, or an operator and a term. More than that is not a search this understands.
        return t('pf2emagic.bad_search_syntax') unless self.search.all? { |t| t[1].split.size <= 2 }

        nil
      end

      def handle

        # Break down each search term and get results for it.

        # Start with all spells.

        spells = Global.read_config('pf2e_spells').keys

        # Iterate through each term and narrow down the list with each search.
        self.search.each do |argument|

          search_type = argument[0].downcase
          termoperator = argument[1].split(" ")

          if termoperator[1]
            operator = termoperator[0]
            term = termoperator[1]
          else
            # Operator has default defined in search_spells.
            term = termoperator[0]
            operator = nil
          end

          result = Pf2emagic.search_spells(search_type, term, operator)

          spells = result.intersection(spells)

        end

        if spells.empty?
          client.emit_failure t('pf2e.nothing_to_display', :elements => 'spells')
          return
        end

        template = PF2DisplayManySpellTemplate.new(spells, client)

        client.emit template.render

      end

    end
  end
end
