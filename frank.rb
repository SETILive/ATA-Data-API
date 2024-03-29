#Need to have RACK_ENV environment variable set to "development" or "test" to
#avoid "production" default.

require 'sinatra'
require 'redis'
require 'yaml'
require 'erb'
require 'json'
require 'pusher'
require 'bson'
require 'aws-sdk'
require 'uuid'
# require 'debugger' ; debugger

# Passwords for better-than-nothing security
seti_passwd = "SETI_PASSWORD"
marv_passwd = "MARV_PASSWORD"
zoo_username = "ZOONIVERSE_USERNAME"
zoo_passwd = "ZOONIVERSE_PASSWORD"

Pusher.app_id = '***REMOVED***'
Pusher.key = '***REMOVED***'
Pusher.secret ='***REMOVED***'

mode_str = 'production'
mode_str = 'development' if Sinatra::Base.development? 
mode_str = 'test' if Sinatra::Base.test? 

redis_config = YAML.load_file('config/redis.yml')
redis_config = redis_config[mode_str].inject({}){|r,a| r[a[0].to_sym]=a[1]; r}

puts redis_config

RedisConnection =Redis.new( redis_config  )

if Sinatra::Base.development?  
  marv_url = 'http://localhost:3000'
else # Sinatra::Base.production?  
  marv_url = 'http://www.setilive.org'
end

require 'oily_png' #'chunky_png'

# Set frank parameters to defaults if not defined in Redis
unless RedisConnection.get( 'frank_parms' )
  RedisConnection.set( 'frank_parms', 
    { t_accum: 93, # Waterfall data collection time
	    followup_deadline_time: 267, # Subject start time to followup request at SonATA
	    data_key_buffer: 30, # Observation data life extension to avoid races.
	    followup_lead_time: 15 # Lead time classification to followup request at SonATA
	  }.to_json )
end

if Sinatra::Base.development?
  # Configure for 
  # https://github.com/jubos/fake-s3 (Ruby)
  # or
  # https://github.com/jserver/mock-s3 (Python)
  # Haven't made either of these work yet.
  AWS.config :access_key_id=>'123', :secret_access_key => 'abc', 
    :use_ssl => false, :s3_port => 10001, :s3_endpoint => 'localhost'
else
  AWS.config :access_key_id=>'***REMOVED***', :secret_access_key => '***REMOVED***'
end

class PurgeTempFiles
  
    def perform
      puts 'purge task'
      if Sinatra::Base.development?
        bucket_home = ENV['HOME'] + '/' + 's3store'
        bucket_name = 'zooniverse-seti' 
        ['data/', 'images/', 'thumbs/'].each do |dir|
          purge = Dir.glob( bucket_home + '/' + bucket_name + '/' + dir + 'tmp_*')
          purge.each { |file| File.delete( file ) }
        end
      else
        s3 = AWS::S3.new
        bucket = s3.buckets['zooniverse-seti']
        ['data/', 'images/', 'thumbs/'].each do |dir|
          purge = bucket.objects.with_prefix( dir + 'tmp_observation_' )
          purge.each { |file| file.delete() }
        end
      end

    end
end

