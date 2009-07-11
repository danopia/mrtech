# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
# 
# * Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above
#   copyright notice, this list of conditions and the following disclaimer
#   in the documentation and/or other materials provided with the
#   distribution.
# * Neither the name of the Danopia nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Simple Armagetron Advanced stats requester
require 'socket'
require 'timeout'
require 'ipaddr'
require 'stringio' # For packet messages

class ArmPacket
	attr_accessor :senderid
	attr_accessor :messages
	
	# Create a new ArmServerInfo instance
	def initialize(senderid=0, messages=[])
		@senderid = senderid.to_i
		@messages = messages || []
	end
	
	def self.parse(data)
		packet = ArmPacket.new
		index = 0
		while data.size >= index + 6
			descriptor, msgid, size = data[index, 6].unpack('n*')
			size *= 2 # Size is halfed, probably because of the endian-ness
			break if data.size < index + 6 + size
			message = ArmPacketMessage.new(descriptor, msgid, data[index+6, size])
			index += 6 + size
			packet << message
		end
		packet.senderid = data[index, 2].unpack('n')[0]
		packet
	end
	
	# Yay endian
	def self.flip(data)
		data.gsub(/(.)(.)/, '\2\1')
	end
	
	def <<(message)
		return unless message.is_a? ArmPacketMessage
		messages << message
	end
	
	# Return a network-ready packet
	def string
		@messages.map{|msg|msg.string}.join('') + [@senderid].pack('n')
	end
end

class ArmPacketMessage < StringIO
	attr_accessor :descriptor, :msgid

	def initialize(descriptor, msgid, data='')
		@descriptor = descriptor.to_i
		@msgid = msgid.to_i
		super()
		self << data unless !data || data.empty?
	end
	
	# Return a network-ready packet
	def string
		[descriptor, msgid, (size/2).to_i].pack('n*') + 
			super#.gsub(/(.)(.)/, '\2\1')
	end
end

# Stores data about servers so that you can retrieve it.
class ArmServerInfo
	# Hash of the data the server returned
	attr_accessor :data
	
	# Array of String
	attr_accessor :players	
	
	# Create a new ArmServerInfo instance
	def initialize(data, players=[])
		@data = data
		@players = players
	end
end

# The main workhorse, Arm contains methods to pull server info.
class Arm
	attr_accessor :default_server, :default_port
	
	# Init the class with some defaults. Note that default_server can contain a
	# port, and default_port is seperate. You'll probably also want to leave
	# default_port to the default. Here's how it works. Say your main server is
	# at example.com:12345, but you want calls to other servers to default to
	# 54321 if there's no port specified:
	#
	#   arm = Arm.new('example.com:12345', 54321)
	def initialize(default_server=nil, default_port=4534)
		@default_server = default_server
		@default_port = default_port
	end
	
	# Lets you send ArmPacket objects to a server. You probably won't use this.
	def send(packet)
		@@socket ||= UDPSocket.open
		@@socket.send(packet.string, 0, server, port)
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
