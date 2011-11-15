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

#Index path should show all the keys and 
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


def target_key(target_id)
  "target_#{target_id}"
end
#to allow set to add target data in to the system 
post '/targets/' do 
  target_id   = params[:target_id]
  target_info = params[:target_info]
  unless target_id && target_info
    return [406, "invalid target info"]
  end
  
  RedisConnection.set target_key(target_id), target_info
  return [201, "upadted target"]
end

post '/current_target' do 
  unless params[:id]
    return [406, "include a target id"]
  end
  target_id = params[:id]
  unless RedisConnection.key target_key(target_id)
    return [406, "target not found in system. Please specify target by posting to /targets/ first"]
  end
  RedisConnection.set "current_target", target_id 
end

get '/current_target' do 
  current_target_id = RedisConnection.get "current_target"
  return [404, "current target not set"] unless current_target_id 
  target_info = RedisConnection.get target_key(current_target_id)
  return [404, "current target #{current_target_id} set but no data in system for it"]
  target_info
end

get '/targets/' do 
  if params[:id]
    return RedisConnection.get target_key(params[:id])
  else
    return RedisConnection.keys target_key("*")
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
   return [406, "problem params are #{params}"]
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
