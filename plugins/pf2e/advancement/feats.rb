module AresMUSH
  module Pf2e
    module Advancement

      # Spending a feat slot a level handed out.
      #
      # Whether a given feat may go in a given slot is a chain of nine questions, and they were
      # nine sequential blocks inside advance/feat's single method. GUARDS is that chain, in
      # order, so the first complaint a player gets is still the most specific one - and so the
      # chain can be read without reading the four hundred lines that followed it.
      module Feats

        # Each row: what makes it a problem, and what to say. `check` returns the Err or nil,
        # because several of them carry values the message needs.
        GUARDS = [
          # 'class' is what a player naturally types for a class feat, and the slot is called
          # 'charclass'. Saying so is kinder than "not an option".
          {
            'name' => 'class_is_charclass',
            'check' => lambda { |ctx|
              next nil unless ctx[:type] == 'class'

              Err.new(:use_charclass, 'pf2e.adv_dont_use_class_for_class_feats', 'feat' => ctx[:value])
            }
          },
          {
            'name' => 'level_grants_this_type',
            'check' => lambda { |ctx|
              ctx[:slot].nil? ? Err.new(:not_an_option, 'pf2e.adv_not_an_option') : nil
            }
          },
          {
            'name' => 'a_slot_is_open',
            'check' => lambda { |ctx|
              next nil if Array(ctx[:slot]).include?('open')

              Err.new(:no_free, 'pf2e.no_free', 'element' => "#{ctx[:type]} feat")
            }
          },
          {
            'name' => 'feat_type_matches_slot',
            'check' => lambda { |ctx|
              # The feat's own types, not the game's: the message says which slots this feat fits,
              # which read as "general is not a feat type" while it was worded as a list to
              # choose from.
              types = Array(ctx[:details]['feat_type']).compact.map { |f| f.to_s.downcase }

              next nil if types.include?(ctx[:type])

              Err.new(:bad_feat_type, 'pf2e.bad_feat_type', 'type' => ctx[:type], 'keys' => types.sort.join(", "))
            }
          }
        ].freeze

        # The pure half: is this feat allowed in this slot, as far as the draft can tell?
        #
        # The questions that need the live character - does it already have the archetype feats
        # a Dedication wants, does it double-dip on the base class, has it been taken as often
        # as it may be, does it meet its prerequisites - stay in the shell, because each reads
        # the sheet through helpers that take a character. They run after these.
        def self.check_slot(state, type, value, details)
          ctx = {
            :type => type.to_s,
            :value => value,
            :details => details || {},
            :slot => (state['to_assign']['feats'] || {})[type.to_s]
          }

          GUARDS.each do |guard|
            failure = guard['check'].call(ctx)

            return failure if failure
          end

          nil
        end

        # Spends the open slot on the feat. The rest of what gaining a feat means is
        # Advancement::FeatGain, which every path that grants a feat goes through.
        def self.spend_slot(state, type, feat)
          feats = state['to_assign']['feats'] || {}
          slots = Array(feats[type.to_s]).dup
          index = slots.index('open')

          return Err.new(:no_free, 'pf2e.no_free', 'element' => "#{type} feat") if index.nil?

          slots[index] = feat

          Ok.new(:state => state.merge('to_assign' => state['to_assign'].merge('feats' => feats.merge(type.to_s => slots))))
        end
      end
    end
  end
end