# Uploads a subject's data/images to S3 using temporary urls and puts the urls
# into redis for Marv to retrieve and construct the Subject and Observation
# object.
# Replaces data in observation key with data and image urls in json format.
class ObservationUploader

  @data = nil
  @subject = nil
  @file_root = nil
  # Gets subject data key from which observation data keys can be derived.
  def perform( subj_key )
    @subject = JSON.parse(RedisConnection.get( subj_key ) )
    beam_key_root = subj_key.sub("tmp_new", "tmp_data_new")
    keys = RedisConnection.keys( beam_key_root + "_?")
    
    keys.each do |key|
      @data = JSON.parse(RedisConnection.get(key))
      key_parse = key.split("_")
      @file_root = "tmp_observation_" + key_parse[0] + "_" + key_parse.last
      #log_entry("uploading data")
      @path_to_data = upload_file( "data/" + @file_root + ".jsonp", "observation(#{@data});" )
      @image_urls      = generate_images
      #log_entry("uploading images")
      urls = [@image_urls[:image], @image_urls[:thumb], @path_to_data]
      new_data_key = key.sub( "_tmp_", "_subject_")
      RedisConnection.setex(new_data_key, RedisConnection.ttl(key), urls.to_json )
      RedisConnection.del( key )

    end
    new_subj_key = subj_key.sub( "_tmp_", "_subject_" )
    RedisConnection.rename( subj_key, new_subj_key )
    RedisConnection.expire( new_subj_key, RedisConnection.ttl("subject_timer") )
  end

  def upload_file(name , data)
    if Sinatra::Base.development?
      #Kluge to avoid sending data to S3 in dev mode if live data is emulated.
      # Need folders already created in ~/s3store/zooniverse-seti/
      # images, thumbs, data
      # Run local HTTP file server in s3store on port 9914
      # (i.e. python -m SimpleHTTPServer 9914) 
      bucket_home = ENV['HOME'] + '/' + 's3store'
      bucket_name = 'zooniverse-seti'
      file_path = bucket_home + '/' + bucket_name + '/' + name
      object_file = File.open( file_path, 'w' )
      object_file.write( data )
      object_file.close
      "http://#{`hostname`.gsub("\n",'')}:9914/#{bucket_name}/#{name}"
    else
      s3 = AWS::S3.new
      bucket = s3.buckets['zooniverse-seti']
      object = bucket.objects[name]
      object.write( data, :acl=>:public_read )
      object.public_url.to_s
    end
  end

  def generate_images
    # Since data is provided in time sequence and image coordinates have
    # origin at top-left, images must be filled in reverse row order.
    # This is imaging version 2
    
    img_width  = 768 #758
    img_height = 384 #410

    thumb_image_width = 128
    thumb_image_height = 64

    data = @data
    main_image  = make_png(data, @observation, img_width,img_height)
    thumb_image = make_png(data, @observation, thumb_image_width,thumb_image_height)
    
    image_url = upload_file("images/#{@file_root}.png",main_image.to_s)
    thumb_url = upload_file("thumbs/#{@file_root}.png",thumb_image.to_s)
    {image: image_url, thumb: thumb_url}
  end 

  def make_png(data, observation, img_width,img_height)
    width  = @subject['width']
    height = @subject['height']
    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.grayscale(255))
    beam = data
    # SonATA delivers last row blank. Fill by repeating previous row
    (0..(height-2)).each do |ypos|
      row = beam[(ypos*width) .. ((ypos+1)*width-1)]
      row.each_with_index do |val, idx|
        val = 255 if val > 255
        val = 0 if val < 0
        row[idx] = ChunkyPNG::Color.grayscale(val)
      end
      png.replace_row!(height - 1 - ypos, row)
    end
    png.replace_row!(0, png.row(1)) # Last row fill
    png.resample_nearest_neighbor!(img_width,img_height)
  end

end
redis_key_prefix= "subject_new_"
redis_recent_prefix= "subject_recent_"

#Index path should show all the keys and 
get  '/' do 
  @keys   = RedisConnection.keys("*#{redis_key_prefix}*").collect{|k| "#{k} : #{RedisConnection.ttl k} "}
  @recent_subjects = RedisConnection.keys("*#{redis_recent_prefix}*").collect{|k| "#{k} : #{RedisConnection.ttl k} "}
  @data_keys = RedisConnection.keys("*subject_data_new*").collect{|k| "#{k} : #{RedisConnection.ttl k} "}
  @status = RedisConnection.get "current_status"
  @pending_followups = RedisConnection.get "follow_ups"
  @current_targets = RedisConnection.get("current_target")
  @errors = RedisConnection.get "error_key"
  @report = RedisConnection.get "report_key"
  @time_to_new_data = RedisConnection.get "time_to_new_data"
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

  # RedisConnection.lpush 'log', {:type=>'targets_post', :date=>Time.now, :data=> params[:target]}.to_json

  RedisConnection.set target_key(target_id), target_info.to_json
  return [201, "updated target"]
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
  
  if target_info
    return {:target_id=> current_target_id, :target_info=>target_info}.to_json
  else
    return [404, "current target #{current_target_id} set but no data in system for it"] unless target_info
  end
  
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
    # RedisConnection.lpush 'log', {:type=>'current_target_post', :date=>Time.now, :data=> params}.to_json
    RedisConnection.set "current_target_#{beamNo}", target_id 
    key = "target_#{target_id}"
    params['target']['name'] = JSON.parse(RedisConnection.get(key))["target_name"]
    push('telescope', 'target_changed' , params.to_json)
  end

end


#follow_up_list These are set by MARV  
get '/followup' do
  pending_followups = RedisConnection.keys("follow_up_*").collect{|key| JSON.parse(RedisConnection.get(key))}
  {followups: [pending_followups[0]]}.to_json
end

post '/followup/:activity_id' do |activity_id|
  push('subjects', 'follow_up_triggered', activity_id )
end

#Getting and setting status 
get '/status' do
  return RedisConnection.get "current_status"
end

post '/followup_time/:time_to_followup' do |followup_time|
  if RedisConnection.ttl("subject_timer") > 10
    RedisConnection.expire("subject_timer", followup_time.to_i)
    RedisConnection.keys("*_subject_*").each do |key|
      RedisConnection.expire(key, RedisConnection.ttl("subject_timer") )
    end
    push('telescope', "time_to_followup_update", 
      RedisConnection.ttl("subject_timer"))
    return 201 
  else
    return [424, "followup time expired"]
  end      
