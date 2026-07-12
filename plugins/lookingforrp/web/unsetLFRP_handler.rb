module AresMUSH
  module LookingForRp
    class UnsetLFRPHandler
      def handle(request)
        puts request.args
        enactor = request.enactor

        LookingForRp.expire(enactor)

        error = Website.check_login(request)
        return error if error

        {
        }
      end
    end
  end
end