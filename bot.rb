# Copyright (c) 2009 Daniel Danopia
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of Danopia nor the names of its contributors may be used
#   to endorse or promote products derived from this software without specific
#   prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

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
puts "Loading HPricot, OpenURI, ERB, Set, and the Time class..."
require 'hpricot'
require 'open-uri'
require 'erb'
require 'set'
require 'time'
puts "Loading Redmine..."
require 'redmine'
redmine = Redmine::Server.new('dux.duckinator.net')
puts "Loading BOFH file..."
file = File.open 'excuses'
$bofh = file.readlines

$b = binding()

nick = 'MrTech'

irc = IRC.new( :server => 'Platinum.eighthbit.net',
                 :port => 6667,
                 :nick => nick,
                :ident => 'mrtech',
             :realname => 'MrTech - using on_irc Ruby IRC library',
              :options => { :use_ssl => false } )

parser = Parser.new

irc.on_001 do
	irc.join '#dux,#gaming,#offtopic'
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
    calculation = (doc/'#res/table/tr/td[3]/h2/b').inner_html
    if calculation.empty?
      irc.msg(e.recipient, 'Invalid Calculation.')
    else
      irc.msg(e.recipient, calculation)
    end
  end
  
  parser.command(e, 'issues') do |c, params|
    issues = Set.new(redmine.get_issue_list)
    issues_by_status = issues.classify {|issue| issue.status_id}
    issues_by_status = issues_by_status.map do |status, issues_set|
      "#{issues_set.size} #{Redmine::Issue.statuses[status]}"
    end
    irc.msg(e.recipient, 'Issue statistics for Dux: ' + issues_by_status.join(', '))
  end
  
  parser.command(e, 'badtime') do |c, params|
    irc.msg(e.recipient, (Time.now.utc+(10*60*60)).strftime('It is currently %I:%M:%S %p where baddog lives.'))
  end
  
  parser.command(e, 'bofh') do |c, params|
    irc.msg(e.recipient, $bofh[rand($bofh.size)])
  end
  
  parser.command(e, 'fortune') do |c, params|
    irc.msg(e.recipient, `fortune -s`.chomp.gsub("\n", "\nPRIVMSG #{e.recipient} :"))
  end
  
  parser.command(e, 'long_fortune') do |c, params|
    irc.notice(e.sender.nick, `fortune -l`.chomp.gsub("\n", " \nNOTICE #{e.sender.nick} :"))
  end
  
  #parser.command(e, 'issue') do |c, params|
    #issue = redmine.issues[params[1]]
    #if issue.title
      #if issue.status_id == 5
        #irc.msg e.recipient, "#{issue.project} #{issue.type.downcase} \##{issue.id}: #{issue.title} (#{issue.status})"
      #else
        #irc.msg e.recipient, "#{issue.project} #{issue.type.downcase} \##{issue.id}: #{issue.title} (#{issue.status}, #{issue.percent_done} done)"
      #end
    #else
      #irc.msg e.recipient, "No such issue: \##{params[1]}"
    #end
  #end
  
  parser.command(e, 'dux') do |c, params|
  
