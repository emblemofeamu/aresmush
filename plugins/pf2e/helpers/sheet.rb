module AresMUSH
  module Pf2e

    # The sections of a character sheet, and whether a given character has one.
    #
    # Three commands read sheets - `sheet`, `sheet/show` and `sheet/combat` - and each carried its
    # own copy of the section list and its own gating. They disagreed: `sheet` left `combat` out of
    # its list while `sheet/show` accepted it, so a player could grant someone a section `sheet`
    # would then refuse to render; and only `sheet` checked that a character casts before offering
    # them a magic section.
    #
    # One row per section, each saying what the character must have for it to exist. Whether the
    # *viewer* may see it is a separate question and stays with the commands, because it depends on
    # the enactor's permissions rather than on the sheet.
    module Sheet

      # A section every character has needs no requirement. `requires` is a predicate on the
      # character; `code` and `key` are what a refusal says.
      SECTIONS = [
        { 'name' => 'all' },
        { 'name' => 'info' },
        { 'name' => 'ability' },
        { 'name' => 'skills' },
        { 'name' => 'feats' },
        { 'name' => 'features' },
        { 'name' => 'languages' },
        { 'name' => 'combat' },
        {
          'name' => 'magic',
          'requires' => lambda { |char| !!char.magic },
          'code' => :not_caster,
          'key' => 'pf2emagic.not_caster'
        }
      ].freeze

      # Reasons a character has no sheet at all, tried before any section is considered - an
      # admin's sheet does not exist, and neither does one whose base info was never locked.
      MISSING = [
        { 'when' => lambda { |char| char.is_admin? }, 'code' => :admin_no_sheet, 'key' => 'pf2e.admin_no_sheet' },
        { 'when' => lambda { |char| !char.pf2_baseinfo_locked }, 'code' => :no_sheet_yet, 'key' => 'pf2e.no_sheet_yet' }
      ].freeze

      # Whether a viewer may see a section of someone's sheet. Rows are reasons to allow it, in
      # order; nothing allowing it is a refusal.
      #
      # This is where `sheet/show`'s grants finally do something. They were written to
      # `pf2_viewsheet` and never read: both display commands asked only whether the game had
      # sheets open and whether the viewer held the staff `view_sheets` permission, so a grant a
      # player made had no effect at all.
      ALLOWED = [
        # The game can be configured so that every sheet is public.
        lambda { |_viewer, _char, _section| !!Global.read_config('pf2e', 'open_sheets') },
        # Staff who are allowed to read sheets.
        lambda { |viewer, _char, _section| !!viewer.has_permission?("view_sheets") },
        # Your own sheet.
        lambda { |viewer, char, _section| viewer.name == char.name },
        # A grant of this section, or of the whole sheet.
        lambda { |viewer, char, section| Sheet.granted?(viewer, char, section) }
      ].freeze

      def self.granted?(viewer, char, section)
        grants = char.pf2_viewsheet || {}

        [ section.to_s.downcase, 'all' ].any? do |key|
          Array(grants[key]).any? { |name| name.to_s.casecmp?(viewer.name.to_s) }
        end
      end

      def self.viewable?(viewer, char, section)
        return Ok.new(:state => section) if ALLOWED.any? { |rule| rule.call(viewer, char, section) }

        Err.new(:cannot_view_sheet, 'pf2e.cannot_view_sheet')
      end

      def self.sections
        SECTIONS.map { |s| s['name'] }
      end

      def self.section?(name)
        sections.include?(name.to_s.downcase)
      end

      # Whether this character has this section. Ok, or an Err naming what is missing.
      def self.available(char, name)
        missing = MISSING.find { |rule| rule['when'].call(char) }
        return Err.new(missing['code'], missing['key']) if missing

        section = SECTIONS.find { |s| s['name'] == name.to_s.downcase }

        unless section
          return Err.new(:bad_section, 'pf2e.bad_section', 'section' => name)
        end

        requires = section['requires']
        return Ok.new(:state => section['name']) if requires.nil? || requires.call(char)

        Err.new(section['code'], section['key'])
      end
    end
  end
end
