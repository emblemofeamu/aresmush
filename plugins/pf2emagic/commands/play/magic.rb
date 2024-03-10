module AresMUSH
  module Pf2emagic
    class PF2MagicDisplayCmd
      include CommandHandler

      attr_accessor :character

      def parse_args
        self.character = trim_arg(cmd.args)
      end

      def check_can_view
        return nil if !self.character
        return nil if Global.read_config('pf2e','open_sheets')
        return nil if enactor.has_permission?("view_sheets")
        return t('pf2e.cannot_view_sheet')
      end

      def handle
        char = Pf2e.get_character(self.character, enactor)

        unless char
          client.emit_failure t('pf2e.not_found')
          return
        end

        if !(Pf2emagic.is_caster?(char))
          client.emit_failure t('pf2emagic.not_caster')
          return
        end

        magic = char.magic

        template = PF2MagicDisplayTemplate.new(char, magic, client)

        client.emit template.render
      end


    end
  end
end
