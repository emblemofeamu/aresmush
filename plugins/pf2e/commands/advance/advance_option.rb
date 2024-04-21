module AresMUSH
  module Pf2e

    class PF2AdvanceOptionCmd
      include CommandHandler

      # Command is used to select things like feat grants and special class items such as Path to Perfection.

      # Syntax advance/option self.type/self.option = self.value

      attr_accessor :type, :option, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.type = downcase_arg(args.arg1)
        self.option = downcase_arg(args.arg2)
        self.value = downcase_arg(args.arg3)
      end

      def required_args
        [ self.type, self.option, self.value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        to_assign = enactor.pf2_to_assign || {}
        advancement = enactor.pf2_advancement || {}


        case self.type
        when "charclass"
          # Class Options Piece
          # Expect self.option to be the name of the class option, should be in advance/review
          # self.value will be an option.

          feature_list = to_assign['charclass']

          unless feature_list
            client.emit_failure t('pf2e.adv_not_an_option')
            return
          end

          fkeys = feature_list.keys || []
          feature = fkeys.select {|f| f.downcase == self.option }.first

          unless feature
            client.emit_failure t('pf2e.adv_not_an_option')
            return
          end

          options = feature_list[feature]

          is_valid = Pf2e.valid_class_option?(enactor, feature, self.value)

          unless is_valid
            client.emit_failure t('pf2e.bad_option', :element => feature, :options => options.join(", "))
            return
          end

          options = self.value

          feature_list[feature] = options
          to_assign['charclass option'] = feature_list

          advancement['charclass option'] = feature_list
        when "skillful lesson"
          # This is just a gated feat with the gate "Skillful Lesson". Make sure they have this.


          # Is it open?

          # Can they pick that feat for skillful lesson?
        when "grant"
          # Grants Piece
          #
          # Lanier - this should be triggered if self.type has a value of 'grant'
          # Expect self.option to be the name of the feat that granted it.
          # self.value should call the key they want to pick.
          # Structure of to_assign and advancement for this:
          # { 'grants' => {'<feat name>' => {<contents of grants key from YML>}}}
          #
          # The advancement assess_ helpers split the contents of a complex YML key into what has to be picked
          # and what can be added to the sheet as-is. Anything to be picked goes into pf2_to_assign and anything that
          # can just be handled goes into pf2_advancement.
          #
          # advance/done directs the game to process the contents of pf2_advancement and add everything to the sheet, so
          # you will need to put anything to be handled in that key. Pf2e.do_advancement is the helper that processes
          # this hash. You'll see this in play in advance/feat and advance/raise.
        else
          client.emit_failure t('pf2e.bad_element', :element => self.type, :options => 'grant, charclass')
        end

        enactor.update(pf2_to_assign: to_assign)
        enactor.update(pf2_advancement: advancement)

        client.emit_success t('pf2e.adv_option_selected', :option => self.value, :feature => feature)

      end
    end
  end
end
