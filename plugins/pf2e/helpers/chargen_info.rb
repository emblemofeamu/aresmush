module AresMUSH
  module Pf2e

    # What `cg/info <element>` can answer, as one row per element.
    #
    # Each row says what the element is called (with its aliases), what must already be chosen
    # before it can be answered, and where its options come from. The error message's list of valid
    # elements is derived from the table, so the vocabulary lives in one place.
    #
    # Three outcomes. The difference between the last two matters to a player:
    #
    #   Ok                  - here are the options
    #   Err :cannot_find_cginfo - you have to choose something else first
    #   Err :no_cginfo_available - there is nothing to choose here; your class has no specialties
    module ChargenInfo

      # Where a prerequisite is read from. `base` is `pf2_base_info`, `faith` is `pf2_faith`.
      def self.field(char, holder, name)
        source = holder == 'faith' ? char.pf2_faith : char.pf2_base_info

        (source || {})[name]
      end

      ELEMENTS = [
        {
          'name' => 'ancestry',
          'options' => lambda { |_char| Global.read_config('pf2e_ancestry').keys }
        },
        {
          'name' => 'heritage',
          # A heritage belongs to an ancestry, so there is nothing to list until one is picked.
          'requires' => { 'field' => 'ancestry', 'label' => 'ancestry' },
          'options' => lambda { |char| Global.read_config('pf2e_ancestry', ChargenInfo.field(char, 'base', 'ancestry'), 'heritages') }
        },
        {
          'name' => 'background',
          'aliases' => [ 'backgrounds' ],
          'options' => lambda { |_char| Global.read_config('pf2e_background').keys }
        },
        {
          'name' => 'charclass',
          'aliases' => [ 'class' ],
          'options' => lambda { |_char| Global.read_config('pf2e_class').keys }
        },
        {
          'name' => 'specialize',
          'requires' => { 'field' => 'charclass', 'label' => 'character class' },
          # Not every class has specialties. "There is nothing to choose here" and "choose something
          # else first" are different answers, so they are different outcomes.
          'optional' => lambda { |char| Global.read_config('pf2e_specialty', ChargenInfo.field(char, 'base', 'charclass')) },
          'options' => lambda { |char| Global.read_config('pf2e_specialty', ChargenInfo.field(char, 'base', 'charclass')).keys }
        },
        {
          'name' => 'specialize_info',
          'requires' => { 'field' => 'specialize', 'label' => 'specialization' },
          'optional' => lambda { |char|
            info = Global.read_config('pf2e_specialty', ChargenInfo.field(char, 'base', 'charclass'), ChargenInfo.field(char, 'base', 'specialize'))
            info && info['choose']
          },
          'options' => lambda { |char|
            info = Global.read_config('pf2e_specialty', ChargenInfo.field(char, 'base', 'charclass'), ChargenInfo.field(char, 'base', 'specialize'))
            info['choose']['options'].keys
          }
        },
        {
          'name' => 'deity',
          'options' => lambda { |_char| Global.read_config('pf2e_deities').keys }
        },
        {
          'name' => 'alignment',
          'aliases' => [ 'align' ],
          'options' => lambda { |char| ChargenInfo.allowed_alignments(char) }
        }
      ].freeze

      def self.elements
        ELEMENTS.map { |e| e['name'] }
      end

      def self.find(element)
        word = element.to_s.downcase

        ELEMENTS.find { |e| e['name'] == word || Array(e['aliases']).include?(word) }
      end

      # Ok carries { 'title', 'options' }. The title is the word the player typed, so the answer
      # names what they asked for and not the row's canonical name.
      def self.options(char, element)
        row = find(element)
        return Err.new(:bad_element, 'pf2e.bad_option', 'element' => 'cg/info', 'options' => elements.join(", ")) unless row

        requires = row['requires']

        if requires && field(char, 'base', requires['field']).blank?
          return Err.new(:cannot_find_cginfo, 'pf2e.cannot_find_cginfo',
                         'element' => element, 'prereq' => requires['label'])
        end

        optional = row['optional']

        if optional && !optional.call(char)
          return Err.new(:no_cginfo_available, 'pf2e.no_cginfo_available',
                         'element' => element, 'prereq' => requires ? requires['label'] : nil)
        end

        Ok.new(:state => { 'title' => element.to_s, 'options' => Array(row['options'].call(char)).compact })
      end

      # What is left after the game, the class, the specialty and the deity have each had their
      # say. A source that names no restriction restricts nothing.
      def self.allowed_alignments(char)
        all = Array(Global.read_config('pf2e', 'allowed_alignments'))

        charclass = field(char, 'base', 'charclass')
        specialize = field(char, 'base', 'specialize')
        deity = field(char, 'faith', 'deity')

        narrowings = [
          charclass.blank? ? nil : Global.read_config('pf2e_class', charclass, 'allowed_alignments'),
          (charclass.blank? || specialize.blank?) ? nil : (Global.read_config('pf2e_specialty', charclass, specialize) || {})['allowed_alignments'],
          deity.blank? ? nil : Global.read_config('pf2e_deities', deity, 'allowed_alignments')
        ]

        narrowings.compact.reduce(all) { |left, right| left & Array(right) }
      end
    end
  end
end
