module AresMUSH
  module Pf2e

    class PF2FeatSearchCmd
      include CommandHandler

      attr_accessor :search_type, :search_term

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.search_type = downcase_arg(args.arg1)
        self.search_term = trimmed_list_arg(args.arg2)

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

        if self.search_term[1]
          term = self.search_term[1]
          operator = self.search_term[0]
        else 
          # Operator has default defined in search_feats.
          term = self.search_term[0].upcase
        end

        match = Pf2e.search_feats(self.search_type, term, operator)

        if match.empty?
          client.emit_failure t('pf2e.nothing_to_display', :elements => 'feats')
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