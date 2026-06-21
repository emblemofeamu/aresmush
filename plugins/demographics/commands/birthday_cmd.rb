module AresMUSH
  module Demographics

    class BirthdateCmd
      include CommandHandler
      
      attr_accessor :name, :date_str
            
      def parse_args
        # Admin version
        if (Demographics.can_set_demographics?(enactor) && cmd.args =~ /\=/)
          args = cmd.parse_args(ArgParser.arg1_equals_arg2)
          self.name = titlecase_arg(args.arg1)
          self.date_str = args.arg2
          # Self version
        else
          self.name = enactor.name
          self.date_str = cmd.args.capitalize # capitalize input so that it takes lowercase months
        end
      end
      
      def required_args
        [ self.name, self.date_str ]
      end
                
      def check_is_allowed
        return nil if self.name == enactor_name
        return t('dispatcher.not_allowed') if !Demographics.can_set_demographics?(enactor)
        return nil
      end
      
      def check_chargen_locked
        return nil if Chargen.can_manage_apps?(enactor)        
        enabled_after_cg = Global.read_config("demographics", "editable_properties")
        return nil if enabled_after_cg.include?('birthdate')
        Chargen.check_chargen_locked(enactor)
      end
      
      def handle
        rl_months = Date::MONTHNAMES
        ic_months = [ nil ] + Global.read_config("ictime",)["month_names"]
        formatted_date_str = ""

        # Determine which date_str format is used and normalize to "Month Day, Year"
        # Find format
        if self.date_str.match(/(\d+)\/(\d+)\/(\d+)/)
          month = ic_months[$1.to_i]
          day = $2.to_i
          year = $3.to_i
        elsif self.date_str.match(/([a-zA-Z]+) (\d+),? (\d+)/)
          if ic_months.include?($1)
            month = $1
          elsif rl_months.include?($1)
            month = ic_months[rl_months.index($1)]
          end
          day = $2.to_i
          year = $3.to_i
        end

        # Format the constituents into a standard string
        formatted_date_str = "#{rl_months[ic_months.index(month)]} #{day}, #{year}"

        ClassTargetFinder.with_a_character(self.name, client, enactor) do |model|
          results = Demographics.set_birthday(model, formatted_date_str)

          if (results[:error])
            client.emit_failure results[:error]
            return
          end
          
          bday = results[:bday]
          
          if (self.name == enactor_name)
            client.emit_success t('demographics.birthdate_set', 
            :birthdate => ICTime.ic_datestr(bday), 
            :age => model.age)
          else
            client.emit_success t('demographics.admin_property_set', :name => self.name, :property => "birthdate", :value => self.date_str)
          end
        end
        
      end
    
    end
  end
end