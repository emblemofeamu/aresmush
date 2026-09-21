module AresMUSH
  module Pf2e
    module Chargen

      # Choosing a divine font, where the deity grants both.
      #
      # The pool marker is resolved to the chosen word, and the word itself goes on the magic object,
      # which is not state a core may write - so the core says which font was chosen and the shell
      # writes it. `dfont` and `admin/set <char>/divine font` are the two ways in, and they agree
      # about the two fonts because Pf2emagic::Entries names them.
      module DivineFont

        def self.choose(state, args)
          font = args['font'].to_s.downcase
          offered = state['to_assign']['divine font']

          return Err.new(:no_option, 'pf2emagic.no_font_option') if offered.blank?
          return Err.new(:bad_font, 'pf2e.bad_option', 'element' => 'divine font',
                         'options' => Pf2emagic::Entries::FONTS.join(', ')) unless Pf2emagic::Entries::FONTS.include?(font)

          to_assign = state['to_assign'].merge('divine font' => font)

          Ok.new(:state => state.merge('to_assign' => to_assign, 'divine_font' => font))
            .with_message('pf2emagic.dfont_updated', 'font' => font.titleize)
        end
      end
    end
  end
end
