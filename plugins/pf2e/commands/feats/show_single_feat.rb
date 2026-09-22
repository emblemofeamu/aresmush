module AresMUSH
  module Pf2e

    class PF2FeatDisplayOneCmd
      include CommandHandler

      attr_accessor :featname, :feat_displayname

      def parse_args
        self.featname = upcase_arg(cmd.args)
        self.feat_displayname = titlecase_arg(cmd.args)
      end

      def required_args
        [ self.featname ]
      end

      def handle

        feat_list = Global.read_config('pf2e_feats')

        match = feat_list.select { |k,v| k.upcase == self.featname }

        if match.empty?
          client.emit_failure Pf2e.bad_feat_message(self.feat_displayname)
          return
        end

        list_details = Pf2e.generate_list_details(match)

        paginator = Paginator.paginate(list_details, cmd.page, 3)

        if (paginator.out_of_bounds?)
          client.emit_failure paginator.out_of_bounds_msg
          return
        end

        title = "Feat Details for #{self.feat_displayname}"

        template = PF2eFeatDisplay.new(paginator, title)

        client.emit template.render
        
      end
    end

  end
end
