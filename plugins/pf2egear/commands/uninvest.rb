module AresMUSH
  module Pf2egear
    class PF2UninvestCmd
      include CommandHandler

      attr_accessor :to_uninvest

      def parse_args
        self.to_uninvest = trimmed_list_arg(cmd.args)

      end

      def required_args
        [ self.to_uninvest ]
      end

      def handle

        ### VALIDATION SECTION ###

        valid_cats = Pf2egear::Inventory.categories.select { |c| Pf2egear::Inventory.investable?(c) }

        # Check for correct format.

        format_check = []

        self.to_uninvest.each do |item|

          args = item.split("/")
          category = args[0]
          num = args[1]

          is_int = num&.to_i.to_s == num ? true : false

          format_check << "not a number" unless is_int

          format_check << "bad category" unless valid_cats.include? category
        end

        # Assemble list of object ID's to be uninvested.

        if !format_check.empty?
          client.emit_failure t('pf2egear.bad_format', :cmd => "uninvest")
          return
        end

        uninvest_list = []

        self.to_uninvest.each do |item|

          args = item.split("/")
          category = args[0]
          num = args[1].to_i

          found = Pf2egear::Inventory.item(enactor, category, num)

          next if Pf2e::CharState.emit_error!(client, found)

          found.state.update(:invest_on_refresh => false)

          uninvest_list << found.state.name

        end


        client.emit_success t('pf2egear.items_uninvested_ok', :count => uninvest_list.size)

      end

    end
  end
end
