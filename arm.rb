# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.

# Simple Armagetron Advanced stats requester
require 'socket'
require 'timeout'
require 'ipaddr'

# Stores data about servers so that you can retrieve it.
class ArmServerInfo
	# Hash of the data the server returned
	attr_accessor :data
	
	# Array of String
	attr_accessor :players	
	
	# Create a new UrTServerInfo instance
	def initialize(data, players=[])
		@data = data
		@players = players
	end
	
	# Shorter way to access data
	def method_missing(m, *args, &blck)
		raise NoMethodError, "undefined method '#{m}' for #{self}" unless data.has_key?(m.to_s)
		raise ArgumentError, "wrong number of arguments (#{args.length} for 0)" if args.length > 0

		data[m.to_s]
	end
end

# The main workhorse, UrT contains methods to pull server info.
class UrT
	attr_accessor :default_server, :default_port
	
	# Init the class with some defaults. Note that default_server can contain a
	# port, and default_port is seperate. You'll probably also want to leave
	# default_port to the default. Here's how it works. Say your main server is
	# at example.com:12345, but you want calls to other servers to default to
	# 54321 if there's no port specified:
	#
	#   urt = UrT.new('example.com:12345', 54321)
	def initialize(default_server=nil, default_port=27960)
		@default_server = default_server
		@default_port = default_port
	end
	
	# Lets you send connectionless, null-terminated packets to a server. You
	# probably won't use this.
	def command(cmd, server, port)
		@@socket ||= UDPSocket.open
		@@socket.send("\xFF\xFF\xFF\xFF#{cmd}\x00", 0, server, port)
		@@socket.flush
	end
	
	# Recieves a packet from the server, stripping off a header. You probably
	# won't use this.
	def recv()
		@@socket.recvfrom(65536)[0][4..-1]
	end
	
	# This handy utility takes a string (as you would feed in on a command line
	# or via IRC) and parses it for a port and hostname/ip, defaulting the port
	# to the value of default_port. You probably won't use this though.
	def parse_address(address)
		return nil unless address.is_a? String
		address = address.split(':')
		return nil unless [1,2].include?(address.size)
		
		# Parse the port, try an IP first
		host = nil
		begin
			host = IPAddr.new(address[0]).to_s
			
		# Not an IP, try hostname
		rescue ArgumentError
			if not (address[0] =~/^([a-z]+\.?)+$/)
				return nil # Not a hostname either
			end
			
			# Save the hostname. I'll catch errors on connect so invalid hostnames
			# will be caught then.
			host = address[0]
		end
		
		# Now parse the port, if there is one
		port = @default_port
		if address.size == 2
			port == address[1].to_i
			return nil if port < 1 # Catch non-numbers and negative ports
		end
		
		[host, port] # Return host/port pair
	end

	# This is what you *will* use. get_stats takes an optional server name
	# (defaults to default_server) and polls it for stats, then returns an
	# instance of UrTServerInfo.
	#
	# === Errors
	# On failure, get_stats will return a Symbol. Possible symbols:
	#
	#   :invalid_address   Error parsing the +server+ field, or the hostname
	#                      couldn't resolve.
	#   :bad_response      The server's response couldn't be parsed.
	#   :timeout           The server didn't respond before the specified
	#                      timeout. Might be lagging badly or not running.
	#
	# === Examples
	#   @urt ||= UrT.new('games.eighthbit.net')
	#   server_info = @urt.get_stats(c.message)
	#   
	#   if server_info.is_a? UrTServerInfo
	#   	puts "UrT stats for #{server_info.sv_hostname}:"
	#   	puts "Game mode is #{server_info.game_type}
	#   	puts "Map is #{server_info.map}
	#   	puts "#{server_info.players.size} out of #{server_info.sv_maxclients} players"
	#   	
	#   	server_info.players.each do |player|
	#   		puts "#{player.name} with #{player.score} points"
	#   	end
	#   else
	#   	case server_info
	#   		when :invalid_address
	#   			puts "ERROR: Invalid server address. I accept hostname/ip[:port] only."
	#   		when :bad_response
	#   			puts "ERROR: The server sent an invalid response."
	#   		when :timeout
	#   			puts "ERROR: The server failed to respond within 5 seconds."
	#   	end
	#   end
	def get_stats(server=nil)
		begin # Catch errors
			timeout(5) do # Timeout after 5 seconds for bad servers

				# Default to the default server
				server ||= @default_server
				
				# Parse the server to make sure it's valid
				server = parse_address server
				return :invalid_address if server == nil # Pass along invalid address nil's
			
				command 'getstatus', server[0], server[1] # Send status command to server

				# Get and parse data
				data = recv.split("\n")
				return :bad_response if data[0] != 'statusResponse' # Real response?
				return :bad_response if data.size < 2 # Needs to have at least 2 lines

				# This may look intimidating, but it's not.
				#
				# It takes every /key/value pair from the second line, puts them in arrays,
				# then the Hash[] format makes it into a hash.
				
				#info = Hash[data[1].scan(/([^\\]+)\\([^\\]+)/).flatten]
				info = {}
				data[1].scan(/([^\\]+)\\([^\\]+)/).each do |pair|
					info[pair[0]] = pair[1]
				end

				# Make a new object
				serverinfo = UrTServerInfo.new(info)

				# After the first 2 lines, the rest are for players.
				#
				#   [score, ping, name]
				serverinfo.players = data[2..-1].map do |item|
					items = item.split(' ')
					UrTPlayerInfo.new(items[0].to_i, items[1].to_i, items[2..-1].join(' ').gsub('"', ''))
				end
				
				# Return the server info
				return serverinfo
			end
		rescue Timeout::Error
			:timeout
		rescue SocketError
			:invalid_address
		end
	end
end
