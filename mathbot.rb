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
irc = $irc

parser = Parser.new

irc.on_001 do
	irc.join '#offtopic,#duckinator,##danopia'
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

class Float
	alias :to_float_s :to_s
	
	def to_s
		return to_i.to_s unless self % 1 > 0
		to_float_s
	end
end

class Quantity
	attr_accessor :members
	def initialize(param=nil, mode=nil, func=nil)
		@members = []
		@buffer = ''
		@variable = ''
		@function = func
		@mode = mode
		
		if param.is_a? StringIO
			io = param
			until io.eof?
				chr = io.read(1)
				case chr
				
					when ')'
						raise(ParseError, 'Unexpected ): no matching (') if @mode == :root
						raise(ParseError, 'Unexpected ): no matching (, expected |') if @mode == :abs
						handle_buffer
						break
				
					when '|'
						handle_buffer
						if @mode == :abs
							break
						else
							quantity = Quantity.new(io, :abs)
							implied_multiplication quantity
						end
						
					when '('
						quantity = Quantity.new(io)
						implied_multiplication quantity
						
					when '0'..'9', '.'
						raise ParseError, 'Spaces can\'t exist inside numbers right now, sorry.' if (!@members.empty? && @members.last.is_a?(Float))
						raise ParseError, 'Numbers can\' be after quantities or variables unless you include an explicit operator.' if (!@members.empty? && !@members.last.is_a?(String))
						@buffer += chr
						
					when 'a'..'z'
						raise ParseError, 'Spaces can\'t exist inside numbers right now, sorry.' if (!@members.empty? && @members.last.is_a?(Float))
						@buffer += chr
						
					when '+', '-', '*', '/'
						add_operator chr
					when '^'
						add_operator '**'
					when ' '
						handle_buffer
					else
						raise ParseError, "Invalid charactor \"#{chr}\""
				end
			end
			
			handle_buffer
		end
	end
	
	def to_s
		return '|' + to_root_s + '|' if @mode == :abs
		'(' + to_root_s + ')'
	end
	def to_root_s # used for a root quantity so that the whole expression isn't wrapped with ( )
		@members.join(' ')
	end
	
	def to_f
		operation = ''
		members = @members
	
		[['**'], ['*', '/'], ['+', '-']].each do |operators|
			members.select{|member| operators.include? member }.each do |member|
				pos = members.index member
				number1 = members[pos-1].to_f
				number2 = members[pos+1].to_f
				members[pos-1] = number1.send(member, number2).to_f
				members.delete_at pos
				members.delete_at pos
			end
		end
		
		return members[0].abs if @mode == :abs
		members[0].to_f
	end
	
	protected
	def handle_buffer
		false
		if !@buffer.empty?
			@members << @buffer.to_f
			@buffer = ''
			true
		end
	end
	
	def add_operator(operator)
		handle_buffer
		if (@members.empty? || @members.last.is_a?(String))
			if operator == '-'
				raise ParseError, 'Negatives aren\'t implemented like that yet. Please use (0-###) instead of -###.'
			else
				raise ParseError, "Unexpected operator \"#{operator}\"; expected practically anything else."
			end
		else
			@members << operator
		end
	end
	
	def implied_multiplication(value)
		if handle_buffer || (!@members.empty? && !@members.last.is_a?(String))
			@members << '*'
		end
		@members << value
	end
end

irc.on_privmsg do |e|
  parser.command(e, 'solve', true) do |c, params|
  	output = ''
  	
		io = StringIO.new(c.message)
		begin
			quantity = Quantity.new(io, true)
			p quantity
			irc.msg e.recipient, "#{quantity.to_root_s} = #{quantity.to_f}"
		rescue ParseError => error
			irc.msg e.recipient, "Error while parsing your expression: #{error.message}"
		end
    
  end
end

irc.connect
