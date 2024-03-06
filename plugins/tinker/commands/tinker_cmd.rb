module AresMUSH
  module Tinker
    class TinkerCmd
      include CommandHandler
      
      def check_can_manage
        return t('dispatcher.not_allowed') if !enactor.has_permission?("tinker")
        return nil
      end
      
      def handle
      
        char = Character.find_one_by_name("Davi")
        value = { "cantrip" => 5, 1 => 3, 2 => 1} 
        
        to_assign = char.pf2_to_assign

        assignment_list = {}
        value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
        end

        to_assign["repertoire"] = assignment_list

        char.update(pf2_to_assign: to_assign)
        
      end

    end
  end
end
