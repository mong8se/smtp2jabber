#!/usr/bin/env ruby
require 'rubygems'
require 'eventmachine'
require 'xmpp4r-simple'

# Default pid file goes in same directory as this script,
# with the extension swapped out for .pid
PIDFILE = __FILE__.reverse.split('.', 2).last.reverse + '.pid'
PORT = 25025

class Smtp2Jabber < EM::Protocols::SmtpServer
    @@jabbers = {}

    # NOTE: the craziest bit is that whatever username/password
    # are sent as authentication to the smtp server, are what is
    # used to log into jabber. So there isn't any authentication
    # on the smtp server--only have it listen on localhost!
    def receive_plain_auth(user, password)
        @@jabbers[user] ||= Jabber::Simple.new(user, password)
        @from = user

        return @@jabbers[user].connected?
    end

    # Who the email is addressed to is the Jabber recipient
    # but strip the < >
    def receive_recipient(address)
        if m = address.match(/<([^>]+)>/)
            @rcpt_to = m[1]
            return true
        else
            @rcpt_to = nil
            return false
        end
    end

    # Get set up to recieve mail
    def receive_data_command
        @headers_finished = nil
        @body = []
        @headers = {}

        return true
    end

    # process each line
    def receive_data_chunk( data )
        data.each do |line|
            if @headers_finished
                @body << line
            elsif line.empty? && @headers_finished.nil?
                @headers_finished = true
            else
                name, value = line.split(': ', 2)
                @headers[name] = value
            end
        end

        return true
    end

    # we have full message, send the jabber im
    # sends subject, blank line, body, then ––
    def receive_message
        im @headers['Subject'], "\n\n", @body.join("\n"), "\n––\n"

        return true
    end

    # I had some code here to check the connection and reconnect
    # if necessary, but looking at the code for xmpp4r-simple, it
    # looks like that's already done for us.
    def im(*messages)
        @@jabbers[@from].deliver @rcpt_to || @headers[:To], messages.join
    end
end

# Eventmachine A Go Go
EM.run do
    begin
        File.open(PIDFILE, 'w') do |pidfile|
            pidfile.puts(Process.pid.to_s)
        end
    rescue Errno::EACCES
        puts 'Cannot create PID file--check permissions.'
        exit!
    end

    EM.start_server( '127.0.0.1', PORT, Smtp2Jabber )
end
