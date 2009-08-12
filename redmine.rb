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

module Redmine
	
	class Users
		attr_accessor :domain
		
		def initialize(domain)
			@domain = domain
			@users = {}
			@ages = {}
		end
		
		def [](id)
			@users.delete(id) if @users.has_key?(id) && Time.now - @ages[id] > 43200 # 12 hours
			
			if !(@users.has_key?(id))
				@users[id] = User.new(@domain, id)
				@ages[id] = Time.now
			end
			
			@users[id]
		end
	end

	class User
		attr_accessor :id, :name, :email, :registered_at, :last_login_at, :projects, :reported_issues, :activity
		
		def initialize(domain, id)
			doc = Hpricot(open("http://#{domain}/account/show/#{id}"))
			
			@id = id.to_i
			@name = (doc/'h2').inner_html.strip
			@email = User.extract_email((doc/'#content/.splitcontentleft/ul/li/script').inner_html)
			@registered_at = User.extract_date((doc/'#content/.splitcontentleft/ul/li[2]').inner_html)
			@last_login_at = User.extract_date((doc/'#content/.splitcontentleft/ul/li[3]').inner_html)
			
			@projects = (doc/'#content/.splitcontentleft/ul[2]/li/a').map do |element|
				element.inner_html
			end
			
			@reported_issues = User.extract_number((doc/'#content/.splitcontentright/p[1]').inner_html)
			
			@activity = []
		end
		
		def self.extract_email(script)
			script =~ /'(.+)'/
			[$1.gsub('%', '')].pack('H*') =~ />(.+)</
			$1
		end
		def self.extract_date(str)
			str =~ /([0-9\/]+)/
			Date.parse($1)
		end
		def self.extract_number(str)
			str =~ /([0-9.]+)/
			$1
		end
	end
	
	class Issues
		attr_accessor :domain
		
		def initialize(domain)
			@domain = domain
			@issues = {}
			@ages = {}
		end
		
		def [](id)
			@issues.delete(id) if @issues.has_key?(id) && Time.now - @ages[id] > 600 # 10 minutes
			
			if !(@issues.has_key?(id))
				@issues[id] = Issue.new(@domain, id)
				@ages[id] = Time.now
			end
			
			@issues[id]
		end
	end
	
	class Issue
		attr_accessor :id, :type, :project, :title, :author, :created_at, :updated_at, :status_id, :priority_id, :assigned_to
		attr_accessor :category, :target_version, :start, :due, :percent_done, :spent_time
		attr_accessor :description, :updates, :revisions
		
		def initialize(domain, id)
			doc = nil
			begin
				doc = open("http://#{domain}/issues/#{id}")
				doc = Hpricot(doc)
				return nil if !doc || (doc/'.author/a').empty?
			rescue OpenURI::HTTPError
				return nil
			end
			
			@id = id.to_i
			@project = (doc/'h1').inner_html
			@type = (doc/'h2')[0].inner_html.split(' ')[0]
			@title = (doc/'.issue/h3').inner_html
			@author = User.new(domain, Issue.extract_number((doc/'.author/a')[0].attributes['href']))
			@created_at = Time.parse((doc/'.author/a')[1].attributes['title'])
			@updated_at = (doc/'.author/a')[2]
			@updated_at = Time.parse(@updated_at.attributes['title']) if @updated_at
			
			(doc/'.issue')[0].attributes['class'] =~ /status-([0-9]+) priority-([0-9]+)/
			@status_id = $1.to_i
			@priority_id = $2.to_i
			
			@assigned_to = (doc/'.issue/table/tr/td')[9].inner_text
			@assigned_to = nil if @assigned_to == '-'
			@assigned_to = User.new(domain, Issue.extract_number((doc/'.issue/table/tr/td/a')[0].attributes['href'])) if @assigned_to
			
			@category = (doc/'.issue/table/tr/td')[13].inner_text
			@category = nil if @category == '-'
			
			@target_version = (doc/'.issue/table/tr/td')[17].inner_text
			@target_version = nil if @target_version == '-'
			
			@start = Date.parse((doc/'.issue/table/tr/td')[3].inner_html)
			
			@due = (doc/'.issue/table/tr/td')[7].inner_html
			@due = nil if @due.empty?
			@date = Date.parse(@due) if @due
			
			@percent_done = (doc/'.issue/table/tr/td')[11].inner_text
			
			@spent_time = (doc/'.issue/table/tr/td')[15].inner_text
			@spent_time = nil if @spent_time == '-'
			
			@description = (doc/'.issue/.wiki/p').map{|ele|ele.inner_text}.join("\n")
			
			@revisions = []
			
			@updates = []
			
			#doc = Hpricot(open("http://#{@domain}/issues/#{id}"))
			#(doc/'#history/div').each do |entry|
				#entry_id = entry.attributes['id'].split('-')[1].to_i
				#my_entry = RedmineJournal.find_by_entry_id(entry_id)
				#next nil if my_entry
				
				#message = (entry/'/div/p').inner_text
				#if !message || message.empty?
					#changes = (entry/'/ul/li')
					#if changes.size == 1
						#message = changes[0].inner_html.gsub(/<\/?strong>/, '').gsub(/<\/?i>/, '')
					#else
						#changes = changes.map do |change|
							#"#{(change/'strong')[0].inner_html} set to #{(change/'i').last.inner_html}"
						#end
						#message = changes.join(', ')
					#end
				#end
				
				#entry_created = Time.parse((entry/'/a').last.attributes['title'])
				#author = (entry/'/a')[1].inner_html
				
				#RedmineJournal.create(:issue_id => id, :entry_id => entry_id, :message => message, :last_updated => entry_created)
				
				#if (entry/'/a').size > 2
					#irc.msg('#dux', "Issue \##{id} updated by #{author}: #{message}")
				#else
					#irc.msg('#dux', "Issue \##{id} updated: #{message}")
				#end
				#any_updates = true
			#end
			
			#@name = (doc/'h2').inner_html.strip
			#@email = UserInfo.extract_email((doc/'#content/.splitcontentleft/ul/li/script').inner_html)
			#@registered_at = UserInfo.extract_date((doc/'#content/.splitcontentleft/ul/li[2]').inner_html)
			#@last_login_at = UserInfo.extract_date((doc/'#content/.splitcontentleft/ul/li[3]').inner_html)
			
			#@projects = (doc/'#content/.splitcontentleft/ul[2]/li/a').map do |element|
				#element.inner_html
			#end
			
			#@reported_issues = UserInfo.extract_number((doc/'#content/.splitcontentright/p[1]').inner_html)
			
			#@activity = []
			
			@@statuses ||= {
				1 => 'New',
				2 => 'Assigned',
				3 => 'Resolved',
				4 => 'Feedback',
				5 => 'Closed',
				6 => 'Rejected',
			}
			@@priorities ||= {
				3 => 'Low',
				4 => 'Normal',
				5 => 'High',
				6 => 'Urgent',
				7 => 'Immediate',
			}
		end
		
		def self.statuses
			@@statuses ||= {
				1 => 'New',
				2 => 'Assigned',
				3 => 'Resolved',
				4 => 'Feedback',
				5 => 'Closed',
				6 => 'Rejected',
			}
			@@statuses
		end
		def self.priorities
			@@priorities ||= {
				3 => 'Low',
				4 => 'Normal',
				5 => 'High',
				6 => 'Urgent',
				7 => 'Immediate',
			}
			@@priorities
		end
		
		def self.extract_date(str)
			str =~ /([0-9\/]+)/
			Date.parse($1)
		end
		def self.extract_number(str)
			str =~ /([0-9.]+)/
			$1
		end
		
		def status
			@@statuses[@status_id]
		end
		def priority
			@@priorities[@priority_id]
		end
	end
	
	class Server
		attr_accessor :domain, :users, :issues
		
		def initialize(domain)
			@domain = domain
			@users = Users.new(@domain) # Hash.new{|hash, id| hash[id] = User.new(domain, id.to_i) }
			@issues = Issues.new(@domain)
		end
		
		def get_issue_list()
			url = "http://#{domain}/issues.xml?set_filter=1&fields[]=status_id&operators[status_id]=*&values[status_id][]=1"

			doc = Hpricot(open(url))
			issues = (doc/'/issues/issue')
			issues.map! do |issue|
				#class Issue
				#attr_accessor :id, :type, :project, :title, :author, :created_at, :updated_at, :status_id, :priority_id, :assigned_to
				#attr_accessor :category, :target_version, :start, :due, :percent_done, :spent_time
				#attr_accessor :description, :updates, :revisions
			
				issue_obj = Issue.allocate
				issue_obj.title = (issue/'/subject').inner_html
				issue_obj.id = (issue/'/id').inner_html
				issue_obj.status_id = (issue/'/status-id').inner_html.to_i
				issue_obj.updated_at = Time.parse((issue/'/updated-on').inner_html)
				issue_obj
			end
			
			issues
		end
		
		
		
		
		
		def get_issue_details(id)
			doc = Hpricot(open("http://#{@domain}/issues/#{id}"))
			(doc/'#history/div').each do |entry|
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
		
	def get_issue_updates()
    url = "http://#{domain}/issues.xml?set_filter=1&fields[]=status_id&operators[status_id]=*&values[status_id][]=1"

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
        author_id = (issue/'/author-id').inner_html.to_i
      	author = @user_info[author_id]
        username = author.name
      
        irc.msg('#dux', "Issue \##{id} created by #{username}: #{subject}")
        any_updates = true
        updated = true
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
end
end
