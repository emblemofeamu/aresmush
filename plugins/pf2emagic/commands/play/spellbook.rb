module AresMUSH
    module Pf2emagic
        class PF2MagicSpellbookCmd
            include CommandHandler
  
            attr_accessor :character, :charclass, :spell_level, :noargs
    
            def parse_args 
                # Faraday's Argparser isn't touching this one
                # Usage: spellbook [character=][class/level]
                charclasses = Global.read_config('pf2e_class').keys
                args = !cmd.args.nil? ? cmd.args.split("/").map {|e| e.split("=")}.flatten : []
                args.append(nil)
                
                #Initialize some default values for the command
                self.character = nil
                self.charclass = nil
                self.spell_level = "all"

                if args[0].nil?
                    self.noargs = true
                    return
                else
                    self.noargs = false
                end

                # Cycle through the args and populate the arguments
                args.each do |v|
                    if ("0".."10").include? v
                        self.spell_level = v
                    end
                    if v == "0"
                        self.spell_level = "cantrip"
                    end
                    # if charclasses v.downcase
                    #     self.charclass = v.capitalize
                    # end
                    charclasses.each do |c|
                        if !v.nil? and c.downcase ==  v.downcase
                            self.charclass = c.capitalize
                        end
                    end
                end

                # Delete previously set values from args
                args.delete(self.charclass)
                args.delete(self.spell_level)

                # and whatever is left over should be a character name, if one is set, or remain nil
                # added additional validation to check if someone put a number outside normal spell levels,
                # which would stay in there and mess up the name being the last one there
                args[0].to_i == 0 ? self.character = args[0] : nil
            end

            def check_permissions
                # Any character may modify their own; only people who can see alts can modify others'.
                if !self.character.nil? # Player provided their own name?
                    return nil if self.character.downcase == enactor.name.downcase
                else
                    return nil # self.character is nil, meaning it's performed on self
                end
                # Check for allowed roles 
                ["admin", "coder"].each do |r|
                    return nil if enactor.has_role?(r)
                end
                return t('dispatcher.not_allowed') 
            end

            def handle
                # If character came out of the argparsing, get that character, else get the enactor's character
                char = Pf2e.get_character(self.character, enactor)

                Global.logger.debug self.character
                Global.logger.debug self.spell_level
                Global.logger.debug self.charclass

                # Check if character is a caster
                if !(Pf2emagic.is_caster?(char))
                    client.emit_failure t('pf2emagic.not_caster')
                    return
                end

                csb = char.magic.spellbook

                # Cut the music if no args were given, or a name was given with no class
                if noargs || (!self.character.nil? && self.charclass.nil?)
                    client.emit_failure t('pf2emagic.spellbook_no_args', :options=>csb.keys.join(","))
                    return
                end

                if !self.charclass.nil? && (!csb.keys.include? self.charclass)
                    client.emit_failure t('pf2emagic.spellbook_invalid_class', :invalid_class=>self.charclass)
                    return
                end
                
                # if !("0".."10").include? self.spell_level or !self.spell_level == "all"
                #     client.emit_failure t('pf2emagic.spellbook_invalid_level')
                #     return
                # end
                























































































































































































































                
                if self.spell_level == "cantrip" and !csb[self.charclass].keys.include? "cantrip"
                    options = csb[self.charclass].keys.map { |v| v == "cantrip" ? "0" : v }.join(", ")
                    client.emit_failure t('pf2emagic.spellbook_no_spells_at_level', :options=>options)
                    return
                elsif !csb[self.charclass].keys.include? self.spell_level
                    options = csb[self.charclass].keys.map { |v| v == "cantrip" ? "0" : v }.join(", ")
                    client.emit_failure t('pf2emagic.spellbook_no_spells_at_level', :options=>options)
                    return
                elsif self.spell_level == "0" and !csb[self.charclass].keys.include? "cantrip"
                    options = csb[self.charclass].keys.map { |v| v == "cantrip" ? "0" : v }.join(", ")
                    client.emit_failure t('pf2emagic.spellbook_no_spells_at_level', :options=>options)
                    return
                end

                if self.spell_level == "all"
                    # Send everything
                    template = PF2SpellbookTemplate.new(char, csb, client)
                elsif self.spell_level == "0"
                    book_by_level = { self.charclass=>{ self.spell_level=>csb[self.charclass.to_s]["cantrip"]} }
                    template = PF2SpellbookTemplate.new(char, book_by_level, client)
                else
                    # Send only one level of the spellbook
                    book_by_level = { self.charclass=>{ self.spell_level=>csb[self.charclass.to_s][self.spell_level.to_s]} }
                    template = PF2SpellbookTemplate.new(char, book_by_level, client)
                end
                client.emit template.render
            end
        end
    end
end