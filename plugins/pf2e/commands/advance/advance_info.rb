module AresMUSH
  module Pf2e

    class PF2AdvanceInfoCmd
      include CommandHandler

      attr_accessor :element

      def parse_args
        self.element = trim_arg(cmd.args)
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        # No element given, so list what they currently have outstanding.
        if self.element.blank?
          show_pending
          return
        end

        # Advancement-specific elements first, then the shared vocabulary.
        found = class_option_element || Pf2e.info_options(enactor, self.element)

        unless found
          client.emit_failure t('pf2e.bad_option', :element => "advance/info", :options => pending_elements.join(", "))
          return
        end

        display = Pf2e.info_option_display(found[0], found[1], cmd.page)

        if display[:error]
          client.emit_failure display[:error]
        else
          client.emit display[:text]
        end
      end

      # A class feature option awaiting a pick, as [ title, options ].
      def class_option_element
        to_assign = enactor.pf2_to_assign || {}
        feature_list = to_assign['class option'] || to_assign['charclass'] || to_assign['charclass option']

        return nil unless feature_list.is_a?(Hash)

        feature = feature_list.keys.find { |f| f.to_s.casecmp?(self.element.to_s) }
        return nil unless feature

        options = feature_list[feature]

        # A resolved feature renders the chosen value as a bare string, not a list to pick from.
        return nil if options.is_a?(String)

        list = if options.is_a?(Hash)
          options.keys
        else
          Array(options).map { |opt| opt.is_a?(Array) ? opt.first : opt }
        end

        [ feature, list.sort ]
      end

      # Everything the character could usefully ask about right now.
      def pending_elements
        to_assign = enactor.pf2_to_assign || {}

        elements = Pf2e.pending_feat_choices(enactor).keys

        feature_list = to_assign['class option'] || to_assign['charclass'] || to_assign['charclass option']
        elements.concat(feature_list.keys) if feature_list.is_a?(Hash)

        pending_feats = to_assign['feats']

        if pending_feats.is_a?(Hash)
          pending_feats.each_pair do |type, slots|
            elements << "#{type} feat" if Array(slots).include?('open')
          end
        end

        elements.uniq.sort
      end

      def show_pending
        elements = pending_elements

        if elements.empty?
          client.emit_ooc t('pf2e.info_nothing_pending')
          return
        end

        client.emit t('pf2e.info_pending', :elements => elements.join(", "))
      end

    end
  end
end
