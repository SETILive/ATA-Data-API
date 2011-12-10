require File.join(File.dirname(__FILE__), '..', 'frank.rb')

require 'rubygems'
require 'sinatra'
require 'redis'
require 'rspec'
require 'rack/test'

# set test environment
set :environment, :test
set :run, false
set :raise_errors, true
set :logging, false

config = YAML.load_file('config/redis.yml')
puts "enviroment is #{ENV['RACK_ENV']}"

config = config['development'].inject({}){|r,a| r[a[0].to_sym]=a[1]; r}
RedisConnection =Redis.new( config  )

RSpec.configure do |conf|
  conf.include Rack::Test::Methods
end

def app
  Sinatra::Application
end

module FrankHelperMethods
  before do
    RedisConnection.del "*"
  end
  
  def set_status 
      RedisConnection.set('')
  end

  def example_target
    {:target=>{:ra=>rand()*10, :dec=>rand*20, :name=>"crab"}}
  end

  def get_current_target 
    RedisConnection.get("current_target")
  end

  def set_current_target(target_id) 
    RedisConnection.set("current_target", target_id)
  end

  def set_up_example_target(target_id, target=nil)
    target ||= example_target
    RedisConnection.set(target_key(target_id), target)
    target
  end
end

