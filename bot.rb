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
      message = "UrT stats for #{server_info.sv_hostname}: Game mode is #{server_info.game_type} on #{server_info.map}. #{server_info.players.size}/#{server_info.sv_maxclients} players" # Base message
      # message += 's' if server_info.players.size != 1 # Pluralize
      message += ': ' if server_info.players.size > 0
      
      # Each player gets an element
      player_parts = server_info.players.map do |player|
        "#{player.name} (#{player.score})"
      end
      
      irc.msg(e.recipient, message + player_parts.join(' 15- '))
    else
      case server_info
        when :invalid_address
          irc.msg(e.recipient, "\"#{c.message}\" is not a valid server address. I accept hostname/ip[:port] only.")
        when :bad_response
          irc.msg(e.recipient, "The server sent an invalid response.")
        when :timeout
          irc.msg(e.recipient, "The server failed to respond within #{@urt.timeout} seconds.")
      end
    end
  end
  
  if e.message =~ /^#{nick}: (.*?) is (.*)$/
    key = $1
    value = $2
    
    if Factoid.create(:key => key, :value => value, :creator => e.sender.nick)
      irc.msg(e.recipient, "OK, #{e.sender.nick}.")
    else
      irc.msg(e.recipient, "Unable to store factoid.")
    end
  elsif e.message =~ /^#{nick}: (.*)$/
    factoid = Factoid.find_by_key($1)
    if factoid
      irc.msg(e.recipient, "#{factoid.key} is #{factoid.value} [added by #{factoid.creator}]")
    else
      irc.msg(e.recipient, "Unable to find the #{$1} factoid!")
    end
  end
  
  if e.message =~ /^\001ACTION (hugs|licks|kisses|huggles|snuggles up with|loves) #{nick}(.*?)\001$/
    irc.msg(e.recipient, 'Aww :-)')
  end
  
  if e.message =~ /^\001ACTION (kills|farts on|eats|drinks|poops on|sets fire to) #{nick}(.*?)\001$/
    irc.msg(e.recipient, "You're mean :-(")
  end
end

irc.connect
