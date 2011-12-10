require File.dirname(__FILE__) + '/spec_helper'


describe 'The Frank App' do
  include FrankHelperMethods

  it "gives a list of active keys if any exist in the system" do
    get '/'
    last_response.should be_ok
    last_response.body.should include 'Telescope Status'
    last_response.body.should include 'Frank is currently observering '
  end
  
  # it "reports the correct telescope status on the home page"
    
  # end

  #Status tests 
  it "saves the correct status when we post it if the status is allowed" do
    ["active", "inactive"].each do |status|
      post "/status/#{status}"
      last_response.status.should == 201
      RedisConnection.get("current_status").should == status 
    end 
  end

  it "failes to save the status when we post an unallowed status " do
    ["bad_status", "gibberish"].each do |status|
      RedisConnection.set "current_status","active" 
      post "/status/#{status}"
      last_response.status.should == 406
      RedisConnection.get("current_status").should == "active" 
    end 
  end

  it "should return the current status of the telescope " do
    RedisConnection.set "current_status", "active" 
    puts "status is #{RedisConnection.get "current_status"}"
    get "/status"
    last_response.status.should == 200
    last_response.body.should  == "active" 
  end

  #Target tests
  it "On posting data should create a new target  if one didnt exist" do 
    target_id = 3
    target = example_target 
    post "/targets/#{target_id}", target
    last_response.status.should == 201
    recovered_target = JSON.parse(RedisConnection.get(target_key(target_id)))
    recovered_target.each_pair do | key ,val|
      val.to_s.should == target[key].to_s
    end
  end

  it "On posting data should not update a  target  if no data is supplied" do 
    target_id = 3
    target = example_target
    post "/targets/#{target_id}", target
    last_response.status.should == 201
    recovered_target = JSON.parse(RedisConnection.get(target_key(target_id)))
    puts recoverd_target
    puts target
    recovered_target.each_pair do | key ,val|
      puts key
      val.to_s.should == target[key].to_s
    end
  end

  it "should get the correct data when issued a get request for a target in the system" do
    target_id = 3
    target = set_up_example_target target_id
    get "/targets/#{target_id}"
    recovered_target = JSON.parse(last_response.body)
    recovered_target.each_pair do |key, val|
      val.to_s.should == target[key].to_s
    end
  end

  it "should set the current target correctly if that target exists in the system" do
    target_id = 3
    RedisConnection.set target_key(target_id), example_target
    post "/current_target/#{target_id}"
    last_response.status.should == 200
    get_current_target.should == "3" 
  end

  it "should return a 404 if the user requests a target which doesnt exist" do
    set_current_target 3 
    post "/current_target/10"
    last_response.status.should == 406
    get_current_target.should == "3" 
  end

end