end

# Next or current schedule start, end times

post '/telescope_schedule_info' do
  return [ 406, "bad parameters" ] unless params[:password] == seti_passwd
  is_current_str = params[:current]
  start_str = params[:starttime]
  end_str = params[:endtime]
  if start_str && end_str && is_current_str 
    t_start = start_str.to_i
    t_end = end_str.to_i 
    is_current = is_current_str == 'true'
    t_start += 75 * 60000 if t_start > 0 # Estimated actual start
    if is_current
      t_change = RedisConnection.get("current_status") == 'active' ? t_end : t_start
    else
      t_change = t_start      
    end
    delta = (RedisConnection.get("next_status_change").to_f - t_change).to_f.abs
    
    # Check if the apparent extended inactive period indicated by the schedule
    # (which previously armed the status_change_inactive flag) has actually
    # happened and send the email notification.
    if RedisConnection.get("status_change_inactive")
      if RedisConnection.get("current_status") == 'inactive'
        RedisConnection.del("status_change_inactive")
        puts "trigger telescope email notification "
        url = URI.parse( marv_url + '/telescope_notify_users')
        args = {'passwd' => marv_passwd}
        req = Net::HTTP::Post.new url.path
        req.basic_auth zoo_username, zoo_passwd
        req.set_form_data args
        Net::HTTP.new(url.host, url.port).start {|http| http.request req }	
      end
    end
    # Look for a change greater than 1 minute and update site status display
    if ( delta > 60000.0 )
      push("telescope", "next_status_changed", t_change.to_s)
      RedisConnection.set "next_status_change", t_change.to_s
    end
    
    # Look for a change greater than 4 hours to a non-current schedule 
    # and arm the email notification flag, indicating an apparent extended
    # inactive period.
    if (delta > 4 * 3600 * 1000 ) && !is_current && t_change > 0
        RedisConnection.setex( "status_change_inactive", 10 * 60, "")
    end
  else
    return [406, "bad parameters"]
  end  
end

post '/operator_message' do
  
  # <time_string_in_seconds>_MSG_<:message> posted to Redis and Pusher.
  # Time string can be converted to local time with
  # Time.at(time_string_in_seconds.to_i).ctime
  # Message will be truncated to 51 characters.
  
  return [ 406, "bad parameters" ] unless params[:password] == seti_passwd

  message = params[:message] == "" ? 
    "The telescope is operating normally." :
    params[:message][0..50]
  op_data = Time.now.to_i.to_s + "_MSG_" + message
  RedisConnection.set( "last_operator_msg", op_data )
  push( 'telescope', 'operator_message', op_data )
  return 201
end

post '/numbeams' do
  return [ 406, "bad parameters" ] unless params[:info][:password] == seti_passwd
  beams = params[:info][:beams].to_i
  allowed_values = [1, 2, 3]
  if allowed_values.include?( beams )
    if ( temp = RedisConnection.get('live_classification_parms') )
      temp = JSON.parse( temp )
      temp['number_of_beams'] = beams
      RedisConnection.set( 'live_classification_parms', temp.to_json )
      return 201
    else
      return [202, 'server not yet configured to use this data']
    end
  else
    return [406, 'invalid beam count']
  end
end

post '/status/:status_update' do |status|
  allowed_states = ["active", "inactive", "replay"]

  # RedisConnection.lpush 'log', {:type=>'status_update', :date=>Time.now, :data=> {:status => status}}.to_json

  if allowed_states.include? status
    RedisConnection.set "current_status", status
    push("telescope", "status_changed", status)
    return 201
  else 
    return [406,"status type not recognised"]
  end  
end

#Subjects
get '/subjects/:activity_id' do |activity_id|
  subject = RedisConnection.get("*#{redis_key_prefix}_#{observation_id}_#{activity_id}_#{obs}")
  if subject 
    return subject.to_json
  else 
    return [404, 'subject with id #{subject_id} does not exist']
  end
end

get '/subjects' do
  RedisConnection.keys("*#{redis_key_prefix}*").inject({}){|r,k| r[k]={:ttl=>RedisConnection.ttl(k)}; r }.to_json
end

get '/recents' do
  RedisConnection.keys("*#{redis_recent_prefix}*").inject({}){|r,k| 
    r[k]={:ttl=>RedisConnection.ttl(k), 
          :priority=>RedisConnection.get(k)}; r }.to_json
end

get '/key/:key' do |key|
  "key is #{RedisConnection.get key }"
end

post '/offilne_subjects' do
  return [200, 'subject_accepted']
end

