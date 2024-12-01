module AresMUSH
  module Tinker
    class TinkerCmd
      include CommandHandler
      
      def handle
        stages = { "skills" => "6", "abilities" => "5", "info" => "4" }
        chargen_stage = "6"
        checkpoint = "skills"
        if stages[checkpoint] == chargen_stage
          client.emit "You can't do that. (Good ending)"
        else
          client.emit "You can do it! (Bad ending)"
        end
      end

    end
  end
end
