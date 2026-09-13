module AresMUSH
  module Pf2e

    INFO_FEAT_SLOT_TYPES = %w(general skill ancestry charclass archetype dedication)

    # Lists at or below this go out as a single line; longer ones get the paginated template.
    INFO_PAGINATE_LIMIT = 20

    # Entries per page once paging kicks in. Two columns, so this is 20 rows.
    INFO_PAGE_SIZE = 40

    def self.info_options(char, element)
      return nil if element.blank?

      # A pending feat choice, by name. This is the Assurance case: the player is told to run 'cg/info Assurance' when they take it, and gets the skills still open to them.
      pending = pending_feat_choices(char)
      key = pending.keys.find { |k| k.to_s.casecmp?(element.to_s) }

      if key
        block = find_choice_block(char, key)
        return nil unless block

        return [ key, choice_options(char, key, block) ]
      end

      # A feat slot type. 'general' and 'general feat' both work.
      type = element.to_s.downcase.strip.sub(/\s+feats?\z/, '')

      if INFO_FEAT_SLOT_TYPES.include?(type)
        return [ t('pf2e.info_feat_title', :type => type.capitalize), get_feat_options(char, type) ]
      end

      nil
    end

    def self.info_option_display(title, options, page)
      options = Array(options).compact

      return { :error => t('pf2e.info_no_options', :element => title) } if options.empty?

      if options.size <= INFO_PAGINATE_LIMIT
        return { :text => t('pf2e.cg_info', :element => title, :options => options.join(", ")) }
      end

      paginator = Paginator.paginate(options, page, INFO_PAGE_SIZE)

      return { :error => paginator.out_of_bounds_msg } if paginator.out_of_bounds?

      { :text => PF2OptionListTemplate.new(paginator, title).render }
    end

  end
end
