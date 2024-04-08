module AresMUSH
  module Pf2e
    class PF2SkillListCmd
      include CommandHandler

      attr_accessor :term

      def parse_args
        self.term = downcase_arg(cmd.args)
      end

      def handle
        skills_list = Global.read_config('pf2e_skills').keys - Global.read_config('pf2e', 'hidden_options')

        if self.term
          skills_list = skills_list.filter { |skill| skill.downcase.match? self.term }
        end

        paginator = Paginator.paginate(skills_list, cmd.page, 30)
        if (paginator.out_of_bounds?)
          client.emit_failure paginator.out_of_bounds_msg
          return
        end

        template = PF2SkillsListTemplate.new(paginator)

        client.emit template.render


      end
    end
  end
end