#begin
    statuses = {
      1 => 'New',
      2 => 'Assigned',
      3 => 'Resolved',
      4 => 'Feedback',
      5 => 'Closed',
      6 => 'Rejected',
    }
    
    #t.integer :issue_id
    #t.integer :status
    #t.string :subject
    #t.datetime :last_updated

    url = 'http://dux.duckinator.net/issues.xml?set_filter=1&fields[]=status_id&operators[status_id]=*&values[status_id][]=1'

    any_updates = false
    
    doc = Hpricot(open(url))
    issues = (doc/'/issues/issue')
    issues.each do |issue|
      subject = (issue/'/subject').inner_html
      id = (issue/'/id').inner_html
      status = (issue/'/status-id').inner_html.to_i
      last_updated = Time.parse((issue/'/updated-on').inner_html)

      my_record = RedmineIssue.find_by_issue_id(id)
      new = false
      updated = false
      if my_record
        updated = true #(last_updated != my_record.last_updated)
        if updated
          my_record.status = status
          my_record.subject = subject
          my_record.last_updated = last_updated
          my_record.save
        end
      else
        my_record = RedmineIssue.create(:issue_id => id, :status => status, :subject => subject, :last_updated => last_updated)
        new = true
      end
      
      if new
        @redmine_users ||= {}
        user_id = (issue/'/author-id').inner_html.to_i
        unless @redmine_users.has_key?(user_id)
          user_doc = Hpricot(open('http://dux.duckinator.net/account/show/' + user_id.to_s))
          @redmine_users[user_id] = (user_doc/'h2').inner_html.strip
        end
        username = @redmine_users[user_id]
      
        irc.msg('#dux', "Issue \##{id} created by #{username}: #{subject}")
        any_updates = true
      end
      
      if updated
        issue_doc = Hpricot(open('http://dux.duckinator.net/issues/' + id.to_s))
        (issue_doc/'#history/div').each do |entry|
          entry_id = entry.attributes['id'].split('-')[1].to_i
          my_entry = RedmineJournal.find_by_entry_id(entry_id)
          next nil if my_entry
          
          message = (entry/'/div/p').inner_text
          if !message || message.empty?
            changes = (entry/'/ul/li')
            if changes.size == 1
              message = changes[0].inner_html.gsub(/<\/?strong>/, '').gsub(/<\/?i>/, '')
            else
              changes = changes.map do |change|
                "#{(change/'strong')[0].inner_html} set to #{(change/'i').last.inner_html}"
              end
              message = changes.join(', ')
            end
          end
          
          entry_created = Time.parse((entry/'/a').last.attributes['title'])
          author = (entry/'/a')[1].inner_html
          
          RedmineJournal.create(:issue_id => id, :entry_id => entry_id, :message => message, :last_updated => entry_created)
          
          if (entry/'/a').size > 2
            irc.msg('#dux', "Issue \##{id} updated by #{author}: #{message}")
          else
            irc.msg('#dux', "Issue \##{id} updated: #{message}")
          end
          any_updates = true
        end
      end
    end
    
    irc.msg e.recipient, 'No recent updates to the issue trackers.' unless any_updates
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
  
  if e.message =~ /(bug|issue|feature|support|fixes|refs|references|IssueID) #?([0-9]+)/
    ids = e.message.scan(/(bug|issue|feature|support|fixes|refs|references|IssueID) #?([0-9]+)/)
    ids.map! do |match|
      issue = redmine.issues[match[1].to_i]
      
      match[0] = match[0].downcase
      if ['bug', 'feature', 'support'].include? match[0]
        next nil unless issue.type.downcase == match[0]
      elsif match[0] != 'issue'
        next nil unless e.sender.nick =~ /^CIA-/
      end
      
      if issue.title
        if issue.status_id == 5
          next "#{issue.project} #{issue.type.downcase} \##{issue.id}: #{issue.title} (#{issue.status}) <http://dux.duckinator.net/issues/#{issue.id}>"
        else
          next "#{issue.project} #{issue.type.downcase} \##{issue.id}: #{issue.title} (#{issue.status}, #{issue.percent_done} done) <http://dux.duckinator.net/issues/#{issue.id}>"
        end
      else
        next "No such issue: \##{match[1]}"
      end
    end
    
    irc.msg e.recipient, ids.compact.join('  |  ')
  
  elsif e.message =~ /^#{nick}[:,] (.*?) is (.*)$/
    key = $1
    value = $2
    
    factoid = Factoid.find_by_key($1)
    if not factoid
      factoid = Factoid.new(:key => key, :value => value, :creator => e.sender.nick)
    elsif factoid.locked && (e.sender.nick != 'danopia')
      irc.msg(e.recipient, "You can't overwrite a locked factoid.")
      break
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
          when "lock"; factoid.locked = (e.sender.nick == 'danopia')
          when "clear"; factoid.action = false; factoid.prefix = true
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
      value = factoid.value.gsub('%n', e.sender.nick).gsub('%c', e.recipient)
      if value =~ /^\[.+\|\|.+\]$/
        values = value[1..-2].split('||')
        value = values[(rand * values.size).to_i]
      end
      
      if factoid.action
        irc.action(e.recipient, value + (factoid.prefix ? " [added by #{factoid.creator}]" : ''))
      elsif factoid.prefix
        irc.msg(e.recipient, "#{factoid.key} is #{value} [added by #{factoid.creator}]")
      else
        irc.msg(e.recipient, '' + value) # Doublebold
      end
    else
      irc.msg(e.recipient, "Unable to find the #{$1} factoid!")
    end
    
  elsif e.message =~ /^(.*)\+\+$/
    target = $1
    karma = Karma.find_by_target_and_voter(target, e.sender.nick)
    if !karma && e.sender.nick == target
      #irc.msg(e.recipient, 'You really thought I was about to let you ++ yourself?')
    elsif !karma
      factoid = Karma.create(:target => target, :voter => e.sender.nick, :positive => true)
      #irc.msg(e.recipient, "#{e.sender.nick}: #{target}'s karma has been increased to #{Karma.count(target)}.")
    elsif karma.positive
      #irc.msg(e.recipient, "#{e.sender.nick}: You already increased #{target}'s karma.")
    else
      factoid.destroy
      #irc.msg(e.recipient, "#{e.sender.nick}: Your negative karma towards #{target} has been removed.")
    end
    
  elsif e.message =~ /^(.*)--$/
    target = $1
    karma = Karma.find_by_target_and_voter(target, e.sender.nick)
    if !karma
      factoid = Karma.create(:target => target, :voter => e.sender.nick, :positive => false)
      #irc.msg(e.recipient, "#{e.sender.nick}: #{target}'s karma has been decreased to #{Karma.count(target)}.")
    elsif karma.negative
      #irc.msg(e.recipient, "#{e.sender.nick}: You already decreased #{target}'s karma.")
    else
      karma.destroy
      #irc.msg(e.recipient, "#{e.sender.nick}: Your positive karma towards #{target} has been removed.")
    end
    
  elsif e.message =~ /^\001ACTION (hugs|licks|kisses|huggles|snuggles up with|loves) #{nick}(.*?)\001$/
    irc.msg(e.recipient, 'Aww :-)')
  elsif e.message =~ /^\001ACTION (kills|farts on|eats|drinks|poops on|sets fire to|bites) #{nick}(.*?)\001$/
    irc.msg(e.recipient, "You're mean :-(")
  
  elsif e.message =~ /^\001VERSION\001$/
    irc.notice(e.sender.nick, "\001VERSION MrTech - using on_irc Ruby IRC library\001")
  elsif e.message =~ /^\001PING\001$/
    irc.notice(e.sender.nick, "\001PING\001")
  elsif e.message =~ /^\001PING (.+)\001$/
    irc.notice(e.sender.nick, "\001PING #{$1}\001")
  elsif e.message =~ /^\001FINGER\001$/
    irc.notice(e.sender.nick, "\001FINGER Ewwwwwww... I dunno what to put here... maybe you want to VERSION me? :)\001")
    
  end
  
  parser.command(e, 'lock') do |c, params|
    factoid = Factoid.find_by_key(params[1..-1].join(' '))
    if not factoid
      irc.msg(e.recipient, "Factoid not found.")
    elsif factoid.locked
      irc.msg(e.recipient, "That's already locked.")
    else
      factoid.locked = (e.sender.nick == 'danopia')
      factoid.save
      irc.msg(e.recipient, "Locked.")
    end
  end
  
  parser.command(e, 'unlock') do |c, params|
    factoid = Factoid.find_by_key(params[1..-1].join(' '))
    if not factoid
      irc.msg(e.recipient, "Factoid not found.")
    elsif not factoid.locked
      irc.msg(e.recipient, "That's already unlocked.")
    else
      factoid.locked = false if e.sender.nick == 'danopia'
      factoid.save
      irc.msg(e.recipient, "Unlocked.")
    end
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
