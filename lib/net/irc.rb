#!ruby

require "ostruct"
require "socket"
require "thread"
require "logger"

module Net; end

module Net::IRC
	VERSION = "0.0.0"
	class IRCException < StandardError; end

	module PATTERN
		# letter     =  %x41-5A / %x61-7A       ; A-Z / a-z
		# digit      =  %x30-39                 ; 0-9
		# hexdigit   =  digit / "A" / "B" / "C" / "D" / "E" / "F"
		# special    =  %x5B-60 / %x7B-7D
		#                  ; "[", "]", "\", "`", "_", "^", "{", "|", "}"
		LETTER   = 'A-Za-z'
		DIGIT    = '\d'
		HEXDIGIT = "#{DIGIT}A-Fa-f"
		SPECIAL  = '\x5B-\x60\x7B-\x7D'

		# shortname  =  ( letter / digit ) *( letter / digit / "-" )
		#               *( letter / digit )
		#                 ; as specified in RFC 1123 [HNAME]
		# hostname   =  shortname *( "." shortname )
		SHORTNAME = "[#{LETTER}#{DIGIT}](?:[-#{LETTER}#{DIGIT}]*[#{LETTER}#{DIGIT}])?"
		HOSTNAME  = "#{SHORTNAME}(?:\\.#{SHORTNAME})*"

		# servername =  hostname
		SERVERNAME = HOSTNAME

		# nickname   =  ( letter / special ) *8( letter / digit / special / "-" )
		#NICKNAME = "[#{LETTER}#{SPECIAL}\\w][-#{LETTER}#{DIGIT}#{SPECIAL}]*"
		NICKNAME = "\\S+" # for multibytes

		# user       =  1*( %x01-09 / %x0B-0C / %x0E-1F / %x21-3F / %x41-FF )
		#                 ; any octet except NUL, CR, LF, " " and "@"
		USER = '[\x01-\x09\x0B-\x0C\x0E-\x1F\x21-\x3F\x41-\xFF]+'

		# ip4addr    =  1*3digit "." 1*3digit "." 1*3digit "." 1*3digit
		IP4ADDR = "[#{DIGIT}]{1,3}(?:\\.[#{DIGIT}]{1,3}){3}"
		# ip6addr    =  1*hexdigit 7( ":" 1*hexdigit )
		# ip6addr    =/ "0:0:0:0:0:" ( "0" / "FFFF" ) ":" ip4addr
		IP6ADDR = "(?:[#{HEXDIGIT}]+(?::[#{HEXDIGIT}]+){7}|0:0:0:0:0:(?:0|FFFF):#{IP4ADDR})"
		# hostaddr   =  ip4addr / ip6addr
		HOSTADDR = "(?:#{IP4ADDR}|#{IP6ADDR})"

		# host       =  hostname / hostaddr
		HOST = "(?:#{HOSTNAME}|#{HOSTADDR})"

		# prefix     =  servername / ( nickname [ [ "!" user ] "@" host ] )
		PREFIX = "(?:#{NICKNAME}(?:(?:!#{USER})?@#{HOST})?|#{SERVERNAME})"

		# nospcrlfcl =  %x01-09 / %x0B-0C / %x0E-1F / %x21-39 / %x3B-FF
		#                 ; any octet except NUL, CR, LF, " " and ":"
		NOSPCRLFCL = '\x01-\x09\x0B-\x0C\x0E-\x1F\x21-\x39\x3B-\xFF'

		# command    =  1*letter / 3digit
		COMMAND = "(?:[#{LETTER}]+|[#{DIGIT}]{3})"

		# SPACE      =  %x20        ; space character
		# middle     =  nospcrlfcl *( ":" / nospcrlfcl )
		# trailing   =  *( ":" / " " / nospcrlfcl )
		# params     =  *14( SPACE middle ) [ SPACE ":" trailing ]
		#            =/ 14( SPACE middle ) [ SPACE [ ":" ] trailing ]
		MIDDLE = "[#{NOSPCRLFCL}][:#{NOSPCRLFCL}]*"
		TRAILING = "[: #{NOSPCRLFCL}]*"
		PARAMS = "(?:((?: #{MIDDLE}){0,14})(?: :(#{TRAILING}))?|((?: #{MIDDLE}){14})(?::?)?(#{TRAILING}))"

		# crlf       =  %x0D %x0A   ; "carriage return" "linefeed"
		# message    =  [ ":" prefix SPACE ] command [ params ] crlf
		CRLF = '\x0D\x0A'
		MESSAGE = "(?::(#{PREFIX}) )?(#{COMMAND})#{PARAMS}#{CRLF}"

		CLIENT_PATTERN  = /\A#{NICKNAME}(?:(?:!#{USER})?@#{HOST})\z/on
		MESSAGE_PATTERN = /\A#{MESSAGE}\z/on
	end # PATTERN

	module Constants
		RPL_WELCOME           = '001'
		RPL_YOURHOST          = '002'
		RPL_CREATED           = '003'
		RPL_MYINFO            = '004'
		RPL_BOUNCE            = '005'
		RPL_USERHOST          = '302'
		RPL_ISON              = '303'
		RPL_AWAY              = '301'
		RPL_UNAWAY            = '305'
		RPL_NOWAWAY           = '306'
		RPL_WHOISUSER         = '311'
		RPL_WHOISSERVER       = '312'
		RPL_WHOISOPERATOR     = '313'
		RPL_WHOISIDLE         = '317'
		RPL_ENDOFWHOIS        = '318'
		RPL_WHOISCHANNELS     = '319'
		RPL_WHOWASUSER        = '314'
		RPL_ENDOFWHOWAS       = '369'
		RPL_LISTSTART         = '321'
		RPL_LIST              = '322'
		RPL_LISTEND           = '323'
		RPL_UNIQOPIS          = '325'
		RPL_CHANNELMODEIS     = '324'
		RPL_NOTOPIC           = '331'
		RPL_TOPIC             = '332'
		RPL_INVITING          = '341'
		RPL_SUMMONING         = '342'
		RPL_INVITELIST        = '346'
		RPL_ENDOFINVITELIST   = '347'
		RPL_EXCEPTLIST        = '348'
		RPL_ENDOFEXCEPTLIST   = '349'
		RPL_VERSION           = '351'
		RPL_WHOREPLY          = '352'
		RPL_ENDOFWHO          = '315'
		RPL_NAMREPLY          = '353'
		RPL_ENDOFNAMES        = '366'
		RPL_LINKS             = '364'
		RPL_ENDOFLINKS        = '365'
		RPL_BANLIST           = '367'
		RPL_ENDOFBANLIST      = '368'
		RPL_INFO              = '371'
		RPL_ENDOFINFO         = '374'
		RPL_MOTDSTART         = '375'
		RPL_MOTD              = '372'
		RPL_ENDOFMOTD         = '376'
		RPL_YOUREOPER         = '381'
		RPL_REHASHING         = '382'
		RPL_YOURESERVICE      = '383'
		RPL_TIM               = '391'
		RPL_                  = '392'
		RPL_USERS             = '393'
		RPL_ENDOFUSERS        = '394'
		RPL_NOUSERS           = '395'
		RPL_TRACELINK         = '200'
		RPL_TRACECONNECTING   = '201'
		RPL_TRACEHANDSHAKE    = '202'
		RPL_TRACEUNKNOWN      = '203'
		RPL_TRACEOPERATOR     = '204'
		RPL_TRACEUSER         = '205'
		RPL_TRACESERVER       = '206'
		RPL_TRACESERVICE      = '207'
		RPL_TRACENEWTYPE      = '208'
		RPL_TRACECLASS        = '209'
		RPL_TRACERECONNECT    = '210'
		RPL_TRACELOG          = '261'
		RPL_TRACEEND          = '262'
		RPL_STATSLINKINFO     = '211'
		RPL_STATSCOMMANDS     = '212'
		RPL_ENDOFSTATS        = '219'
		RPL_STATSUPTIME       = '242'
		RPL_STATSOLINE        = '243'
		RPL_UMODEIS           = '221'
		RPL_SERVLIST          = '234'
		RPL_SERVLISTEND       = '235'
		RPL_LUSERCLIENT       = '251'
		RPL_LUSEROP           = '252'
		RPL_LUSERUNKNOWN      = '253'
		RPL_LUSERCHANNELS     = '254'
		RPL_LUSERME           = '255'
		RPL_ADMINME           = '256'
		RPL_ADMINLOC1         = '257'
		RPL_ADMINLOC2         = '258'
		RPL_ADMINEMAIL        = '259'
		RPL_TRYAGAIN          = '263'
		ERR_NOSUCHNICK        = '401'
		ERR_NOSUCHSERVER      = '402'
		ERR_NOSUCHCHANNEL     = '403'
		ERR_CANNOTSENDTOCHAN  = '404'
		ERR_TOOMANYCHANNELS   = '405'
		ERR_WASNOSUCHNICK     = '406'
		ERR_TOOMANYTARGETS    = '407'
		ERR_NOSUCHSERVICE     = '408'
		ERR_NOORIGIN          = '409'
		ERR_NORECIPIENT       = '411'
		ERR_NOTEXTTOSEND      = '412'
		ERR_NOTOPLEVEL        = '413'
		ERR_WILDTOPLEVEL      = '414'
		ERR_BADMASK           = '415'
		ERR_UNKNOWNCOMMAND    = '421'
		ERR_NOMOTD            = '422'
		ERR_NOADMININFO       = '423'
		ERR_FILEERROR         = '424'
		ERR_NONICKNAMEGIVEN   = '431'
		ERR_ERRONEUSNICKNAME  = '432'
		ERR_NICKNAMEINUSE     = '433'
		ERR_NICKCOLLISION     = '436'
		ERR_UNAVAILRESOURCE   = '437'
		ERR_USERNOTINCHANNEL  = '441'
		ERR_NOTONCHANNEL      = '442'
		ERR_USERONCHANNEL     = '443'
		ERR_NOLOGIN           = '444'
		ERR_SUMMONDISABLED    = '445'
		ERR_USERSDISABLED     = '446'
		ERR_NOTREGISTERED     = '451'
		ERR_NEEDMOREPARAMS    = '461'
		ERR_ALREADYREGISTRED  = '462'
		ERR_NOPERMFORHOST     = '463'
		ERR_PASSWDMISMATCH    = '464'
		ERR_YOUREBANNEDCREEP  = '465'
		ERR_YOUWILLBEBANNED   = '466'
		ERR_KEYSE             = '467'
		ERR_CHANNELISFULL     = '471'
		ERR_UNKNOWNMODE       = '472'
		ERR_INVITEONLYCHAN    = '473'
		ERR_BANNEDFROMCHAN    = '474'
		ERR_BADCHANNELKEY     = '475'
		ERR_BADCHANMASK       = '476'
		ERR_NOCHANMODES       = '477'
		ERR_BANLISTFULL       = '478'
		ERR_NOPRIVILEGES      = '481'
		ERR_CHANOPRIVSNEEDED  = '482'
		ERR_CANTKILLSERVER    = '483'
		ERR_RESTRICTED        = '484'
		ERR_UNIQOPPRIVSNEEDED = '485'
		ERR_NOOPERHOST        = '491'
		ERR_UMODEUNKNOWNFLAG  = '501'
		ERR_USERSDONTMATCH    = '502'
		RPL_SERVICEINFO       = '231'
		RPL_ENDOFSERVICES     = '232'
		RPL_SERVICE           = '233'
		RPL_NONE              = '300'
		RPL_WHOISCHANOP       = '316'
		RPL_KILLDONE          = '361'
		RPL_CLOSING           = '362'
		RPL_CLOSEEND          = '363'
		RPL_INFOSTART         = '373'
		RPL_MYPORTIS          = '384'
		RPL_STATSCLINE        = '213'
		RPL_STATSNLINE        = '214'
		RPL_STATSILINE        = '215'
		RPL_STATSKLINE        = '216'
		RPL_STATSQLINE        = '217'
		RPL_STATSYLINE        = '218'
		RPL_STATSVLINE        = '240'
		RPL_STATSLLINE        = '241'
		RPL_STATSHLINE        = '244'
		RPL_STATSSLINE        = '244'
		RPL_STATSPING         = '246'
		RPL_STATSBLINE        = '247'
		RPL_STATSDLINE        = '250'
		ERR_NOSERVICEHOST     = '492'

		PASS     = 'PASS'
		NICK     = 'NICK'
		USER     = 'USER'
		OPER     = 'OPER'
		MODE     = 'MODE'
		SERVICE  = 'SERVICE'
		QUIT     = 'QUIT'
		SQUIT    = 'SQUIT'
		JOIN     = 'JOIN'
		PART     = 'PART'
		TOPIC    = 'TOPIC'
		NAMES    = 'NAMES'
		LIST     = 'LIST'
		INVITE   = 'INVITE'
		KICK     = 'KICK'
		PRIVMSG  = 'PRIVMSG'
		NOTICE   = 'NOTICE'
		MOTD     = 'MOTD'
		LUSERS   = 'LUSERS'
		VERSION  = 'VERSION'
		STATS    = 'STATS'
		LINKS    = 'LINKS'
		TIME     = 'TIME'
		CONNECT  = 'CONNECT'
		TRACE    = 'TRACE'
		ADMIN    = 'ADMIN'
		INFO     = 'INFO'
		SERVLIST = 'SERVLIST'
		SQUERY   = 'SQUERY'
		WHO      = 'WHO'
		WHOIS    = 'WHOIS'
		WHOWAS   = 'WHOWAS'
		KILL     = 'KILL'
		PING     = 'PING'
		PONG     = 'PONG'
		ERROR    = 'ERROR'
		AWAY     = 'AWAY'
		REHASH   = 'REHASH'
		DIE      = 'DIE'
		RESTART  = 'RESTART'
		SUMMON   = 'SUMMON'
		USERS    = 'USERS'
		WALLOPS  = 'WALLOPS'
		USERHOST = 'USERHOST'
		ISON     = 'ISON'
	end

	COMMANDS = Constants.constants.inject({}) {|r,i|
		r[Constants.const_get(i)] = i
		r
	}

	class Prefix < String
		def nick
			_match[1]
		end
		
		def user
			_match[2]
		end
		
		def host
			_match[3]
		end
		
		private
		def _match
			self[/^([^\s!]+)!([^\s@]+)@(\S+)$/]
		end
	end
