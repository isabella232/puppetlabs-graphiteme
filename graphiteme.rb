#!/usr/bin/env ruby
# 

defaults = { :port => 2003, :graphite => 'graphite.dc1.puppetlabs.net', :source => nil , :file => 'graphiteme.yaml' }

# Code below, stay away...
require 'rubygems'
require 'simple-graphite'
require 'trollop'
require 'yaml'
require 'socket'
require 'erb'


class Graphite
  attr_accessor :host, :port, :time, :source

  def initialize(options = {})
    @host = options[:host]
    @port = options[:port] || 2003
    @source = options[:source] || nil
    @time = Time.now.to_i
  end

  def push_to_graphite
    raise "You need to provide both the hostname and the port" if @host.nil? || @port.nil?
    socket = TCPSocket.new(@host, @port, @source )
    yield socket
    socket.close
  end
end

class TCPSocket
  def pee( metric , value )
    self.puts "#{metric} #{value} #{Time.now.to_i}"
  end
end

def graphitemagic( graphite , command, regex , metric )

  unless regex.class == Regexp
    regex = Regexp.new regex
  end

  IO.popen( "#{command} 2>/dev/null </dev/null" , 'r' ) do |pfinfo|
    pfinfo.each do |line|
      if line =~ regex
        graphite.push_to_graphite { |gg| gg.pee( metric , $1 ) }
      end
    end
  end

end

def make_my_stats( graphiteobject , things )

  # Little inefficient doing this each time, but it needs to be available
  # to the ERB here.
  hostname = Socket.gethostname.split( '.' ).first

  things.each do |thing|
    thing[:pairs].each do |pair|
      pair.each do |metric,regex|
        graphitemagic( graphiteobject , thing[:cmd] , regex , ERB.new( metric ).result(binding) )
      end
    end
  end
end

def read_config( file )

  make_me_stats_on_these = nil

  if File.exists? file and File.readable? file
    begin
      make_me_stats_on_these = YAML.load_file( file )
    rescue => e
      $stderr.puts "Unable to read #{file}, due to #{e}"
      exit 10
    end
  else
    puts "Unable to load the YAML file #{file}"
    exit 5
  end

  if make_me_stats_on_these.nil?
    puts "Empty config file."
    exit 6
  end

  make_me_stats_on_these
end



opts = Trollop::options do
  opt :source, "Source IP address", :short => 's', :type => :string
  opt :graphite, "IP/hostname for graphite", :short => 'g', :type => :string
  opt :port, "Port for graphite", :short => 'p', :type => :integer
  opt :daemon, "Run in a loop, every N seconds", :short => 'd', :type => :integer
end
opts.each { |k,v| opts.delete k if v.nil? }
opts = defaults.merge( opts )


make_me_stats_on_these = read_config( opts[:file] )

g = Graphite.new
g.host = opts[:graphite]
g.port = opts[:port]
g.source = opts[:source]


if opts[:daemon_given]
  while 1
    make_my_stats( g , make_me_stats_on_these )
    sleep opts[:daemon]
  end
else
  make_my_stats( g , make_me_stats_on_these )
end
