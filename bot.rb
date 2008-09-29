$LOAD_PATH << './lib'
require 'irc'
require 'parser'
require 'rubygems'
require 'activerecord'
require 'models'

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
	irc.join '#botters'
end

irc.on_all_events do |e|
	p e
end

irc.on_invite do |e|
  irc.join(e.channel)
end

irc.on_join do |e|
  irc.msg(e.channel, "Hey #{e.sender.nick}, and welcome to #{e.channel}!") if e.sender.nick != nick
end

irc.on_privmsg do |e|
  parser.command(e, 'whatis') do |c, params|
    factoid = Factoid.find_by_key(c.message)
    if factoid
      irc.msg(e.recipient, "#{factoid.key} is #{factoid.value} [added by #{factoid.creator}]")
    else
      irc.msg(e.recipient, "Unable to find the #{factoid.key} factoid!")
    end
  end
  
  parser.command(e, 'eval', true) do |c, params|
    begin
      irc.msg(e.recipient, eval(c.message, $b, 'eval', 1))
    rescue Exception => error
      irc.msg(e.recipient, 'compile error')
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
      irc.msg(e.recipient, "Unable to find the #{factoid.key} factoid!")
    end
  end
end

irc.connect