end

class Net::IRC::Message
	include Net::IRC

	class InvalidMessage < Net::IRC::IRCException; end


	attr_reader :prefix, :command, :params

	def self.parse(str)
		_, prefix, command, *rest = *PATTERN::MESSAGE_PATTERN.match(str)
		raise InvalidMessage, "Invalid message: #{str.dump}" unless _

		case
		when rest[0] && !rest[0].empty?
			middle, trailer, = *rest
		when rest[2] && !rest[2].empty?
			middle, trailer, = *rest[2, 2]
		when rest[1]
			params  = []
			trailer = rest[1]
		when rest[3]
			params  = []
			trailer = rest[3]
		else
			params  = []
		end

		params ||= middle.split(/ /)[1..-1]
		params << trailer if trailer

		new(prefix, command, params)
	end

	def initialize(prefix, command, params)
		@prefix  = prefix
		@command = command
		@params  = params
	end

	def [](n)
		@params[n]
	end

	def each(&block)
		@params.each(&block)
	end

	def to_s
		str = ""
		if @prefix
			str << ":#{@prefix} "
		end

		str << @command

		if @params
			f = false
			@params.each do |param|
				str << " "
				if !f && (param.size == 0 || / / =~ param || /^:/ =~ param)
					str << ":#{param}"
					f = true
				else
					str << param
				end
			end
		end

		str << "\x0D\x0A"

		str
	end

	def inspect
		'#<%s:0x%x prefix:%s command:%s params:%s>' % [
			self.class,
			self.object_id,
			@prefix,
			@command,
			@params.inspect
		]
	end

