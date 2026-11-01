module AresMUSH
  module Pf2e

    # The commands that do what a player names (`+e/how <name>`): an action they can use, a Strike they
    # can make, a spell they can cast, an item they carry, or something the game does for anyone, like
    # spending a Hero Point. Each answer is `[ command, what it does ]`, the command as they would type it
    # with what they fill in shown in angle brackets.
    #
    # Pure: `known` is what the character has, as the command gathers it -
    #
    #   'strikes' => [ { 'names' => [ 'Longsword', 'Old Faithful' ] } ]
    #   'actions' => [ { 'name' =>, 'cost' =>, 'target' => true, 'strike' => true } ]
    #   'spells'  => [ { 'name' =>, 'from' => a class, 'focus' or 'innate' } ]
    #   'items'   => [ { 'category' =>, 'number' =>, 'name' =>, 'equipped' =>, 'uses' =>, 'thrown' =>, 'ammunition' => } ]
    module HowTo

      # What the game does for anyone, by the words a player might call it.
      TOPICS = [
        { 'words' => [ 'hero point', 'hero', 'reroll', 'boost', 'survive', 'fortune' ],
          'ways' => [ [ 'hero', 'how many Hero Points you have in the scene' ],
                      [ 'hero/reroll', 'spend one to reroll your last check; the new roll stands' ],
                      [ 'hero/boost', 'spend one to add 10 to your last check, if the die rolled under 10' ],
                      [ 'hero/survive', 'spend them all to keep from dying' ] ] },
        { 'words' => [ 'turn', 'actions left', 'reaction', 'multiple attack penalty', 'map' ],
          'ways' => [ [ '+e/turn', 'the actions you have used this turn, your reaction, and your multiple attack penalty' ] ] },
        { 'words' => [ 'why', 'modifier', 'bonus', 'penalty' ],
          'ways' => [ [ '+e/why', 'every modifier on your last roll, and on the defense it was rolled against' ] ] },
        { 'words' => [ 'reload' ],
          'ways' => [ [ '+e/reload [<weapon>]', 'reload a weapon that needs it, such as a crossbow' ] ] },
        { 'words' => [ 'cover' ],
          'ways' => [ [ '+e/cover <target>=<none|lesser|standard|greater>', 'set cover: the GM, or a player they trust' ] ] },
        { 'words' => [ 'conceal', 'concealed', 'hidden', 'undetected' ],
          'ways' => [ [ '+e/conceal <target>=<none|concealed|hidden|undetected>', 'set concealment: the GM, or a player they trust' ] ] },
        { 'words' => [ 'aura' ],
          'ways' => [ [ '+e/enter <aura>=<target>,<target>', 'mark who is inside one of your auras' ],
                      [ '+e/leave <aura>=<target>', 'mark that someone has left it' ] ] },
        { 'words' => [ 'gear', 'item', 'inventory', 'carry' ],
          'ways' => [ [ '+e/gear', 'what you carry in this encounter, with the numbers the commands use' ] ] },
        { 'words' => [ 'sheet', 'stats' ],
          'ways' => [ [ '+e/sheet', 'your sheet as it stands in this encounter' ],
                      [ '+e/csheet', 'your Strikes, AC and saves as they stand in this encounter' ] ] },
        { 'words' => [ 'cast', 'spell' ],
          'ways' => [ [ '+e/cast <spell>=<target>[,<target>][/rank <n>]', 'cast a spell; +e/how <spell> gives one of yours' ] ] }
      ].freeze

      # The words that ask for every Strike.
      STRIKE = %w{strike attack}.freeze

      def self.answers(term, known)
        wanted = word(term)

        return nothing(term) if wanted.empty?

        found = topics(wanted) + strikes(wanted, known) + actions(wanted, known) + spells(wanted, known) + items(wanted, known)
        found = found.uniq(&:first)

        found.empty? ? nothing(term) : Ok.new(:state => found)
      end

      def self.nothing(term)
        Err.new(:how_nothing, 'pf2e.how_nothing', 'name' => term.to_s.strip)
      end

      # A name as it is compared: lowercase, its words joined, and one that ends in an s taken as the word
      # without it.
      def self.word(text)
        Domains.slug(text).sub(/(?<=[a-z])s\z/, '')
      end

      def self.called?(name, wanted)
        named = word(name)

        named == wanted || named.split('-').each_cons(wanted.count('-') + 1).any? { |run| run.join('-') == wanted } ||
          (wanted.length > 3 && named.include?(wanted))
      end

      def self.topics(wanted)
        TOPICS.select { |topic| topic['words'].any? { |one| word(one) == wanted } }.flat_map { |topic| topic['ways'] }
      end

      def self.strikes(wanted, known)
        listed = Array(known['strikes'])
        chosen = STRIKE.include?(wanted) ? listed : listed.select { |one| one['names'].any? { |name| called?(name, wanted) } }

        chosen.map { |one| [ "+e/strike <target>=#{one['names'].first}", "Strike with your #{one['names'].first}" ] }
      end

      def self.actions(wanted, known)
        Array(known['actions']).select { |one| called?(one['name'], wanted) }.map do |one|
          target = one['target'] ? '=<target>' : ''
          weapon = one['strike'] ? '/<weapon>' : ''

          [ "+e/act #{one['name'].downcase}#{target}#{weapon}", "#{one['name']}: #{one['cost']}" ]
        end
      end

      def self.spells(wanted, known)
        matched = Array(known['spells']).select { |one| called?(one['name'], wanted) }

        matched.group_by { |one| one['name'] }.flat_map do |name, ways|
          ways.map do |one|
            how = case one['from']
                  when 'focus', 'innate' then "/#{one['from']}"
                  else ways.size > 1 ? "/class #{one['from']}" : ''
                  end

            [ "+e/cast #{name.downcase}=<target>#{how}", "cast #{name}#{one['from'] ? " (#{one['from']})" : ''}" ]
          end
        end
      end

      def self.items(wanted, known)
        Array(known['items']).flat_map do |one|
          uses = Array(one['uses'])
          named = called?(one['name'], wanted)
          chosen = named ? uses : uses.select { |use| called?(use, wanted) }

          next [] unless named || chosen.any?

          item_ways(one, chosen)
        end
      end

      # ------------------------------------------------------------------------------
      # What a character has, read from the database: their copy in the encounter, where `holder` is
      # their state in one, or their own sheet.

      CATEGORIES = %w{consumables weapons armor shields magicitem}.freeze

      def self.known(char, holder)
        { 'strikes' => Acting.attacks_of(holder).map { |names, _attack| { 'names' => names } },
          'actions' => Actions.available(char).map { |name| action(name) },
          'spells' => spells_of(char.magic),
          'items' => CATEGORIES.flat_map { |category| items_of(holder, category) } }
      end

      def self.action(name)
        entry = Actions.info(name)
        aimed = (entry['check'] || {})['against'] || entry['strike']

        { 'name' => name, 'cost' => Actions.cost(name), 'target' => !!aimed, 'strike' => !!entry['strike'] }
      end

      def self.spells_of(magic)
        return [] unless magic

        named = lambda { |ranks| Array((ranks || {}).values).flatten.compact.map(&:to_s).reject { |one| one.casecmp?(Pf2emagic::Entries::OPEN) } }
        prepared = (magic.spells_prepared || {}).flat_map { |from, ranks| named.call(ranks).map { |name| { 'name' => name, 'from' => from } } }
        repertoire = Pf2emagic::Entries.known_by_source(magic, 'spontaneous').flat_map do |from, ranks|
          named.call(ranks).map { |name| { 'name' => name, 'from' => from } }
        end
        focus = Pf2emagic::Entries.all_focus(magic).map { |name| { 'name' => name, 'from' => 'focus' } }
        innate = Pf2emagic::Entries.innate_grants(magic).map { |grant| { 'name' => grant['name'], 'from' => 'innate' } }

        (prepared + repertoire + focus + innate).uniq
      end

      def self.items_of(holder, category)
        Pf2egear::Inventory.held(holder, category).each_with_index.map do |item, number|
          uses = category == 'consumables' || !item.respond_to?(:use) ? [] : (item.use || {}).keys

          { 'category' => category, 'number' => number, 'name' => item.name, 'uses' => uses,
            'equipped' => item.respond_to?(:equipped) ? !!item.equipped : nil,
            'thrown' => category == 'consumables' && Consumables.bomb?(item.name),
            'ammunition' => category == 'consumables' ? Ammunition.material(item.name)&.tr('-', ' ') : nil }
        end
      end

      def self.item_ways(one, uses)
        number = "#{one['category']}=#{one['number']}"

        if one['thrown']
          [ [ "+e/strike <target>=#{one['name']}", "throw your #{one['name']}" ] ]
        elsif one['ammunition']
          [ [ "+e/strike <target>=<weapon>/#{one['ammunition']}", "shoot your #{one['name']} from a weapon that fires it" ] ]
        elsif one['category'] == 'consumables'
          [ [ "+e/use #{number}", "use your #{one['name']}" ], [ "+e/use #{number}/<who>", "give it to someone in the fight" ] ]
        elsif uses.any?
          uses.map { |use| [ "+e/use #{number}/#{use}", "use your #{one['name']}: #{use}" ] }
        elsif %w{weapons armor shields}.include?(one['category'])
          one['equipped'] ? [ [ "+e/strike <target>=#{one['name']}", "Strike with your #{one['name']}" ] ].select { one['category'] == 'weapons' }
                          : [ [ "+e/equip #{number}", "draw or put on your #{one['name']}" ] ]
        else
          [ [ "+e/use #{number}", "use your #{one['name']}" ] ]
        end
      end
    end
  end
end
