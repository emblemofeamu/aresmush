module AresMUSH
  module FS3Combat
    class WeaponDetailCmd
      include CommandHandler
      include TemplateFormatters
      
      attr_accessor :name
      
      def parse_args
        self.name = titlecase_arg(cmd.args)
      end

      def required_args
        {
          args: [ self.name ],
          help: 'weapons'
        }
      end
      
      def check_weapon_exists
        return t('fs3combat.invalid_weapon') if !FS3Combat.weapon(self.name)
        return nil
      end
      
      def handle
        template = GearDetailTemplate.new(FS3Combat.weapon(self.name), self.name, :weapon)
        client.emit template.render
      end
    end
  end
end