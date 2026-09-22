module AresMUSH
  module Pf2e

    class PF2FeatSearchCmd
      include CommandHandler

      attr_accessor :search_type, :search_term

      # The searches that take something in front of the term: a comparison for level, a class for
      # classlevel. Everywhere else the whole argument is the term, so a name may run to as many
      # words as it likes.
      OPERATOR_TYPES = %w{level classlevel}.freeze

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.search_type = downcase_arg(args.arg1)
        self.search_term = trim_arg(args.arg2)

      end

      # [ term, operator ], with the operator nil on every search that does not take one.
      def term_and_operator
        return [ self.search_term.to_s, nil ] unless OPERATOR_TYPES.include?(self.search_type)

        operator, _, term = self.search_term.to_s.strip.partition(' ')

        return [ self.search_term.to_s, nil ] if term.strip.empty?

        [ term.strip, operator ]
      end

      def required_args
        [ self.search_type, self.search_term ]
      end

      def check_search_type 
        valid_types = [ 'name', 
          'traits', 
          'feat_type', 
          'level', 
          'class', 
          'classlevel',
          'ancestry', 
          'skill',
          'description',
          'desc',
          'archetype'
        ]

        return nil if valid_types.include? self.search_type
        return t('pf2e.bad_option', :options => valid_types.sort.join(', '), :element => "search type")
      end

      def handle

        term, operator = term_and_operator

        match = Pf2e.search_feats(self.search_type, term.upcase, operator)

        if match.empty?
          client.emit_failure Pf2e::Renames.hint_for('feats', term, Global.read_config('pf2e_feats').keys) ||
                              t('pf2e.nothing_to_display', :elements => 'feats')
          return
        end

        list_details = Pf2e.generate_list_details(match)

        paginator = Paginator.paginate(list_details, cmd.page, 3)

        if (paginator.out_of_bounds?)
          client.emit_failure paginator.out_of_bounds_msg
          return
        end

        search_args = operator ? "#{self.search_type}=#{operator} #{term}" : "#{self.search_type}=#{term}"
        title = "Feat Search Results (#{search_args})"
        page_notice = nil
        if paginator.total_pages > 1 && paginator.current_page < paginator.total_pages
          next_page = paginator.current_page + 1
          page_command = "feat/search#{next_page} #{search_args}"
          page_notice = t('pf2e.feat_search_next_page', :command => page_command)
        end

        template = PF2eFeatDisplay.new(paginator, title, page_notice)

        client.emit template.render

      end


    end
  
  end 
end