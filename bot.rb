$LOAD_PATH << './lib'
puts "Loading IRC..."
require 'irc'
puts "Loading the IRC Parser..."
require 'parser'
puts "Loading RubyGems..."
require 'rubygems'
puts "Loading Activerecord..."
require 'activerecord'
puts "Loading models and connecting to database..."
require 'models'
puts "Loading UrT library..."
require 'urt'
puts "Loading HPricot, OpenURI and ERB..."
require 'hpricot'
require 'open-uri'
require 'erb'

$b = binding()

nick = 'MrTech'

irc = IRC.new( :server => 'irc.eighthbit.net',
                 :port => 6667,
                 :nick => nick,
                :ident => 'mrtech',
             :realname => 'MrTech - using on_irc Ruby IRC library',
              :options => { :use_ssl => false } )

parser = Parser.new

irc.on_001 do
	irc.join '#gaming,#offtopic'
end

irc.on_all_events do |e|
	p e
end

irc.on_invite do |e|
  irc.join(e.channel)
end

# Uncomment this block if you want it to greet people
#irc.on_join do |e|
#  irc.msg(e.channel, "Hey #{e.sender.nick}, and welcome to #{e.channel}!") if e.sender.nick != nick
#end

irc.on_privmsg do |e|
  
  parser.command(e, 'join', true) do |c, params|
    irc.join(c.message)
  end
  
  parser.command(e, 'calc') do |c, params|
    url = "http://www.google.com/search?q=#{ERB::Util.u(c.message)}"
    doc = Hpricot(open(url))
    calculation = (doc/'/html/body//#res/p/table/tr/td[3]/h2/font/b').inner_html
    if calculation.empty?
      irc.msg(e.recipient, 'Invalid Calculation.')
    else
      irc.msg(e.recipient, calculation)
    end
  end
  
  parser.command(e, 'urt') do |c, params|
    @urt ||= UrT.new('games.eighthbit.net')
    server_info = @urt.get_stats(c.message)
    
    if server_info.is_a? UrTServerInfo
      message = "UrT stats for #{server_info.sv_hostname}: Playing #{server_info.game_type} on #{server_info.map}. #{server_info.players.size}/#{server_info.sv_maxclients} players" # Base message
      # message += 's' if server_info.players.size != 1 # Pluralize
      message += ': ' if server_info.players.size > 0
      
      sorted_players = server_info.players.sort do |a, b|
        next a.name.downcase <=> b.name.downcase if a.score == b.score
        b.score <=> a.score
      end
      
      # Each player gets an element
      player_parts = sorted_players.map do |player|
        "#{player.name}" + ((player.score == 0) ? ' ' : "(#{player.score}) ")
      end
      
      irc.msg(e.recipient, (message + player_parts.join('15- ')).gsub(/\^[0-9]/, ''))
    else
      case server_info
        when :invalid_address
          irc.msg(e.recipient, "\"#{c.message}\" is not a valid server address. I accept hostname/ip[:port] only.")
        when :bad_response
          irc.msg(e.recipient, "The server sent an invalid response.")
        when :timeout
          irc.msg(e.recipient, "The server failed to respond within #{@urt.server_timeout} seconds.")
      end
    end
  end
  
  if e.message =~ /^#{nick}[:,] (.*?) is (.*)$/
    key = $1
    value = $2
    
    factoid = Factoid.find_by_key($1)
    if not factoid
      factoid = Factoid.new(:key => key, :value => value, :creator => e.sender.nick)
    elsif factoid.locked
      irc.msg(e.recipient, "You can't overwrite a locked factoid.")
      return
    else
      factoid.value = value
      factoid.creator = e.sender.nick
    end
    
    if value =~ /^((<[^>]+>)+)(.+)$/
      factoid.value = $3
      $1.scan(/<([^>]+)>/).each do |flag|
        case flag[0].downcase
          when "nopre"; factoid.prefix = false
          when "action"; factoid.action = true
        end
      end
    end
    
    if factoid.save
      irc.msg(e.recipient, "OK, #{e.sender.nick}.")
    else
      irc.msg(e.recipient, "Unable to store factoid.")
    end
    
  elsif e.message =~ /^#{nick}[:,] (.*)$/
    factoid = Factoid.find_by_key($1)
    if factoid
      if factoid.action
        irc.action(e.recipient, factoid.value + (factoid.prefix ? " [added by #{factoid.creator}]" : ''))
      elsif factoid.prefix
        irc.msg(e.recipient, "#{factoid.key} is #{factoid.value} [added by #{factoid.creator}]")
      else
        irc.msg(e.recipient, '' + factoid.value) # Doublebold
      end
    else
      irc.msg(e.recipient, "Unable to find the #{$1} factoid!")
    end
    
  elsif e.message =~ /^(.*)\+\+$/
    target = $1
    karma = Karma.find_by_target_and_voter(target, e.sender.nick)
    if !karma && e.sender.nick == target
      irc.msg(e.recipient, 'You really thought I was about to let you ++ yourself?')
    elsif !karma
      factoid = Karma.create(:target => target, :voter => e.sender.nick, :positive => true)
      irc.msg(e.recipient, "#{e.sender.nick}: #{target}'s karma has been increased to #{Karma.count(target)}.")
    elsif karma.positive
      irc.msg(e.recipient, "#{e.sender.nick}: You already increased #{target}'s karma.")
    else
      factoid.destroy
      irc.msg(e.recipient, "#{e.sender.nick}: Your negative karma towards #{target} has been removed.")
    end
    
  elsif e.message =~ /^(.*)--$/
    target = $1
    karma = Karma.find_by_target_and_voter(target, e.sender.nick)
    if !karma
      factoid = Karma.create(:target => target, :voter => e.sender.nick, :positive => false)
      irc.msg(e.recipient, "#{e.sender.nick}: #{target}'s karma has been decreased to #{Karma.count(target)}.")
    elsif karma.negative
      irc.msg(e.recipient, "#{e.sender.nick}: You already decreased #{target}'s karma.")
    else
      karma.destroy
      irc.msg(e.recipient, "#{e.sender.nick}: Your positive karma towards #{target} has been removed.")
    end
    
  elsif e.message =~ /^\001ACTION (hugs|licks|kisses|huggles|snuggles up with|loves) #{nick}(.*?)\001$/
    irc.msg(e.recipient, 'Aww :-)')
  
  elsif e.message =~ /^\001ACTION (kills|farts on|eats|drinks|poops on|sets fire to) #{nick}(.*?)\001$/
    irc.msg(e.recipient, "You're mean :-(")
    
  end
  
  parser.command(e, 'karma') do |c, params|
    if params && params.size >= 2
      count = Karma.count params[1]
      irc.msg(e.recipient, "#{params[1]}'s karma is #{count}")
    else
      irc.msg(e.recipient, 'I think you forgot to specify a nick. *cough*fail*cough*')
    end
  end
end

irc.connect
