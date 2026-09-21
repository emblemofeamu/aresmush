module AresMUSH
  module Pf2e

    # Every feat the character is eligible for, in each slot this level has left open.
    #
    # `advance/info <type>` answers one slot type, which only helps a player who already knows the
    # vocabulary - general, skill, ancestry, charclass, archetype. This asks the question a player
    # actually has: what can I take right now.
    class PF2AdvanceFeatsCmd
      include CommandHandler

      attr_accessor :slot_type, :filter

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.slot_type = downcase_arg(args.arg1)
        self.filter = trim_arg(args.arg2)
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        types = Pf2e.open_feat_slot_types(enactor)

        if types.empty?
          client.emit_ooc t('pf2e.no_open_feat_slots')
          return
        end

        wanted = self.slot_type.blank? ? types : types.select { |type| type.casecmp?(self.slot_type) }

        if wanted.empty?
          client.emit_failure t('pf2e.bad_option', :element => 'feat slot', :options => types.join(", "))
          return
        end

        # One slot type reads as a list to pick from and pages; several read as a summary, because
        # paginating three lists at once would page each of them independently.
        wanted.size == 1 ? show_one(wanted.first) : show_each(wanted)
      end

      private

      def show_one(type)
        display = Pf2e.info_option_display(t('pf2e.info_feat_title', :type => type.capitalize),
                                           Pf2e.get_feat_options(enactor, type), cmd.page, self.filter)

        display[:error] ? client.emit_failure(display[:error]) : client.emit(display[:text])
      end

      def show_each(types)
        lines = types.map do |type|
          options = narrowed(Pf2e.get_feat_options(enactor, type))

          t('pf2e.feats_open_slot', :type => type.capitalize, :count => options.size,
                                    :cmd => "advance/feats #{type}")
        end

        client.emit t('pf2e.feats_open_summary', :slots => lines.join("%r"))
      end

      def narrowed(options)
        return options if self.filter.blank?

        wanted = self.filter.to_s.strip.downcase

        options.select { |option| option.to_s.downcase.include?(wanted) }
      end
    end
  end
end
