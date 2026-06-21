module AresMUSH
  module Pf2e

    class PF2FeatOptionsCmd
      include CommandHandler

      attr_accessor :search_type, :assign_type

      def parse_args
        self.search_type = titlecase_arg(cmd.args)
        arg = downcase_arg(cmd.args)
        self.assign_type = arg ? arg + " feat" : nil
      end

      def required_args
        [ self.search_type ]
      end

      def check_is_special_feat
        if self.search_type == "Special"
          return t('pf2e.no_feat_option_special')
        else
          return nil
        end
      end

      def check_chargen_or_advancement
        if enactor.chargen_locked && !enactor.advancing || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def handle
        
        to_assign = enactor.pf2_to_assign

        # Does the character need to assign this feat? 

        if !(to_assign[self.assign_type])
          client.emit_failure t('pf2e.no_free', :element => self.assign_type)
          return
        end

        # Do it. 

        EventMachine.defer(
          proc {
            options = Pf2e.get_feat_options(enactor, self.search_type)
            options
          },

          proc { |options|
            client.emit t('pf2e.feat_available_options', :options => options.sort.join(", "))
          }
        )
      end



    end
  
  end 
end