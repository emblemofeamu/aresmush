module AresMUSH
  module Pf2e

    # A character described compactly enough to build a hundred of them, for asking whether a feat
    # may be taken.
    #
    # `Pf2e.can_take_feat_details?` reads a dozen places on a character: base info, feats, skills,
    # abilities, specials, faith, archetype slots, the magic object and the combat object. Standing
    # in for all of them keeps the eligibility matrix in the unit suite, where a cell costs
    # microseconds, so the matrix can afford to be exhaustive.
    #
    # Include it in an example group. The methods build doubles, so they only work inside an
    # example.
    module FeatMatrix

      AXES = {
        :level => 1,
        :charclass => 'Fighter',
        :ancestry => 'Human',
        :heritage => 'Versatile Human',
        :specialize => nil,
        :feats => {},
        :skills => {},
        :abilities => {},
        :specials => [],
        :deity => nil,
        :alignment => nil,
        :traditions => {},
        :innate => [],
        :focus_spells => [],
        :focus_pool => 0,
        :divine_font => nil,
        :perception => 'untrained',
        :archetypes => {},
        :advancing => nil
      }.freeze

      ABILITY_NAMES = %w(Strength Dexterity Constitution Intelligence Wisdom Charisma).freeze

      def matrix_char(overrides = {})
        opts = AXES.merge(overrides)

        double(matrix_label(opts),
          :name => matrix_label(opts),
          :pf2_level => opts[:level],
          :advancing => opts[:advancing],
          :is_admin? => false,
          :pf2_base_info => {
            'charclass' => opts[:charclass],
            'ancestry' => opts[:ancestry],
            'heritage' => opts[:heritage],
            'specialize' => opts[:specialize]
          },
          :pf2_faith => { 'deity' => opts[:deity], 'alignment' => opts[:alignment] },
          :pf2_feats => opts[:feats],
          :pf2_special => opts[:specials],
          :pf2_archetypeinfo => opts[:archetypes],
          :pf2_to_assign => {},
          :pf2_advancement => {},
          # Read by adopted_ancestries, which every Ancestry feat goes through.
          :pf2_level_tracker => {},
          :skills => opts[:skills].map { |name, prof| matrix_skill(name, prof) },
          :abilities => matrix_abilities(opts[:abilities]),
          :magic => matrix_magic(opts),
          :combat => matrix_combat(opts))
      end

      def matrix_skill(name, prof)
        double(:name => name, :prof_level => prof, :name_upcase => name.upcase)
      end

      def matrix_abilities(scores)
        base = ABILITY_NAMES.each_with_object({}) { |name, out| out[name] = 10 }

        base.merge(scores).map do |name, score|
          double(:name => name, :name_upcase => name.upcase, :shortname => name[0, 3].upcase,
                 :base_val => score, :mod_val => nil)
        end
      end

      # nil when the character has no magic at all, which is what a non-caster looks like.
      def matrix_magic(opts)
        blank = opts[:traditions].empty? && opts[:innate].empty? && opts[:focus_spells].empty? &&
                opts[:focus_pool].to_i.zero? && opts[:divine_font].nil?

        return nil if blank

        double(:tradition => opts[:traditions],
               :innate_spells => opts[:innate],
               :focus_pool => { 'max' => opts[:focus_pool], 'current' => opts[:focus_pool] },
               :divine_font => opts[:divine_font],
               :spell_abil => {}, :spells_per_day => {}, :repertoire => {}, :spellbook => {},
               :signature_spells => {}, :restricted_spellbook => {}, :restricted_slots => {},
               :character => nil)
      end

      def matrix_combat(opts)
        double(:perception => opts[:perception], :class_dc => 'trained', :saves => {},
               :weapon_prof => {}, :armor_prof => {}, :weapon_group_prof => {},
               :sneak_attack => nil)
      end

      # A short name for a failure message: the axes this character has moved off their default.
      def matrix_label(opts)
        moved = opts.reject { |axis, value| AXES[axis] == value || axis == :charclass }
                    .map { |axis, value| "#{axis}=#{value.inspect}" }

        [ "#{opts[:charclass]} L#{opts[:level]}", *moved ].join(' ')
      end

      # May this character take this feat? Reads the feat from whatever config the example has
      # stubbed, so a fixture and the shipped data are asked the same way.
      def matrix_allows?(char, feat_name, ignore_charclass: false)
        feats = Global.read_config('pf2e_feats') || {}
        key = feats.keys.find { |k| k.to_s.casecmp?(feat_name.to_s) }

        raise "no feat named #{feat_name.inspect} in the config under test" unless key

        Pf2e.can_take_feat_details?(char, key, feats[key], nil, ignore_charclass)
      end

      # `pf2_feats` wants bucket => [ names ]. Which bucket rarely matters to eligibility, because
      # every check flattens the hash.
      def matrix_holding(*names)
        { 'charclass' => names.flatten.compact }
      end

      # The focus spell lists Entries.all_focus reads, for the focus_spell prereq.
      def matrix_focus(names)
        allow(Pf2emagic::Entries).to receive(:all_focus).and_return(Array(names))
      end
    end
  end
end