end # Message

class Net::IRC::Client
	include Net::IRC
	include Constants

	def initialize(host, port, opts={})
		@host = host
		@port = port
		@opts = OpenStruct.new(opts)
		@log  = Logger.new(@opts.out || $stdout)
	end

	def start
		@socket = TCPSocket.open(@host, @port)
		request PASS,  @opts.pass if @opts.pass
		request NICK,  @opts.nick
		request USER,  @opts.user, "0", "*", @opts.real
		request WHOIS, @opts.nick
		while l = @socket.gets
			begin
				m = Message.parse(l)
				@log.debug m.inspect
				next if on_message(m) === true
				name = "on_#{(COMMANDS[m.command.upcase] || m.command).downcase}"
				send(name, m) if respond_to?(name)
			rescue Message::InvalidMessage
				@log.error "MessageParse: " + l.inspect
			end
		end
	ensure
		finish
	end

	def finish
		@socket.close
	end

	def on_rpl_whoisuser(m)
		@prefix = Prefix.new("#{m[1]}!#{m[2]}@#{m[3]}") if m[1] == @opts.nick
	end

	def on_message(m)
	end

	private
	def request(command, *params)
		@socket << Message.new(@prefix, command, params)
	end
end # Client

class Net::IRC::Server
	def initialize(host, port, session_class, opts={})
		@host          = host
		@port          = port
		@session_class = session_class
		@opts          = OpenStruct.new(opts)
		@sessions      = []
	end

	def start
		@serv = TCPServer.new(@host, @port)
		@log = Logger.new(@opts.out || $stdout)
		@log.info "Host: #{@host} Port:#{@port}"
		@accept = Thread.start do
			loop do
				Thread.start(@serv.accept) do |s|
					begin
						@sessions << s
						@log.info "Client connected, new session starting..."
						s = @session_class.new(self, s, @log)
						@sessions << s
						s.start
					rescue Exception => e
						puts e
						puts e.backtrace
					ensure
						@sessions.delete(s)
					end
				end
			end
		end
		@accept.join
	end

	def finish
		Thread.exclusive do
			@accept.kill
			@serv.close
			@sessions.each do |s|
				s.close
			end
		end
	end


	class Session
		include Net::IRC
		include Constants

		Version                = "0.0.0"
		NAME                   = "Net::IRC::Server::Session"
		AVAIABLE_USER_MODES    = "eixwy"
		AVAIABLE_CHANNEL_MODES = "spknm"

		def initialize(server, socket, logger)
			@server, @socket, @log = server, socket, logger
		end

		def self.start(*args)
			new(*args).start
		end

		def start
			on_connect
			while l = @socket.gets
				begin
					m = Message.parse(l)
					@log.debug m.inspect
					next if on_message(m) === true
					if m.command == QUIT
						on_quit if respond_to?(:on_quit)
						break
					else
						name = "on_#{(COMMANDS[m.command.upcase] || m.command).downcase}"
						send(name, m) if respond_to?(name)
					end
				rescue Message::InvalidMessage
					@log.error "MessageParse: " + l.inspect
				end
			end
		ensure
			finish
		end

		def finish
			@socket.close
		end

		def on_pass(m)
			@pass = m.params[0]
		end

		def on_nick(m)
			@nick = m.params[0]
		end

		def on_user(m)
			@login, @real = m.params[0], m.params[3]
			@host = @socket.peeraddr[2]
			@mask = Prefix.new("#{@nick}!#{@login}@#{@host}")
			@real, *@opts = @real.split(/\s/)
			inital_message
		end

		def on_connect
		end

		def on_quit
		end

		def on_message(m)
		end

		private
		def response(prefix, command, *params)
			@socket << Message.new(prefix, command, params)
		end

		def inital_message
			response NAME, RPL_WELCOME,  "Welcome to the Internet Relay Network #{@mask}"
			response NAME, RPL_YOURHOST, "Your host is #{NAME}, running version #{Version}"
			response NAME, RPL_CREATED,  "This server was created #{Time.now}"
			response NAME, RPL_MYINFO,   "#{NAME} #{Version} #{AVAIABLE_USER_MODES} #{AVAIABLE_CHANNEL_MODES}"
		end
	end
end # Server

__END__

Thread.start do
	Net::IRC::Server.new("localhost", 16669, Net::IRC::Server::Session).start
end

Net::IRC::Client.new("localhost", "16669", {
	:nick => "chokan",
	:user => "chokan",
	:real => "chokan",
}).start

__END__

Net::IRC::Client.new("charlotte", "6669", {
	:nick => "chokan",
	:user => "chokan",
	:real => "chokan",
}).start

__END__
class SimpleClient < Net::IRC::Client
	def on_privmsg
		request(PRIVMSG, channel, "aaa")
	end
end

class LingrIrcGateway < Net::IRC::Server::Session
	def on_user
		response(NAME, RPL_WELCOME,  "Welcome to the Internet Relay Network #{@mask}")
		response(NAME, RPL_YOURHOST, "Your host is #{NAME}, running version #{Version}")
		response(NAME, RPL_CREATED,  "This server was created #{Time.now}")
		response(NAME, RPL_MYINFO,   "#{NAME} `Tynoq` v#{Version}")
	end

	def on_privmsg
	end
end

Net::IRC::Server.new("localhost", 16669, LingrIrcGateway).start

