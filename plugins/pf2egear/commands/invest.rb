module AresMUSH
  module Pf2egear
    class PF2InvestCmd
      include CommandHandler

      attr_accessor :to_invest

      def parse_args
        self.to_invest = trimmed_list_arg(cmd.args)

      end

      def required_args
        [ self.to_invest ]
      end

      def handle

        ### VALIDATION SECTION ###

        valid_cats = Pf2egear::Inventory.categories.select { |c| Pf2egear::Inventory.investable?(c) }

        # Check for correct format.

        format_check = []

        self.to_invest.each do |item|

          args = item.split("/")
          category = args[0]
          num = args[1]

          is_int = num&.to_i.to_s == num ? true : false

          format_check << "not a number" unless is_int

          format_check << "bad category" unless valid_cats.include? category
        end

        # Mark objects for investment at next refresh.

        if !format_check.empty?
          client.emit_failure t('pf2egear.bad_format', :cmd => "invest")
          return
        end

        max_investable = Pf2e.has_feat?(enactor, 'Incredible Investiture') ? 12 : 10

        # Every item PF2e lets a character invest, which Inventory says rather than this command.
        investable_list = valid_cats.map { |c| Pf2egear::Inventory.canonical(c) }.uniq
                                    .flat_map { |c| Pf2egear::Inventory.held(enactor, c) }

        already_invested = investable_list.select { |item| item.invest_on_refresh }

        counter = already_invested.size

        self.to_invest.each do |item|

          args = item.split("/")
          category = args[0]
          num = args[1].to_i

          found = Pf2egear::Inventory.item(enactor, category, num)

          next if Pf2e::CharState.emit_error!(client, found)

          item_id = found.state

          if Array(item_id.traits).include? 'invested'

            if item_id.invest_on_refresh
              client.emit_failure t('pf2egear.already_set_for_investment')
              return
            end

            counter = counter + 1

            if counter > max_investable
              client.emit_failure t('pf2egear.too_many_invested', :max => max_investable)
              return
            end

            item_id.update(invest_on_refresh: true)

          else
            client.emit_ooc t('pf2egear.not_investible_item', :item => Pf2egear.get_item_name(item_id))
          end

          client.emit_success t('pf2egear.items_invested_ok', :count => counter)


        end


      end

    end
  end
end
