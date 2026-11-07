module AresMUSH
  module Pf2e

    # The parties the played-encounter specs seat, the fights they play, and the wiring that audits every
    # roll a fight makes. A party is four players of four classes at a level, built through chargen and
    # advancement and outfitted for the level.
    module ScenarioParties
      Seat = ScenarioRunner::Seat

      def self.potion(level)
        { 1 => 'Healing Potion (Minor)', 6 => 'Healing Potion (Lesser)', 11 => 'Healing Potion (Moderate)',
          16 => 'Healing Potion (Greater)', 20 => 'Healing Potion (Major)' }[level]
      end

      # What a character of the level carries on their weapon and armour, by the levels the runes are.
      def self.runes(level)
        {
          1 => {},
          6 => { 'potency' => 1, 'striking' => 1, 'armor_potency' => 1 },
          11 => { 'potency' => 2, 'striking' => 1, 'armor_potency' => 1, 'resilient' => 1, 'property' => [ 'Flaming' ] },
          16 => { 'potency' => 2, 'striking' => 2, 'armor_potency' => 2, 'resilient' => 2, 'property' => [ 'Flaming', 'Frost' ] },
          20 => { 'potency' => 3, 'striking' => 3, 'armor_potency' => 3, 'resilient' => 3,
                  'property' => [ 'Flaming', 'Frost', 'Shock' ] }
        }[level]
      end

      def self.kit(level, weapons:, armor: nil, shields: nil, extra: [], alchemy: [])
        {
          'weapons' => weapons, 'armor' => armor, 'shields' => shields,
          'consumables' => [ [ potion(level), 2 ] ] + extra,
          'runes' => runes(level), 'alchemy' => alchemy
        }
      end

      PARTIES = {
        1 => [
          Seat.new(charclass: 'Fighter', ancestry: 'Khazad', heritage: 'Rock', background: 'Guard',
                   kit: kit(1, weapons: [ 'Longsword' ], armor: 'Chain Mail', shields: 'Steel Shield')),
          Seat.new(charclass: 'Cleric', ancestry: 'Human', heritage: 'Versatile', background: 'Acolyte',
                   kit: kit(1, weapons: [ 'Mace' ], armor: "Explorer's Clothing", shields: 'Wooden Shield')),
          Seat.new(charclass: 'Rogue', ancestry: 'Goblin', heritage: 'Unbreakable', background: 'Criminal',
                   kit: kit(1, weapons: [ 'Rapier', 'Shortbow' ], armor: 'Studded Leather')),
          Seat.new(charclass: 'Wizard', ancestry: 'Sildanyar', heritage: 'Seer', background: 'Scholar',
                   kit: kit(1, weapons: [ 'Staff' ], armor: "Explorer's Clothing"))
        ],
        6 => [
          Seat.new(charclass: 'Barbarian', ancestry: 'Oruch', heritage: 'Battle-ready', background: 'Gladiator',
                   kit: kit(6, weapons: [ 'Greataxe' ], armor: 'Hide')),
          Seat.new(charclass: 'Bard', ancestry: 'Bassin', heritage: 'Gutsy', background: 'Entertainer',
                   kit: kit(6, weapons: [ 'Rapier' ], armor: 'Leather')),
          Seat.new(charclass: 'Ranger', ancestry: 'Egalrin', heritage: 'Skyborn', background: 'Hunter',
                   kit: kit(6, weapons: [ 'Longbow', 'Shortsword' ], armor: 'Leather')),
          Seat.new(charclass: 'Druid', ancestry: 'Kailli', heritage: 'Tunnel Kailli', background: 'Herbalist',
                   kit: kit(6, weapons: [ 'Sickle' ], armor: 'Hide', shields: 'Wooden Shield'))
        ],
        11 => [
          Seat.new(charclass: 'Champion', ancestry: 'Human', heritage: 'Skilled', background: 'Squire',
                   kit: kit(11, weapons: [ 'Longsword' ], armor: 'Full Plate', shields: 'Steel Shield')),
          Seat.new(charclass: 'Sorcerer', ancestry: 'Ciith', heritage: 'Xalli', background: 'Fortune Teller',
                   kit: kit(11, weapons: [ 'Dagger' ], armor: "Explorer's Clothing")),
          Seat.new(charclass: 'Monk', ancestry: 'Sildanyar', heritage: 'Woodland', background: 'Martial Disciple',
                   kit: kit(11, weapons: [ 'Staff' ])),
          Seat.new(charclass: 'Investigator', ancestry: 'Arvek', heritage: 'Shortshanks', background: 'Detective',
                   kit: kit(11, weapons: [ 'Rapier', 'Hand Crossbow' ], armor: 'Leather'))
        ],
        16 => [
          Seat.new(charclass: 'Swashbuckler', ancestry: 'Egalrin', heritage: 'Stormtossed', background: 'Acrobat',
                   kit: kit(16, weapons: [ 'Rapier', 'Whip' ], armor: 'Leather')),
          Seat.new(charclass: 'Oracle', ancestry: 'Gnome', heritage: 'Sensate', background: 'Haunted',
                   kit: kit(16, weapons: [ 'Spear' ], armor: 'Studded Leather')),
          Seat.new(charclass: 'Alchemist', ancestry: 'Goblin', heritage: 'Irongut', background: 'Artisan',
                   kit: kit(16, weapons: [ 'Dagger' ], armor: 'Leather',
                            extra: [ [ "Alchemist's Fire (Greater)", 2 ], [ 'Elixir of Life (Greater)', 1 ] ],
                            alchemy: [ "Alchemist's Fire (Greater)", 'Elixir of Life (Greater)' ])),
          Seat.new(charclass: 'Witch', ancestry: 'Kailli', heritage: 'Shadow Kailli', background: 'Hermit (Occultism)',
                   kit: kit(16, weapons: [ 'Staff' ], armor: "Explorer's Clothing"))
        ],
        20 => [
          Seat.new(charclass: 'Fighter', ancestry: 'Oruch', heritage: 'Winter', background: 'Laborer',
                   kit: kit(20, weapons: [ 'Greatsword', 'Longbow' ], armor: 'Full Plate')),
          Seat.new(charclass: 'Wizard', ancestry: 'Gnome', heritage: 'Umbral', background: 'Astrologer',
                   kit: kit(20, weapons: [ 'Staff' ], armor: "Explorer's Clothing")),
          Seat.new(charclass: 'Cleric', ancestry: 'Khazad', heritage: 'Death Warden', background: 'Blessed',
                   kit: kit(20, weapons: [ 'Mace' ], armor: "Explorer's Clothing", shields: 'Steel Shield')),
          Seat.new(charclass: 'Rogue', ancestry: 'Bassin', heritage: 'Twilight', background: 'Charlatan',
                   kit: kit(20, weapons: [ 'Shortsword', 'Shortbow' ], armor: 'Studded Leather'))
        ]
      }.freeze

      # Two fights of moderate threat at each level, the second carrying on from the first.
      FIGHTS = {
        1 => [ [ [ 1, 'Bugbear Prowler' ], [ 1, 'Goblin Warrior' ] ], [ [ 1, 'Boggard Warrior' ], [ 1, 'Giant Rat' ] ] ],
        6 => [ [ [ 1, 'Frost Drake' ], [ 1, 'Gargoyle' ] ], [ [ 1, 'Dullahan' ], [ 1, 'Dwarf Stonecaster' ] ] ],
        11 => [ [ [ 1, 'Great Cyclops' ], [ 1, 'Frost Giant' ] ], [ [ 1, 'Lich' ], [ 1, 'Greater Hell Hound' ] ] ],
        16 => [ [ [ 1, 'Ice Linnorm' ], [ 1, 'Crag Linnorm' ] ], [ [ 1, 'Banshee' ], [ 1, 'Caldera Oni' ] ] ],
        20 => [ [ [ 1, 'Grim Reaper' ], [ 1, 'Kraken' ] ], [ [ 1, 'Tor Linnorm' ], [ 1, 'Magma Worm' ] ] ]
      }.freeze

      # An adventure's two fights, with an exploration before each: creatures none of FIGHTS uses.
      # Fights for each kind of GM. An event runner's are Monster Core's creatures, made elite or weak to
      # suit the party; a Plotmaster's bring one of their own making and a creature from another book.
      GM_FIGHTS = {
        :runner => { 1 => [ [ [ 2, 'weak Wolf' ], [ 1, 'elite Giant Rat' ] ], [ [ 1, 'elite Python' ], [ 1, 'Kobold Warrior' ] ] ],
                     6 => [ [ [ 1, 'weak Stone Giant' ], [ 1, 'elite Basilisk' ] ], [ [ 1, 'Frost Drake' ], [ 2, 'elite Dire Wolf' ] ] ] },
        :plotmaster => { 11 => [ [ 'elite Warlord=ac 31 hp 190 level 11 fort 22 ref 18 will 20 perception 21 str 6 dex 3; ' \
                                   'skills athletics 23, intimidation 21; resist physical 5; weak cold iron 10; immune fear; ' \
                                   'strike greataxe +24 2d12+12 slashing (sweep, reach 10); ranged javelin +21 2d6+10 piercing (range 30); ' \
                                   'ability Whirlwind [2]: Each creature within reach takes 4d8 slashing damage (DC 30 basic Reflex save).',
                                   [ 2, 'Guard' ] ],
                                 [ [ 1, 'elite Fire Giant' ], [ 1, 'weak Lich' ] ] ] }
      }.freeze

      # Fights against creatures with the most to do: grabs and what follows them, swallowing, auras of
      # fear, breaths that take rounds to come back, venoms with stages, reactions, and spells. Played by
      # a GM who uses all of it (`CreaturePlay`).
      BY_THE_BOOK = {
        1 => [ [ [ 1, 'Python' ], [ 2, 'Wolf' ] ], [ [ 1, 'Giant Rat' ], [ 1, 'Orc Veteran' ], [ 1, 'Ghoul Stalker' ] ] ],
        6 => [ [ [ 1, 'elite Snapping Flytrap' ], [ 2, 'Giant Wasp' ] ], [ [ 1, 'Dullahan' ], [ 1, 'Forest Troll' ] ] ],
        11 => [ [ [ 1, 'Terra Dragon (Young)' ], [ 1, 'Nuckelavee' ] ], [ [ 1, 'Diabolic Dragon (Young)' ], [ 1, 'Garadasura' ] ] ],
        16 => [ [ [ 1, 'Terra Dragon (Ancient)' ], [ 1, 'Jotund Troll' ] ], [ [ 1, 'Phasmadaemon' ], [ 1, 'Thulgant' ] ] ],
        20 => [ [ [ 1, 'Diabolic Dragon (Ancient)' ], [ 1, 'Urveth' ] ], [ [ 1, 'Tor Linnorm' ], [ 1, 'Nessari' ] ] ]
      }.freeze

      ADVENTURES = {
        1 => [ [ [ 1, 'Python' ], [ 1, 'Fire Scamp' ] ], [ [ 1, 'Draugr' ], [ 1, 'Wolf Skeleton' ] ] ],
        6 => [ [ [ 1, 'Zombie Hulk' ], [ 1, 'Iron Hag' ] ], [ [ 1, 'Skittering Slayer' ] ] ],
        11 => [ [ [ 1, 'Spinosaurus' ], [ 1, 'Garadasura' ] ], [ [ 1, 'Viper Vine' ] ] ],
        16 => [ [ [ 1, 'Clockwork Dragon' ], [ 1, 'Sumbreiva' ] ],
                [ [ 1, 'Graveknight Champion' ], [ 1, 'Dybbuk' ], [ 1, 'Wemmuth' ] ] ],
        20 => [ [ [ 1, 'Tarn Linnorm' ], [ 1, 'Baomal' ] ], [ [ 1, 'Ravener' ], [ 1, 'Tzitzimitl' ] ] ]
      }.freeze
    end
  end
end
