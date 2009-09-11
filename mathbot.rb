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
puts "Loading HPricot, OpenURI, ERB, Set, and the Time class..."
require 'hpricot'
require 'open-uri'
require 'erb'
require 'set'
require 'time'

$b = binding()

nick = 'MrTech'

#irc = IRC.new( :server => 'Platinum.eighthbit.net',
#                 :port => 6667,
#                 :nick => nick,
#                :ident => 'mrtech',
#             :realname => 'MrTech - using on_irc Ruby IRC library',
#              :options => { :use_ssl => false } )
require 'init-irc'

parser = Parser.new

irc.on_001 do
	irc.join '#offtopic,#duckinator'
end

irc.on_all_events do |e|
	p e
end

irc.on_invite do |e|
  #irc.join(e.channel)
end

# Uncomment this block if you want it to greet people
#irc.on_join do |e|
#  irc.msg(e.channel, "Hey #{e.sender.nick}, and welcome to #{e.channel}!") if e.sender.nick != nick
#end

require 'stringio'

class ParseError < Exception
end

class Quantity
	def self.parse(io, root=false)
		buffer = ''
		quantity = Quantity.new()
		until io.eof?
			chr = io.read(1)
			case chr
				when ')'
					raise(ParseError, 'Unexpected ): no matching (') if root
					if !buffer.empty?
						quantity.members << buffer.to_f
						buffer = ''
					end
					break
				when '('
					subquantity = Quantity.parse(io)
					if buffer.empty? && (quantity.members.empty? || quantity.members.last.is_a?(String))
						quantity.members << subquantity
					elsif !buffer.empty?
						quantity.members << buffer.to_f
						buffer = ''
						quantity.members << '*'
						quantity.members << subquantity
					elsif !quantity.members.empty? && !quantity.members.last.is_a?(String)
						quantity.members << '*'
						quantity.members << subquantity
					else
						raise ParseError, 'HALP! (error #1)'
					end
				when '0'..'9', '.'
					buffer += chr
					# value = number1.to_f.send(operation, number2.to_f)
				when '+', '-', '*', '/'
					if !buffer.empty?
						quantity.members << buffer.to_f
						buffer = ''
					end
					if (quantity.members.empty? || quantity.members.last.is_a?(String))
						if chr == '-'
							raise ParseError, 'HALP! (error #2)'
						else
							raise ParseError, "Unexpected operator \"#{chr}\"; expected a number or quantity"
						end
					else
						quantity.members << chr
					end
				when '^'
					if !buffer.empty?
						quantity.members << buffer.to_f
						buffer = ''
					end
					if (quantity.members.empty? || quantity.members.last.is_a?(String))
						raise ParseError, "Unexpected operator \"#{chr}\"; expected a number or quantity"
					else
						quantity.members << '**'
					end
				else
					raise ParseError, "Invalid charactor \"#{chr}\""
  		end
		end
		
		if !buffer.empty?
			quantity.members << buffer.to_f
			buffer = ''
		end
		
		quantity
	end
	
	attr_accessor :members
	def initialize(param=nil)
		if param.is_a? String
			# TODO: parse
		else
			@members = []
		end
	end
	
	def value
		before = ''
		after = 0.to_f
		operation = ''
		
		members = @members
		
		@operator_levels = {
			0 => ['**'],
			1 => ['*', '/'],
			2 => ['+', '-']
		}
		
		# Create initial string
		members.each do |member|
			if member.is_a? String
				before += " #{member} "
			elsif member.is_a? Float
				before += member.to_s
			elsif member.is_a? Quantity
				result = member.value
				before += "(#{result[0]})"
			else
				raise ParseError, "Wow I failed somewhere. (Extra exception data: #{member.class}"
			end
		end
		
		@operator_levels.each_value do |operators|
			p members
			members.select{|member|operators.include? member}.each do |member|
				pos = members.index member
				number1 = members[pos-1]
				number1 = number1.value[1] if number1.is_a? Quantity
				number2 = members[pos+1]
				number2 = number2.value[1] if number1.is_a? Quantity
				members[pos-1] = number1.to_f.send(member, number2.to_f).to_f
				members.delete_at pos
				members.delete_at pos
			end
		end
		
		p members
		
		[before, members[0]]
	end
end

irc.on_privmsg do |e|
  
  parser.command(e, 'solve', true) do |c, params|
  	output = ''
  	
		io = StringIO.new(c.message)
		begin
			quantity = Quantity.parse(io, true)
			value = quantity.value
			irc.msg e.recipient, "#{value[0]} = #{value[1]}"
		rescue ParseError => error
			irc.msg e.recipient, "Error while parsing your expression: #{error.message}"
		end
    
  end
  
end

irc.connect
