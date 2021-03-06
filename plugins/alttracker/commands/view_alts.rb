module AresMUSH
  module AltTracker

    class ViewAltsCmd
      include CommandHandler

      attr_accessor :altlist, :banned, :codeword, :email, :target

      def parse_args
        if cmd.args
          self.target = cmd.args
        else
          self.target = enactor
        end
      end

      def check_can_view
        return nil if self.target == enactor
        return nil if enactor.has_permission?("manage_alts")
        return t('alttracker.view_own_alts')
      end

      def handle
        valid_email = /\A([\w+\-].?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i

        if self.target =~ valid_email
          player = AltTracker.find_player_by_email(self.target)
        elsif self.target == enactor
          player = enactor.player
        else
          player = Character.find_one_by_name(self.target)&.player
        end

        if !player
          if self.target == enactor
            display_name = enactor.name
          else
            display_name = cmd.args
          end

          client.emit_failure t('alttracker.not_registered', :name => display_name)
          return nil
        else
          email = player.name
          codeword = player.codeword
          altlist = AltTracker.get_altlist_by_object(player)
          banned = player.banned

          template = AltsDisplayTemplate.new email, codeword, altlist, banned

          client.emit template.render
        end
      end
    end

  end
end