post '/subjects' do
  begin
    #log_entry( "\n/subjects")
    parms = JSON.parse( RedisConnection.get('frank_parms') )
    RedisConnection.set "report_key" , params.to_json
    puts "activity id ", params[:subject][:activity_id]
    puts "observation id ", params[:subject][:observation_id]
    puts "pol ", params[:subject][:pol]
    puts "subchannel", params[:subject][:subchannel] 
    unless params[:file] &&
      (tmpfile = params[:file][:tempfile]) &&
      (name = params[:file][:filename]) &&
      (activity_id = params[:subject][:activity_id]) &&
      (observation_id = params[:subject][:observation_id]) &&
      (pol = params[:subject][:pol]) &&
      (sub_channel = params[:subject][:subchannel] )


      RedisConnection.set("error_key", params.to_json)
      File.open("uploadErrors.log", "a") {|f| f.puts "having trouble params are #{params}"}

      @error = "No file selected"
      return [406, "problem params are #{params}"]
    end

    # See if the Renderer is sending a rendering version number, set to version
    # 1 if not.
    rendering = params[:subject][:rendering]
    rendering = "1" unless rendering 
       
    # Purge old files on first new activity data received
    PurgeTempFiles.new.perform() unless RedisConnection.get("subject_timer")
    
    # Temporary identifier for temporary redis keys and image/data filenames. 
    # Marv will create proper database entries and modify urls when subject 
    # is served. 
    uuid = UUID.new.generate

    STDOUT.puts "Uploading file, original name #{name.inspect}"
    file=''

    while blk = tmpfile.read(65536)
      file << blk
    end
    file = BSON.deserialize(file)
    
    # Set subject timer for followup deadline if first activity data
    unless RedisConnection.get("subject_timer")
      subject_time = file['startTimeNanos'].to_i / 1000000000 + 
                     parms['followup_deadline_time'] -
                     parms['followup_lead_time'] -
                     Time.now.to_i
      
      RedisConnection.setex("subject_timer", subject_time, "")
      
      push('telescope', "time_to_followup", RedisConnection.ttl("subject_timer"))
    end
    
    tmp_key = uuid + "_" + tmp_key(
      observation_id, activity_id, pol, sub_channel, rendering )
    #log_entry( "Beam check:" )
    is_empty = true
    empty_beams = []
    file["beam"].each do |beam|
      beam_no   = beam['beam']
      data = beam.delete('data').to_a
      if data.nil? or data.empty? or (data-[0]).empty?
        puts "WARNING: Empty beam" 
        empty_beams << beam
      else
        is_empty = false
        tmp_data_key = uuid + "_" + tmp_data_key(observation_id, 
          activity_id, beam['polarization'], sub_channel, rendering, beam_no )
        RedisConnection.setex tmp_data_key, 
                    RedisConnection.ttl( 'subject_timer' ) + parms['data_key_buffer'], 
                    data.to_json
      end
    end 

    unless is_empty
      empty_beams.each {|beam| file['beam'].delete(beam) }
      RedisConnection.setex tmp_key,  
                    RedisConnection.ttl( 'subject_timer' ) + parms['data_key_buffer'], 
                    file.to_json
      ObservationUploader.new.perform(tmp_key)
    else
      RedisConnection.del tmp_key
    end
    push("telescope","new_data", {:url => '/subjects/', :observation_id => observation_id, :activity_id=> activity_id, :polarization=> pol}.to_json)
    #log_entry( "/subject done")
    return [201, "created succesfully"]
  rescue => ex
    puts ex.message
    f = File.open('exc_subjects.msg','a')
    f.write("EXCEPTION: #{Time.now.utc.to_s}: #{ex.class}: #{ex.message}\nBACKTRACE: #{ex.backtrace}\n\n")
    f.close
  end
end

def tmp_key(observation_id, activity_id, pol,sub_channel, rendering)
  redis_key_prefix= "tmp_new"
  "#{redis_key_prefix}_#{observation_id}_#{activity_id}_#{pol}_#{sub_channel}_#{rendering}"
end

def tmp_data_key(observation_id, activity_id, pol,sub_channel,beam_no, rendering)
  redis_key_prefix= "tmp_data_new"
  "#{redis_key_prefix}_#{observation_id}_#{activity_id}_#{pol}_#{sub_channel}_#{beam_no}_#{rendering}"
end

def push(chanel, message, data)  
  chan_prefix = Sinatra::Base.development? ? 'dmode-' : ''
  chan = chan_prefix + chanel
  begin
    Pusher[chan].trigger(message, data)
  rescue 
    puts "could not push update #{chan} #{message} #{data}"
  end
end

def log_entry( entry )
    puts entry
    f = File.open('log_entry.log','a')
    f.write( entry + ": " + Time.now.utc.to_s + "\n" )
    f.close
end  
