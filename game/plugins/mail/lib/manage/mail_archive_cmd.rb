module AresMUSH
  module Mail
    class MailArchiveCmd
      include CommandHandler

      attr_accessor :num

      def parse_args
        self.num = trim_arg(cmd.args)
      end
      
      def required_args
        {
          args: [ self.num ],
          help: 'mail managing'
        }
      end
      
      def handle
        Mail.with_a_delivery(client, enactor, self.num) do |delivery|
          tags = delivery.tags
          tags << Mail.archive_tag
          tags.delete(Mail.inbox_tag)
          tags.uniq!
          delivery.update(tags: tags)
          client.emit_success t('mail.message_archived')
        end
      end
    end
  end
end
