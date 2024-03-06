module AresMUSH
  module Pf2e

    class PF2ChargenInfoCmd
      include CommandHandler
      include CommonTemplateFields

      attr_accessor :element

      def parse_args
        self.element = downcase_arg(cmd.args)
      end

      def handle

        base_info = enactor.pf2_base_info
        faith_info = enactor.pf2_faith
        ancestry = base_info['ancestry']
        charclass = base_info['charclass']
        subclass = base_info['specialize']
        deity = faith_info['deity']

        case self.element
        when 'ancestry'
          options = Global.read_config('pf2e_ancestry').keys
        when 'heritage'
          if ancestry.blank?
            client.emit_failure t('pf2e.cannot_find_info', :element=>self.element, :prereq=>'ancestry')
            return
          end

          options = Global.read_config('pf2e_ancestry', ancestry, 'heritages')
        when 'background', 'backgrounds'
          options = Global.read_config('pf2e_background').keys
        when 'class', 'charclass'
          options = Global.read_config('pf2e_class').keys
        when 'specialize'
          if charclass.blank?
            client.emit_failure t('pf2e.cannot_find_info', :element=>self.element, :prereq=>'character class')
            return
          end

          specialty_info = Global.read_config('pf2e_specialty', charclass)

          if !specialty_info
            client.emit_ooc t('pf2e.no_cginfo_available', :element=>self.element, :prereq=>'character class')
            return
          end

          options = specialty_info.keys
        when 'specialize_info'
          if subclass.blank?
            client.emit_failure t('pf2e.cannot_find_cginfo', :element=>self.element, :prereq=>'specialization')
            return
          end

          subclass_info = Global.read_config('pf2e_specialty', charclass, subclass)['choose']

          if !subclass_info
            client.emit_ooc t('pf2e.no_cginfo_available', :element=>self.element, :prereq=>'specialization')
            return
          end

          options = subclass_info['options'].keys
        when 'deity'
          options = Global.read_config('pf2e_deities').keys
        when 'align', 'alignment'
          all_align = Global.read_config('pf2e','allowed_alignments')
          subclass_align = subclass.blank? ? all_align : Global.read_config('pf2e_specialty', charclass, subclass)['allowed_alignments']
          class_align = charclass.blank? ? all_align : Global.read_config('pf2e_class', charclass, 'allowed_alignments')
          deity_align = deity.blank? ? all_align : Global.read_config('pf2e_deities', deity, 'allowed_alignments')

          class_align = all_align if !class_align
          subclass_align = all_align if !subclass_align

          options = all_align & subclass_align & class_align & deity_align
        else
          options = %w{ancestry heritage charclass background specialize specialize_info deity alignment}

          client.emit_failure t('pf2e.bad_option', :element=>"cg/info", :options=>options.join(", "))
          return
        end

        # Some of these have approximately 3.84 metric fucktons of output, so pagination ended up being required.

        # Format the list to be paginated.

        fmt_options = []

        options.sort.each_with_index do |option, i|
          fmt_options << Pf2e.format_cginfo_options(option, i)
        end

        paginator = Paginator.paginate(fmt_options, cmd.page, 30)

        if (paginator.out_of_bounds?)
          client.emit_failure paginator.out_of_bounds_msg
          return
        end

        title = "Chargen Options for #{self.element.capitalize}"

        template = PF2CGInfoTemplate.new(paginator, title)

        client.emit template.render

        # client.emit t('pf2e.cg_info',
        #   :element=>"%x24#{self.element}%xn",
        #   :options=>"#{item_color}#{options.join(", ")}"
        # )
      end

    end
  end
end
