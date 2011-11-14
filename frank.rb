require 'sinatra'
require 'redis'
require 'yaml'
require 'erb'
require 'json'


config = YAML.load_file('redis.yml')
puts "enviroment is #{ENV['RACK_ENV']}"

config = config['production'].inject({}){|r,a| r[a[0].to_sym]=a[1]; r}
RedisConnection =Redis.new( config  )

redis_key_prefix= "subject_new_"
subject_life = 93*3

get  '/' do 
  @keys   = RedisConnection.keys("#{redis_key_prefix}*").collect{|k| "#{k} : #{RedisConnection.ttl k} "}
  @status = RedisConnection.get "current_status"
  @pending_followups = RedisConnection.get "follow_ups"
  erb :index
end

post '/observations/' do
  if params[:observation_id] 
    RedisConnection.set "current_target", params[:observation_id]
    return [201,"updated observation id"]
  else
    return [406,"submit a current observation id"]
  end
end

post '/sources/' do
  if params[:source] 
    RedisConnection.set "current_source", params[:source]
    return [201,"updated source"]
  else
    return [406,"submit a current source"]
  end
end

get '/followup' do
  @pending_followups = RedisConnection.get("follow_ups")
  @pending_followups.to_json
end

post '/status' do
  allowed_states = ["active", "inactive"]
  if allowed_states.include? params[:status]
    RedisConnection.set "current_status", params[:status]
    return 201
  else 
    return [406,"status type not recognised"]
  end  
end

get '/status' do
  RedisConnection.get "current_status"
end


get '/keys' do
  RedisConnection.keys("#{redis_key_prefix}*").inject({}){|r,k| r[k]={:ttl=>RedisConnection.ttl(k)}; r }.to_json
end

post '/subjects/' do 
  unless params[:file] &&
        (tmpfile = params[:file][:tempfile]) &&
        (name = params[:file][:filename]) &&
        (activity_id = params[:subject][:activity_id]) &&
        (source_id   = params[:subject][:source_id]) &&
        (observation_id = params[:subject][:observation_id])
        
   @error = "No file selected"
   return [406, "problem"]
 end
 STDOUT.puts "Uploading file, original name #{name.inspect}"
 file=''
 
 while blk = tmpfile.read(65536)
   file << blk
 end
 RedisConnection.set "#{redis_key_prefix}#{source_id}_#{observation_id}_#{activity_id}", file
 RedisConnection.expire "#{redis_key_prefix}#{source_id}_#{observation_id}_#{activity_id}", subject_life
 return [201, "created succesfully"]
end
