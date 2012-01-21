require 'sinatra'
require 'redis'
require 'yaml'
require 'erb'
require 'json'
require 'pusher'

require 'pusher'

Pusher.app_id = '***REMOVED***'
Pusher.key = '***REMOVED***'
Pusher.secret = '***REMOVED***'


redis_config = YAML.load_file('config/redis.yml')
redis_config = redis_config['production'].inject({}){|r,a| r[a[0].to_sym]=a[1]; r}

RedisConnection =Redis.new( redis_config  )



# config = JSON.parse(IO.read("config.json"))

redis_key_prefix= "subject_new_"
subject_life = 93*3

#Index path should show all the keys and 
get  '/' do 
  @keys   = RedisConnection.keys("#{redis_key_prefix}*").collect{|k| "#{k} : #{RedisConnection.ttl k} "}
  @status = RedisConnection.get "current_status"
  @pending_followups = RedisConnection.get "follow_ups"
  erb :index
end

#Targets

def target_key(target_id)
  "target_#{target_id}"
end

post '/targets/:id' do |target_id|
  target_info = params[:target]
  
  unless target_id && target_info
    return [406, "invalid target info"]
  end
  
  RedisConnection.set target_key(target_id), target_info.to_json
  return [201, "upadted target"]
end

get '/targets' do 
  RedisConnection.keys(target_key("*")).collect{|key| RedisConnection.get(key)}.to_json
end

get '/targets/:id' do |target_id| 
  if target_id
    return RedisConnection.get target_key(target_id)
  else
    return [404, "no target with that id"]
  end
end

get '/current_target' do 
  current_target_id = RedisConnection.get "current_target"
  return [404, "current target not set"] unless current_target_id 
  target_info = RedisConnection.get target_key(current_target_id)
  return [404, "current target #{current_target_id} set but no data in system for it"]
  
  return {:target_id=> current_target_id, :target_info=>target_info}.to_json
end

post '/current_target/:target_id' do |target_id| 
  unless target_id
    return [406, "include a target id"]
  end

  unless RedisConnection.get target_key(target_id)
    return [406, "target not found in system. Please specify target by posting to /targets/ first"]
  end

  RedisConnection.set "current_target", target_id 
end


#follow_up_list These are set by MARV  
get '/followup' do
  pending_followups = RedisConnection.get("follow_up_*")
  pending_followups.to_json
end

#Getting and setting status 

get '/status' do
  return RedisConnection.get "current_status"
end

post '/status/:status' do |status|
  allowed_states = ["active", "inactive"]
  if allowed_states.include? status
    RedisConnection.set "current_status", status
    Pusher['telescope'].trigger('status Changed', status)
    return 201
  else 
    return [406,"status type not recognised"]
  end  
end

#Subjects

get '/subjects/:activity_id' do |activity_id|
  subject = RedisConnection.get("#{redis_key_prefix}_#{activity_id}")
  if subject 
    return subject.to_json
  else 
    return [404, 'subject with id #{subject_id} does not exist']
  end
end

get '/subjects' do
  RedisConnection.keys("#{redis_key_prefix}*").inject({}){|r,k| r[k]={:ttl=>RedisConnection.ttl(k)}; r }.to_json
end

post '/subjects/' do 
  puts params 
  unless params[:file] &&
        (tmpfile = params[:file][:tempfile]) &&
        (name = params[:file][:filename]) &&
        (activity_id = params[:activity_id]) &&
        (observation_id = params[:observation_id])
  
   @error = "No file selected"
   return [406, "problem params are #{params}"]
 end
 
 STDOUT.puts "Uploading file, original name #{name.inspect}"
 file=''
 
 while blk = tmpfile.read(65536)
   file << blk
 end
 RedisConnection.set "#{redis_key_prefix}_#{activity_id}", file
 RedisConnection.expire "#{redis_key_prefix}_#{activity_id}", subject_life
 return [201, "created succesfully"]
end
