module AresMUSH
    module LookingForRp
      class LookingForRpAnnounceCommand
        include CommandHandler

        attr_accessor :toggle

        def parse_args
          self.toggle = (cmd.args)
        end
        
        def required_args
          [ self.toggle ]
        end
        
        def handle
          if self.toggle == "off"
            LookingForRp.announce_toggle_off(enactor)
            client.emit_success t('lookingforrp.announce_off')

          elsif self.toggle == "on"
            LookingForRp.announce_toggle_on(enactor)
            client.emit_success t('lookingforrp.announce_on')
          end
        end
      end
  
    end
  end