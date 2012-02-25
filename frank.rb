require 'sinatra'
require 'redis'
require 'yaml'
require 'erb'
require 'json'
require 'pusher'


Pusher.app_id = '***REMOVED***'
Pusher.key = '***REMOVED***'
Pusher.secret ='***REMOVED***'


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
  @current_targets = RedisConnection.get("current_target")
  @errors = RedisConnection.get "error_key"
  erb :index
end


get '/listener' do 
  erb :listener
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

  RedisConnection.lpush 'log', {:type=>'targets_post', :date=>Time.now, :data=> params[:target]}.to_json

  RedisConnection.set target_key(target_id), target_info.to_json
  return [201, "upadted target"]
end

get '/targets' do  
  results =[]
  keys = RedisConnection.keys(target_key("*"))

  RedisConnection.mget(*keys).each_with_index do |data,index|
    begin 
      results<<  JSON.parse(data).merge({:target_id=> keys[index].gsub("target_","")})
    rescue 
      puts "failed to parse #{keys[index]}"
    end
  end
  return [200, results.to_json ]
end

get '/targets/:id' do |target_id| 
  if target_id
    return RedisConnection.get target_key(target_id)
  else
    return [404, "no target with that id"]
  end
end

get '/testPush' do
  push('telescope', 'status_test', '')
  return [200, 'ok']
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

  beamNo = params['target']['beam_no']


  unless RedisConnection.get("current_target_#{beamNo}") == target_id
    RedisConnection.lpush 'log', {:type=>'current_target_post', :date=>Time.now, :data=> params}.to_json
    RedisConnection.set "current_target_#{beamNo}", target_id 
    push('telescope', 'target_changed' , params.to_json)
  end

end


#follow_up_list These are set by MARV  
get '/followup' do


  followups= [ {followup_id: 1,
                 activity_id: 1,
                 target_id: 1000, 
                 beam_no: 1,
                 pol: 0, 
                 frequencies: [
                  {start_freq: 1420.0, drift: 3.2, type: 'cw', shape: 'straight'}, 
                  {start_freq: 1420.3, drift: 1.2, type: 'pulse', shape: 'diagional'}
                ]},
                {followup_id: 2,
                 activity_id: 1,
                 target_id: 1001,
                 beam_no: 1,
                 pol: 0, 
                 frequencies:[
                  {start_freq: 14230.0, drift: 3.2, type: 'pulse', shape: 'spiral'}, 
                  {start_freq: 1220.3, drift: 1.2, type: 'pulse', shape: 'diagional'}
                ]}]

  followups.to_json
  # pending_followups = RedisConnection.get("follow_up_*")
  # pending_followups.to_json
end

post '/followup/:activity_id' do |activity_id|
  push('subjects', 'follow_up_triggered', activity_id )
end

#Getting and setting status 

get '/status' do
  return RedisConnection.get "current_status"
end

post '/status/:status_update' do |status|
  allowed_states = ["active", "inactive", "replay"]

  RedisConnection.lpush 'log', {:type=>'status_update', :date=>Time.now, :data=> {:status => status}}.to_json

  if allowed_states.include? status
    push("telescope", "status_changed", status)
    RedisConnection.set "current_status", status
    return 201
  else 
    return [406,"status type not recognised"]
  end  
end

#Subjects

get '/subjects/:activity_id' do |activity_id|
  subject = RedisConnection.get("#{redis_key_prefix}_#{observation_id}_#{activity_id}_#{obs}")
  if subject 
    return subject.to_json
  else 
    return [404, 'subject with id #{subject_id} does not exist']
  end
end

get '/subjects' do
  RedisConnection.keys("#{redis_key_prefix}*").inject({}){|r,k| r[k]={:ttl=>RedisConnection.ttl(k)}; r }.to_json
end

post '/subjects' do 
  unless params[:file] &&
    (tmpfile = params[:file][:tempfile]) &&
    (name = params[:file][:filename]) &&
    (activity_id = params[:subject][:activity_id]) &&
    (observation_id = params[:subject][:observation_id]) &&
    (pol = params[:subject][:pol])
    (sub_channel= subject[:subchannel] )
  

    RedisConnection.set("error_key", params.to_json)
    File.open("uploadErrors.log", "a") {|f| f.puts "having trouble params are #{params}"}

    @error = "No file selected"
    return [406, "problem params are #{params}"]
  end
 
  STDOUT.puts "Uploading file, original name #{name.inspect}"
  file=''
 
  while blk = tmpfile.read(65536)
     file << blk
  end

  RedisConnection.lpush 'log', {:type=>'subject_upload', :date=>Time.now, :data=> {:params => params, :file => file}}
 
  key = subject_key(observation_id, activity_id, pol,sub_channel )
  RedisConnection.set key, file
  RedisConnection.expire key, subject_life

  push("telescope","new_data", {:url => '/subjects/', :observation_id => observation_id, :activity_id=> activity_id, :polarization=> pol}.to_json)
  return [201, "created succesfully"]
end

def subject_key(observation_id, activity_id, pol,sub_channel)
  redis_key_prefix= "subject_new"

  "#{redis_key_prefix}_#{observation_id}_#{activity_id}_#{pol}_#{sub_channel}"
end

def push(chanel, message, data)
  begin
    Pusher[chanel].trigger(message, data)
  rescue 
    puts "could not push update #{chanel} #{message} #{data}"
  end
end