module AresMUSH
  module Pf2emagic

    class PF2DivineFontCmd
      include CommandHandler

      attr_accessor :font

      def parse_args
        self.font = downcase_arg(cmd.args)
      end

      def required_args
        [ self.font ]
      end

      def check_in_chargen
        if enactor.is_approved? || enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def check_valid_font
        fonts = %w{ heal harm }
        return nil if fonts.include? self.font
        return t('pf2e.bad_option', :element => 'divine font', :options => fonts.join(", "))
      end

      def check_baseinfo_locked
        # They need to have done commit info before they can use this command.
        return nil if enactor.pf2_baseinfo_locked
        return t('pf2e.lock_info_first')
      end

      def handle
        to_assign = enactor.pf2_to_assign

        # Do they need to choose a font option? Not all deities grant this.
        dfont_option = to_assign['divine font']

        unless dfont_option
          client.emit_failure t('pf2emagic.no_font_option')
          return
        end

        magic = enactor.magic

        # Do it.

        to_assign['divine font'] = self.font
        enactor.update(pf2_to_assign: to_assign)

        magic.update divine_font: self.font

        client.emit_success t('pf2emagic.dfont_updated', :font => self.font)
      end
    end
  end
end
