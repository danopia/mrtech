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
puts "Loading HPricot, OpenURI and ERB..."
require 'hpricot'
require 'open-uri'
require 'erb'

$b = binding()

nick = 'on_irc_chuck'

irc = IRC.new( :server => 'irc.freenode.org',
                 :port => 6667,
                 :nick => nick,
                :ident => 'on_irc',
             :realname => 'on_irc Ruby IRC library',
              :options => { :use_ssl => false } )

parser = Parser.new

irc.on_001 do
	irc.join '##gpt'
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
  
  parser.command(e, 'eval', true) do |c, params|
    begin
      irc.msg(e.recipient, eval(c.message, $b, 'eval', 1))
    rescue Exception => error
      irc.msg(e.recipient, 'compile error')
    end
  end
  
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
